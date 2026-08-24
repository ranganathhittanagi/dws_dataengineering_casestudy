# SNS topic for pipeline failure + infrastructure alerting, replacing the previous
# Gmail SMTP email path. The email subscription requires a one-time manual confirmation
# click in the recipient's inbox after `terraform apply`.

resource "aws_sns_topic" "pipeline_alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "alert_email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# Published so EC2 instances can discover the topic at boot without baking ARNs into code.
resource "aws_ssm_parameter" "alert_topic_arn" {
  name  = "${var.airflow_param_path}/alert_topic_arn"
  type  = "String"
  value = aws_sns_topic.pipeline_alerts.arn
}
