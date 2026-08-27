"""Pipeline alerting via AWS SNS.

Airflow invokes `notify_failure` as an `on_failure_callback` when a task fails,
and `notify_success` as a regular final task when the quality-gated DAG completes.

All messages are structured with run/batch context and are published without
secret values or raw sensitive payloads.
"""
import logging
import os

logger = logging.getLogger(__name__)

SNS_SUBJECT_MAX_LEN = 100  # hard SNS limit


def _publish(topic_arn: str, subject: str, message: str) -> None:
    """Publish a message to SNS, swallowing errors so alerting never masks task state."""
    try:
        from airflow.providers.amazon.aws.hooks.sns import SnsHook
        SnsHook(aws_conn_id=os.getenv("AWS_CONN_ID", "aws_default")).publish_to_target(
            target_arn=topic_arn, message=message, subject=subject
        )
    except Exception:
        logger.exception("Failed to publish SNS alert.")


def notify_failure(context: dict) -> None:
    """Publish a structured task-failure alert to the SNS topic."""
    topic_arn = os.getenv("SNS_ALERT_TOPIC_ARN")
    if not topic_arn:
        logger.warning("SNS_ALERT_TOPIC_ARN is not set; skipping failure alert.")
        return

    task_instance = context.get("task_instance")
    dag_id = getattr(context.get("dag"), "dag_id", "unknown")
    task_id = getattr(task_instance, "task_id", "unknown")
    execution_date = context.get("ds", "unknown")
    log_url = getattr(task_instance, "log_url", "unavailable")
    exception = context.get("exception")
    try_number = getattr(task_instance, "try_number", "n/a")

    subject = f"[Airflow] {dag_id}.{task_id} failed ({execution_date})"[:SNS_SUBJECT_MAX_LEN]
    message = (
        f"Airflow data-quality failure\n"
        f"-----------------------------\n"
        f"Type:           data_quality_failure\n"
        f"DAG:            {dag_id}\n"
        f"Task:           {task_id}\n"
        f"Execution date: {execution_date}\n"
        f"Try number:     {try_number}\n"
        f"Log URL:        {log_url}\n"
        f"Exception:      {exception}\n"
        f"\nVALID_TRADES was not updated. Investigate the failed quality gate before reprocessing.\n"
    )

    _publish(topic_arn, subject, message)
    logger.info("Published failure alert for %s.%s to %s", dag_id, task_id, topic_arn)


def notify_success(context: dict) -> None:
    """Publish a structured success summary to the SNS topic after the batch passes."""
    topic_arn = os.getenv("SNS_ALERT_TOPIC_ARN")
    if not topic_arn:
        logger.warning("SNS_ALERT_TOPIC_ARN is not set; skipping success alert.")
        return

    dag_id = getattr(context.get("dag"), "dag_id", "unknown")
    execution_date = context.get("ds", "unknown")
    run_id = context.get("run_id", "unknown")

    subject = f"[Airflow] {dag_id} passed ({execution_date})"[:SNS_SUBJECT_MAX_LEN]
    message = (
        f"Airflow data-quality success\n"
        f"----------------------------\n"
        f"Type:           data_quality_success\n"
        f"DAG:            {dag_id}\n"
        f"Execution date: {execution_date}\n"
        f"Run ID:         {run_id}\n"
        f"Status:         all quality gates passed; batch published to VALID_TRADES\n"
        f"\nThe quality scorecard and control totals are available in COMPLIANCE_DB.DQ_OBSERVABILITY.\n"
    )

    _publish(topic_arn, subject, message)
    logger.info("Published success alert for %s to %s", dag_id, topic_arn)
