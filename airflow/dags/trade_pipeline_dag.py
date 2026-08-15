"""Airflow DAG to orchestrate trade file ingestion and dbt transformations.

Trade data generation is a manual, external step (run separately by an operator).
This DAG:
  1. Waits for that day's trade file to land in the local raw data directory.
  2. Uploads it to the Snowflake stage.
  3. Runs dbt models for the corresponding etl_date (blocking - failures stop the DAG).
  4. Runs dbt tests for the same etl_date (blocking - failures stop the DAG and trigger an email alert
     via Airflow's default email_on_failure behavior).
"""
import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.sensors.filesystem import FileSensor

from src.ingestion.load_to_snowflake import upload_files

TRADE_DATA_DIR = os.getenv("TRADE_DATA_DIR", "/opt/home/data/raw")
DBT_PROJECT_DIR = "/opt/home/dbt"
# Invoke the dbt venv's python directly in isolated mode (-I) so it never falls back to
# Airflow's user-site packages (~/.local), which can contain an incompatible typing_extensions
# that breaks dbt-common/mashumaro imports.
DBT_BIN = "/opt/home/dbt_venv/bin/python -I /opt/home/dbt_venv/bin/dbt"
ALERT_EMAIL_TO = [os.environ["ALERT_EMAIL_TO"]] if os.getenv("ALERT_EMAIL_TO") else []

default_args = {
    "owner": "data-engineering",
    "email": ALERT_EMAIL_TO,
    "email_on_failure": True,
    "email_on_retry": False,
    "retries": 0,
}


def _upload_to_snowflake(**context):
    """Upload the day's trade file(s) from the local landing dir to the Snowflake stage."""
    upload_files(TRADE_DATA_DIR)


with DAG(
    dag_id="trade_pipeline_dag",
    description="Ingest daily trade files into Snowflake and run dbt transformations.",
    default_args=default_args,
    schedule_interval="@daily",
    start_date=datetime(2026, 8, 1),
    catchup=False,
    max_active_runs=1,
    tags=["trades", "dbt", "snowflake"],
) as dag:

    wait_for_trade_file = FileSensor(
        task_id="wait_for_trade_file",
        filepath=f"{TRADE_DATA_DIR}/trades_{{{{ ds }}}}.csv",
        fs_conn_id="fs_default",
        poke_interval=60,
        timeout=30 * 60,
        mode="reschedule",
        soft_fail=False,
    )

    load_to_snowflake = PythonOperator(
        task_id="load_to_snowflake",
        python_callable=_upload_to_snowflake,
        retries=2,
        retry_delay=timedelta(minutes=2),
    )

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"{DBT_BIN} run --vars '{{\"etl_date\": \"{{{{ ds }}}}\"}}'"
        ),
        retries=1,
        retry_delay=timedelta(minutes=5),
        execution_timeout=timedelta(minutes=30),
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"{DBT_BIN} test --vars '{{\"etl_date\": \"{{{{ ds }}}}\"}}'"
        ),
        execution_timeout=timedelta(minutes=15),
    )

    wait_for_trade_file >> load_to_snowflake >> dbt_run >> dbt_test
