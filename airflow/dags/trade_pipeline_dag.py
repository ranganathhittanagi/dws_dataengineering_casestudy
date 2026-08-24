"""Airflow DAG orchestrating S3-sourced trade ingestion and dbt transformations.

Trade files are uploaded to the S3 landing prefix out of band (manual step today).
This DAG:
  1. Waits for that day's trade file to land in S3.
  2. Runs dbt models for the corresponding etl_date. The raw model COPY INTOs the
     bronze table straight from the S3 external stage, so no bytes move through
     Airflow (blocking - failures stop the DAG).
  3. Runs dbt tests for the same etl_date (blocking - failures stop the DAG and trigger
     an email alert via Airflow's default email_on_failure behavior).

The Snowflake private key is pulled from AWS SSM Parameter Store at task runtime and
passed to dbt as a process environment variable, so it never lands on disk or in XCom.
"""
import os
import subprocess
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor

from src.config import dbt_environment

DBT_PROJECT_DIR = "/opt/home/dbt"
# Invoke the dbt venv's python directly in isolated mode (-I) so it never falls back to
# Airflow's user-site packages (~/.local), which can contain an incompatible typing_extensions
# that breaks dbt-common/mashumaro imports.
DBT_BIN = ["/opt/home/dbt_venv/bin/python", "-I", "/opt/home/dbt_venv/bin/dbt"]

S3_BUCKET = os.getenv("S3_BUCKET", "trades-source-dws")
S3_PREFIX = os.getenv("S3_PREFIX", "raw/trades").strip("/")
AWS_CONN_ID = os.getenv("AWS_CONN_ID", "aws_default")
ALERT_EMAIL_TO = [os.environ["ALERT_EMAIL_TO"]] if os.getenv("ALERT_EMAIL_TO") else []

default_args = {
    "owner": "data-engineering",
    "email": ALERT_EMAIL_TO,
    "email_on_failure": True,
    "email_on_retry": False,
    "retries": 0,
}


def _run_dbt(subcommand: str, **context):
    """Run a dbt subcommand with the private key sourced from SSM Parameter Store."""
    etl_date = context["ds"]
    command = DBT_BIN + [subcommand, "--vars", f'{{"etl_date": "{etl_date}"}}']
    env = {**os.environ, **dbt_environment()}
    result = subprocess.run(command, cwd=DBT_PROJECT_DIR, env=env, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"dbt {subcommand} failed with exit code {result.returncode}")


with DAG(
    dag_id="trade_pipeline_dag",
    description="Ingest daily trade files from S3 into Snowflake and run dbt transformations.",
    default_args=default_args,
    schedule_interval="@daily",
    start_date=datetime(2026, 8, 1),
    catchup=False,
    max_active_runs=1,
    tags=["trades", "dbt", "snowflake", "s3"],
) as dag:

    wait_for_trade_file = S3KeySensor(
        task_id="wait_for_trade_file",
        bucket_name=S3_BUCKET,
        bucket_key=f"{S3_PREFIX}/trades_{{{{ ds }}}}.csv",
        aws_conn_id=AWS_CONN_ID,
        poke_interval=60,
        timeout=30 * 60,
        mode="reschedule",
        soft_fail=False,
    )

    dbt_run = PythonOperator(
        task_id="dbt_run",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "run"},
        retries=1,
        retry_delay=timedelta(minutes=5),
        execution_timeout=timedelta(minutes=30),
    )

    dbt_test = PythonOperator(
        task_id="dbt_test",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "test"},
        execution_timeout=timedelta(minutes=15),
    )

    wait_for_trade_file >> dbt_run >> dbt_test
