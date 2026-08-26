"""Datawarehouse layer DAG: runs after the transform layer succeeds.

Builds the VALID_TRADES warehouse table, runs pre-publication quality and
reconciliation checks, builds post-publication audit artifacts, and sends a
final status notification. Quality-gate test failures no longer block
downstream audit tasks, but the DAG is still marked failed via the final
notification task.
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.exceptions import AirflowException
from airflow.operators.python import PythonOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.state import State

from src.alerting import notify_failure, notify_success
from src.dbt_runner import run_dbt


def _build_scorecard_and_send_notification(**context):
    """Build the scorecard, then fail the DAG if any quality gate failed."""
    run_dbt(subcommand="run", selector="quality_scorecard", **context)

    dag_run = context["dag_run"]
    failed_tasks = []
    for task_id in ("trades_warehouse_dq_check", "post_publish_dq_check"):
        ti = dag_run.get_task_instance(task_id)
        if ti and ti.state == State.FAILED:
            failed_tasks.append(task_id)

    if failed_tasks:
        raise AirflowException(
            f"Data quality gate(s) failed: {', '.join(failed_tasks)}. "
            "Downstream audit tasks were allowed to run, "
            "but the DAG is marked failed."
        )

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
            "selector": "valid_trades candidate_trades_are_unique reconciliation",
        },
        on_failure_callback=None,
        execution_timeout=timedelta(minutes=15),
    )

    load_dq_rule_catalog = PythonOperator(
        task_id="load_dq_rule_catalog",
        python_callable=run_dbt,
        op_kwargs={"subcommand": "seed", "selector": "dq_rule_catalog"},
        trigger_rule="all_done",
        execution_timeout=timedelta(minutes=15),
    )

    post_publish_audit = PythonOperator(
        task_id="post_publish_audit",
        python_callable=run_dbt,
        op_kwargs={"subcommand": "run", "selector": "batch_stats reconciliation"},
        trigger_rule="all_done",
        execution_timeout=timedelta(minutes=15),
    )

    post_publish_dq_check = PythonOperator(
        task_id="post_publish_dq_check",
        python_callable=run_dbt,
        op_kwargs={
            "subcommand": "test",
            "selector": "tag:post_publish_audit",
        },
        on_failure_callback=None,
        trigger_rule="all_done",
        execution_timeout=timedelta(minutes=15),
    )

    build_scorecard_and_send_notification = PythonOperator(
        task_id="build_scorecard_and_send_notification",
        python_callable=_build_scorecard_and_send_notification,
        trigger_rule="all_done",
        execution_timeout=timedelta(minutes=20),
    )

    (
        input_transform_dataset_sensor
        >> trades_warehouse
        >> trades_warehouse_dq_check
        >> load_dq_rule_catalog
        >> post_publish_audit
        >> post_publish_dq_check
        >> build_scorecard_and_send_notification
    )
