"""Datawarehouse layer DAG: runs after the transform layer succeeds.

Builds warehouse candidates, runs pre-publication quality and reconciliation
checks, publishes VALID_TRADES, builds post-publication audit artifacts, and
sends a structured success notification.
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.state import State

from src.alerting import notify_failure, notify_success
from src.dbt_runner import run_dbt


def _send_quality_notification(**context):
    """Pass the Airflow context to notify_success."""
    return notify_success(context)


with DAG(
    dag_id="trades_datawarehouse_etl_dag",
    description="Build warehouse candidates, quality-gate, publish and audit.",
    default_args={
        "owner": "data-engineering",
        "on_failure_callback": notify_failure,
        "retries": 0,
    },
    schedule="@daily",
    start_date=datetime(2026, 8, 1),
    catchup=False,
    max_active_runs=1,
    tags=["trades", "datawarehouse", "dbt", "snowflake"],
) as dag:

    input_transform_dataset_sensor = ExternalTaskSensor(
        task_id="input_transform_dataset_sensor",
        external_dag_id="trades_transform_etl_dag",
        external_task_id="emit_transform_dataset",
        allowed_states=[State.SUCCESS],
        execution_delta=timedelta(days=0),
        poke_interval=60,
        timeout=30 * 60,
        mode="reschedule",
    )

    trades_warehouse = PythonOperator(
        task_id="trades_warehouse",
        python_callable=run_dbt,
        op_kwargs={
            "subcommand": "run",
            "selector": "tag:warehouse_candidate reconciliation",
        },
        retries=1,
        retry_delay=timedelta(minutes=5),
        execution_timeout=timedelta(minutes=30),
    )

    trades_warehouse_dq_check = PythonOperator(
        task_id="trades_warehouse_dq_check",
        python_callable=run_dbt,
        op_kwargs={
            "subcommand": "test",
            "selector": "candidate_valid_trades candidate_trades_are_unique reconciliation",
        },
        execution_timeout=timedelta(minutes=15),
    )

    publish_valid_trades = PythonOperator(
        task_id="publish_valid_trades",
        python_callable=run_dbt,
        op_kwargs={"subcommand": "run", "selector": "tag:publish"},
        execution_timeout=timedelta(minutes=30),
    )

    post_publish_audit = PythonOperator(
        task_id="post_publish_audit",
        python_callable=run_dbt,
        op_kwargs={"subcommand": "run", "selector": "tag:post_publish_audit"},
        execution_timeout=timedelta(minutes=15),
    )

    post_publish_dq_check = PythonOperator(
        task_id="post_publish_dq_check",
        python_callable=run_dbt,
        op_kwargs={
            "subcommand": "test",
            "selector": "tag:post_publish_audit",
        },
        execution_timeout=timedelta(minutes=15),
    )

    send_quality_notification = PythonOperator(
        task_id="send_quality_notification",
        python_callable=_send_quality_notification,
        trigger_rule="all_success",
        execution_timeout=timedelta(minutes=5),
    )

    (
        input_transform_dataset_sensor
        >> trades_warehouse
        >> trades_warehouse_dq_check
        >> publish_valid_trades
        >> post_publish_audit
        >> post_publish_dq_check
        >> send_quality_notification
    )
