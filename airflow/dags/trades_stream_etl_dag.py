"""Streaming trades DAG.

Snowpipe auto-ingests files from s3://streaming-trades-source-dws into
RAW_DB.RAW_SCHEMA.TRADES_STREAM. This DAG runs every 15 minutes to process
new streaming records through STG_TRADES_STREAM and merge them into VALID_TRADES.
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator

from common import default_dag_args
from src.dbt_runner import run_dbt


with DAG(
    dag_id="trades_stream_etl_dag",
    description="Process streaming trades from Snowpipe into VALID_TRADES.",
    default_args=default_dag_args(retries=1, retry_delay=timedelta(minutes=2)),
    schedule=timedelta(minutes=5),
    start_date=datetime(2026, 8, 1),
    catchup=False,
    max_active_runs=1,
    tags=["trades", "streaming", "dbt", "snowpipe", "snowflake"],
) as dag:

    stream_silver = PythonOperator(
        task_id="stream_silver",
        python_callable=run_dbt,
        op_kwargs={"subcommand": "run", "selector": "tag:streaming"},
        execution_timeout=timedelta(minutes=10),
    )

    merge_stream_to_warehouse = PythonOperator(
        task_id="merge_stream_to_warehouse",
        python_callable=run_dbt,
        op_kwargs={"subcommand": "run", "selector": "valid_trades"},
        execution_timeout=timedelta(minutes=10),
    )

    emit_stream_dataset = EmptyOperator(
        task_id="emit_stream_dataset",
    )

    stream_silver >> merge_stream_to_warehouse >> emit_stream_dataset
