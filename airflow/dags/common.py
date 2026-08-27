"""Shared helpers for Airflow DAGs in the trades pipeline."""
from datetime import timedelta

from airflow.utils.state import State
from src.alerting import notify_failure


def default_dag_args(retries: int = 0, retry_delay: timedelta | None = None) -> dict:
    """Return the common default_args used by all pipeline DAGs."""
    args = {
        "owner": "data-engineering",
        "on_failure_callback": notify_failure,
        "retries": retries,
    }
    if retry_delay is not None:
        args["retry_delay"] = retry_delay
    return args


def sensor_defaults(
    poke_interval: int = 60,
    timeout: int = 30 * 60,
    mode: str = "reschedule",
) -> dict:
    """Return common kwargs for ExternalTaskSensor / S3KeySensor."""
    return {
        "poke_interval": poke_interval,
        "timeout": timeout,
        "mode": mode,
    }


# Convenience re-export for DAG task state checks.
TASK_SUCCESS = State.SUCCESS
