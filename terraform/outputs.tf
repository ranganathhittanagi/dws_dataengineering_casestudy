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

output "keypair_note" {
  description = "Authentication reminder"
  value       = "Use the private key file matching the RSA public key configured on ${snowflake_user.service_user.name}."
}
