"""Raw layer DAG: waits for the daily S3 trade file, ingests it into Snowflake,
and runs bronze-level data quality checks.
"""
import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor

from src.alerting import notify_failure
from src.dbt_runner import run_dbt

S3_BUCKET = os.getenv("S3_BUCKET", "trades-source-dws")
S3_PREFIX = os.getenv("S3_PREFIX", "raw/trades").strip("/")
AWS_CONN_ID = os.getenv("AWS_CONN_ID", "aws_default")


with DAG(
    dag_id="trades_raw_etl_dag",
    description="Ingest daily trade files from S3 and run raw quality checks.",
    default_args={
        "owner": "data-engineering",
        "on_failure_callback": notify_failure,
        "retries": 0,
    },
    schedule="@daily",
    start_date=datetime(2026, 8, 1),
    catchup=False,
    max_active_runs=1,
    tags=["trades", "raw", "dbt", "snowflake", "s3"],
) as dag:

    input_s3_file_sensor = S3KeySensor(
        task_id="input_s3_file_sensor",
        bucket_name=S3_BUCKET,
        bucket_key=f"{S3_PREFIX}/trades_{{{{ ds }}}}.csv",
        aws_conn_id=AWS_CONN_ID,
        poke_interval=60,
        timeout=30 * 60,
        mode="reschedule",
        soft_fail=False,
    )

    trades_raw = PythonOperator(
        task_id="trades_raw",
        python_callable=run_dbt,
        op_kwargs={"subcommand": "run", "selector": "tag:ingest"},
        retries=1,
        retry_delay=timedelta(minutes=5),
        execution_timeout=timedelta(minutes=30),
    )

    trades_raw_dq_check = PythonOperator(
        task_id="trades_raw_dq_check",
        python_callable=run_dbt,
        op_kwargs={"subcommand": "test", "selector": "tag:ingest"},
        execution_timeout=timedelta(minutes=15),
    )

    emit_raw_dataset = EmptyOperator(
        task_id="emit_raw_dataset",
        trigger_rule="all_success",
    )

    input_s3_file_sensor >> trades_raw >> trades_raw_dq_check >> emit_raw_dataset
