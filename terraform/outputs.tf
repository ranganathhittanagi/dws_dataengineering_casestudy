output "warehouse_name" {
  description = "Snowflake virtual warehouse"
  value       = snowflake_warehouse.warehouse.name
}

output "raw_database_name" {
  description = "Raw landing database"
  value       = snowflake_database.raw.name
}

output "transform_database_name" {
  description = "DBT transformation database"
  value       = snowflake_database.transform.name
}

output "datawarehouse_database_name" {
  description = "Data warehouse database"
  value       = snowflake_database.datawarehouse.name
}

output "raw_schema_name" {
  description = "Raw landing schema"
  value       = snowflake_schema.raw.name
}

output "transform_schema_name" {
  description = "DBT transformation schema"
  value       = snowflake_schema.transform.name
}

output "datawarehouse_schema_name" {
  description = "Data warehouse schema"
  value       = snowflake_schema.datawarehouse.name
}

output "raw_table" {
  description = "Raw trades landing table (created by DBT, not Terraform)"
  value       = "${snowflake_database.raw.name}.${snowflake_schema.raw.name}.TRADES"
}

output "raw_stage" {
  description = "Snowflake stage for raw trade files"
  value       = "${snowflake_database.raw.name}.${snowflake_schema.raw.name}.${snowflake_stage.raw_data.name}"
}

output "raw_file_format" {
  description = "Snowflake file format used by the raw stage"
  value       = "${snowflake_database.raw.name}.${snowflake_schema.raw.name}.${snowflake_file_format.csv.name}"
}

output "service_user_name" {
  description = "Service user for Airflow and DBT"
  value       = snowflake_user.service_user.name
}

output "service_role_name" {
  description = "Service role for Airflow and DBT"
  value       = snowflake_account_role.service_role.name
}

output "storage_integration_name" {
  description = "Snowflake storage integration granting access to the S3 landing prefix"
  value       = snowflake_storage_integration.s3.name
}

output "s3_stage_url" {
  description = "S3 location the external raw stage points at"
  value       = local.s3_stage_url
}

output "snowflake_integration_role_arn" {
  description = "IAM role Snowflake assumes to read from S3"
  value       = aws_iam_role.snowflake_integration.arn
}

output "snowflake_iam_user_arn" {
  description = "Snowflake-side IAM user allowed to assume the integration role"
  value       = snowflake_storage_integration.s3.storage_aws_iam_user_arn
}

output "snowflake_external_id" {
  description = "External ID enforced by the integration role's trust policy"
  value       = snowflake_storage_integration.s3.storage_aws_external_id
}

output "streaming_s3_bucket" {
  description = "S3 bucket for streaming trade files"
  value       = aws_s3_bucket.streaming_trades_source.bucket
}

output "streaming_stage" {
  description = "Snowflake stage for streaming trade files"
  value       = "${snowflake_database.raw.name}.${snowflake_schema.raw.name}.${snowflake_stage.streaming_raw_data.name}"
}

output "streaming_table" {
  description = "Bronze table for streaming trade records"
  value       = "${snowflake_database.raw.name}.${snowflake_schema.raw.name}.${snowflake_table.trades_stream.name}"
}

output "streaming_pipe" {
  description = "Snowpipe that auto-ingests streaming trade files"
  value       = "${snowflake_database.raw.name}.${snowflake_schema.raw.name}.${snowflake_pipe.trades_stream.name}"
}

output "streaming_sns_topic_arn" {
  description = "SNS topic that receives S3 event notifications for the streaming bucket"
  value       = aws_sns_topic.streaming_s3_events.arn
}

output "keypair_note" {
  description = "Authentication reminder"
  value       = "Use the private key file matching the RSA public key configured on ${snowflake_user.service_user.name}."
}

# --- EC2 deployment ---

output "airflow_url" {
  description = "Airflow webserver entry point (HTTP, restricted to the admin IP allowlist)"
  value       = "http://${aws_lb.airflow.dns_name}"
}

output "sns_alert_topic_arn" {
  description = "SNS topic receiving pipeline and infrastructure failure alerts"
  value       = aws_sns_topic.pipeline_alerts.arn
}

output "control_instance_id" {
  description = "Airflow control-plane EC2 instance (connect with: aws ssm start-session --target <id>)"
  value       = aws_instance.airflow_control.id
}

output "control_private_ip" {
  description = "Private IP of the complete Airflow control and worker instance"
  value       = aws_instance.airflow_control.private_ip
}

output "dev_instance_id" {
  description = "SSH/SSM-accessible dev-ec2-instance"
  value       = aws_instance.dev_ec2.id
}

output "dev_public_ip" {
  description = "Public IP for SSH access to dev-ec2-instance"
  value       = aws_instance.dev_ec2.public_ip
}
