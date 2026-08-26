"""Transform layer DAG: runs after the raw layer succeeds.

Normalizes and validates trades, produces a quarantine audit trail, and emits a
dataset marker that the datawarehouse layer waits on.
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.state import State

from src.alerting import notify_failure
from src.dbt_runner import run_dbt


with DAG(
    dag_id="trades_transform_etl_dag",
    description="Transform and validate raw trades, then emit transform dataset.",
    default_args={
        "owner": "data-engineering",
        "on_failure_callback": notify_failure,
        "retries": 0,
    },
    schedule="@daily",
    start_date=datetime(2026, 8, 1),
    catchup=False,
    max_active_runs=1,
    tags=["trades", "transform", "dbt", "snowflake"],
) as dag:

    input_raw_dataset_sensor = ExternalTaskSensor(
        task_id="input_raw_dataset_sensor",
        external_dag_id="trades_raw_etl_dag",
        external_task_id="emit_raw_dataset",
        allowed_states=[State.SUCCESS],
        execution_delta=timedelta(days=0),
        poke_interval=60,
        timeout=30 * 60,
        mode="reschedule",
    )

    trades_transform = PythonOperator(
        task_id="trades_transform",
        python_callable=run_dbt,
        op_kwargs={"subcommand": "run", "selector": "tag:prepare_quality"},
        retries=1,
        retry_delay=timedelta(minutes=5),
        execution_timeout=timedelta(minutes=30),
    )

    trades_transform_dq_check = PythonOperator(
        task_id="trades_transform_dq_check",
        python_callable=run_dbt,
        op_kwargs={"subcommand": "test", "selector": "tag:prepare_quality"},
        execution_timeout=timedelta(minutes=15),
    )

    emit_transform_dataset = EmptyOperator(
        task_id="emit_transform_dataset",
    )

    input_raw_dataset_sensor >> trades_transform >> trades_transform_dq_check >> emit_transform_dataset
