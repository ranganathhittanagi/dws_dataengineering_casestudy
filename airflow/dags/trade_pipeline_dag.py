"""Airflow DAG orchestrating S3-sourced trade ingestion with staged quality gates.

Every batch:
  1. Waits for the daily trade file in S3.
  2. Loads raw rows from the external stage (copy_into_table).
  3. Runs bronze/raw quality checks.
  4. Normalizes and quarantines invalid rows.
  5. Runs transform quality checks.
  6. Builds warehouse candidates.
  7. Runs warehouse/reconciliation quality checks.
  8. Publishes only tested candidates to VALID_TRADES.
  9. Builds post-publication audit artifacts and scorecards.
  10. Sends a structured success or failure notification.

A failing quality gate stops the DAG before the publish task, leaving
VALID_TRADES unchanged from the previous successful run.
"""
import os
import subprocess
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor

from src.alerting import notify_failure, notify_success
from src.config import dbt_environment

DBT_PROJECT_DIR = "/opt/home/dbt"
DBT_BIN = ["/opt/home/dbt_venv/bin/python", "-I", "/opt/home/dbt_venv/bin/dbt"]

S3_BUCKET = os.getenv("S3_BUCKET", "trades-source-dws")
S3_PREFIX = os.getenv("S3_PREFIX", "raw/trades").strip("/")
AWS_CONN_ID = os.getenv("AWS_CONN_ID", "aws_default")


def _run_dbt(subcommand: str, selector: str, **context):
    """Run a dbt subcommand with a selector and the SSM-sourced private key."""
    etl_date = context["ds"]
    command = (
        DBT_BIN
        + [subcommand, "--select"]
        + selector.split()
        + ["--vars", f'{{"etl_date": "{etl_date}"}}']
    )
    env = {**os.environ, **dbt_environment()}
    result = subprocess.run(command, cwd=DBT_PROJECT_DIR, env=env, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"dbt {subcommand} --select {selector} failed with exit code {result.returncode}")


with DAG(
    dag_id="trade_pipeline_dag",
    description="Ingest daily trade files from S3 with staged dbt quality gates.",
    default_args={
        "owner": "data-engineering",
        "on_failure_callback": notify_failure,
        "retries": 0,
    },
    schedule_interval="@daily",
    start_date=datetime(2026, 8, 1),
    catchup=False,
    max_active_runs=1,
    tags=["trades", "dbt", "snowflake", "s3", "quality"],
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

    raw_ingest = PythonOperator(
        task_id="raw_ingest",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "run", "selector": "tag:ingest"},
        retries=1,
        retry_delay=timedelta(minutes=5),
        execution_timeout=timedelta(minutes=30),
    )

    raw_quality = PythonOperator(
        task_id="raw_quality",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "test", "selector": "tag:ingest"},
        execution_timeout=timedelta(minutes=15),
    )

    transform_models = PythonOperator(
        task_id="transform_models",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "run", "selector": "tag:prepare_quality"},
        execution_timeout=timedelta(minutes=30),
    )

    transform_quality = PythonOperator(
        task_id="transform_quality",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "test", "selector": "tag:prepare_quality"},
        execution_timeout=timedelta(minutes=15),
    )

    warehouse_candidate = PythonOperator(
        task_id="warehouse_candidate",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "run", "selector": "tag:warehouse_candidate"},
        execution_timeout=timedelta(minutes=30),
    )

    reconciliation = PythonOperator(
        task_id="reconciliation",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "run", "selector": "reconciliation"},
        execution_timeout=timedelta(minutes=15),
    )

    warehouse_quality = PythonOperator(
        task_id="warehouse_quality",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "test", "selector": "candidate_valid_trades candidate_trades_are_unique reconciliation"},
        execution_timeout=timedelta(minutes=15),
    )

    publish = PythonOperator(
        task_id="publish",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "run", "selector": "tag:publish"},
        execution_timeout=timedelta(minutes=30),
    )

    post_publish_audit = PythonOperator(
        task_id="post_publish_audit",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "run", "selector": "tag:post_publish_audit"},
        execution_timeout=timedelta(minutes=15),
    )

    post_publish_quality = PythonOperator(
        task_id="post_publish_quality",
        python_callable=_run_dbt,
        op_kwargs={"subcommand": "test", "selector": "tag:post_publish_audit"},
        execution_timeout=timedelta(minutes=15),
    )

    quality_notification = PythonOperator(
        task_id="quality_notification",
        python_callable=notify_success,
        trigger_rule="all_success",
    )

    (
        wait_for_trade_file
        >> raw_ingest
        >> raw_quality
        >> transform_models
        >> transform_quality
        >> warehouse_candidate
        >> reconciliation
        >> warehouse_quality
        >> publish
        >> post_publish_audit
        >> post_publish_quality
        >> quality_notification
    )
