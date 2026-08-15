# Admin credentials used only by Terraform to provision resources.
variable "snowflake_organization_name" {
  description = "Snowflake organization name (e.g., YTQEMJI)"
  type        = string
  default     = "YTQEMJI"
}

variable "snowflake_account_name" {
  description = "Snowflake account name (e.g., TW17096)"
  type        = string
  default     = "TW17096"
}

variable "snowflake_user" {
  description = "Snowflake admin user name"
  type        = string
}

variable "snowflake_password" {
  description = "Snowflake admin user password"
  type        = string
  sensitive   = true
}

variable "snowflake_role" {
  description = "Snowflake role to use (e.g., ACCOUNTADMIN)"
  type        = string
  default     = "ACCOUNTADMIN"
}

# Resource names
variable "warehouse_name" {
  description = "Name of the Snowflake virtual warehouse"
  type        = string
  default     = "COMPUTE_WH"
}

variable "raw_database_name" {
  description = "Name of the raw landing database"
  type        = string
  default     = "RAW_DB"
}

variable "raw_schema_name" {
  description = "Name of the raw landing schema"
  type        = string
  default     = "RAW_SCHEMA"
}

variable "transform_database_name" {
  description = "Name of the DBT transformation database"
  type        = string
  default     = "TRANSFORM_DB"
}

variable "transform_schema_name" {
  description = "Name of the DBT transformation schema"
  type        = string
  default     = "TRANSFORM_SCHEMA"
}

variable "datawarehouse_database_name" {
  description = "Name of the data warehouse database"
  type        = string
  default     = "DATAWAREHOUSE_DB"
}

variable "datawarehouse_schema_name" {
  description = "Name of the data warehouse schema"
  type        = string
  default     = "DATAWAREHOUSE_SCHEMA"
}

variable "compliance_database_name" {
  description = "Name of the compliance database for rejected trades and audit logs"
  type        = string
  default     = "COMPLIANCE_DB"
}

variable "compliance_schema_name" {
  description = "Name of the schema for rejected trades"
  type        = string
  default     = "COMPLIANCE_SCHEMA"
}

variable "service_user_name" {
  description = "Name of the service user used by Airflow and DBT"
  type        = string
  default     = "DWS_SERVICE_USER"
}

variable "service_role_name" {
  description = "Name of the service role used by Airflow and DBT"
  type        = string
  default     = "DWS_SERVICE_ROLE"
}

variable "service_user_public_key_file" {
  description = "Path to the service user's RSA public key PEM file (relative to the terraform directory)"
  type        = string
  default     = "../secrets/rsa_key.pub"
}
