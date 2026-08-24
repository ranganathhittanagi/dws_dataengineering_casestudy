"""Pipeline failure alerting via AWS SNS (replaces the previous SMTP email path).

Airflow invokes `notify_failure` as an `on_failure_callback` when a task instance
reaches its final failed state (i.e. after retries are exhausted) - the same trigger
point as the old `email_on_failure` behaviour. The SNS topic fans out to the email
subscription(s) managed in Terraform (terraform/sns.tf).

Auth follows the same pattern as the rest of the pipeline: the SnsHook resolves AWS
credentials through the `aws_default` connection / boto3 default chain (an instance
role on EC2, a local profile in development).
"""
import logging
import os

logger = logging.getLogger(__name__)

SNS_SUBJECT_MAX_LEN = 100  # hard SNS limit


def notify_failure(context: dict) -> None:
    """Publish a task-failure alert to the SNS topic. Never raises: alerting must not
    mask or compound the original task failure."""
    topic_arn = os.getenv("SNS_ALERT_TOPIC_ARN")
    if not topic_arn:
        logger.warning("SNS_ALERT_TOPIC_ARN is not set; skipping failure alert.")
        return

    try:
        from airflow.providers.amazon.aws.hooks.sns import SnsHook

        task_instance = context.get("task_instance")
        dag_id = getattr(context.get("dag"), "dag_id", "unknown")
        task_id = getattr(task_instance, "task_id", "unknown")
        execution_date = context.get("ds", "unknown")
        log_url = getattr(task_instance, "log_url", "unavailable")
        exception = context.get("exception")

        subject = f"[Airflow] {dag_id}.{task_id} failed ({execution_date})"[:SNS_SUBJECT_MAX_LEN]
        message = (
            f"Airflow task failure\n"
            f"--------------------\n"
            f"DAG:            {dag_id}\n"
            f"Task:           {task_id}\n"
            f"Execution date: {execution_date}\n"
            f"Try number:     {getattr(task_instance, 'try_number', 'n/a')}\n"
            f"Log URL:        {log_url}\n"
            f"Exception:      {exception}\n"
        )

        SnsHook(aws_conn_id=os.getenv("AWS_CONN_ID", "aws_default")).publish_to_target(
            target_arn=topic_arn, message=message, subject=subject
        )
        logger.info("Published failure alert for %s.%s to %s", dag_id, task_id, topic_arn)
    except Exception:
        logger.exception("Failed to publish SNS failure alert.")
