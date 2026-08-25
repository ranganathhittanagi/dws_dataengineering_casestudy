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

variable "snowflake_private_key_param" {
  description = "SSM SecureString parameter holding the admin (snowflake_user) RSA private key Terraform authenticates with"
  type        = string
  default     = "/dws/snowflake/admin/private_key"
}

variable "snowflake_role" {
  description = "Snowflake role to use for Terraform provisioning"
  type        = string
  default     = "DWS_SERVICE_ROLE"
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

# AWS / S3 source
variable "aws_region" {
  description = "AWS region hosting the S3 landing bucket and SSM parameters"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile used by Terraform. Leave null to use the default credential chain (e.g. an IAM role)."
  type        = string
  default     = null
}

variable "s3_bucket_name" {
  description = "Existing S3 bucket holding raw trade files"
  type        = string
  default     = "trades-source-dws"
}

variable "s3_source_prefix" {
  description = "Key prefix within the bucket where trade files land"
  type        = string
  default     = "raw/trades"
}

variable "storage_integration_name" {
  description = "Name of the Snowflake storage integration for S3"
  type        = string
  default     = "S3_TRADES_INTEGRATION"
}

variable "snowflake_integration_role_name" {
  description = "Name of the IAM role Snowflake assumes to read from S3"
  type        = string
  default     = "snowflake-trades-s3-access"
}

variable "service_user_public_key_param" {
  description = "SSM parameter holding the service user's RSA public key PEM"
  type        = string
  default     = "/dws/snowflake/dws-service-user/public_key"
}

# --- EC2 deployment (Airflow CeleryExecutor across two instances) ---

variable "project_name" {
  description = "Prefix applied to AWS resource names for this deployment"
  type        = string
  default     = "dws-airflow"
}

variable "vpc_cidr" {
  description = "CIDR block for the pipeline VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "admin_ip_allowlist" {
  description = "CIDR blocks allowed to reach the Airflow webserver via the ALB. Defaults to open (0.0.0.0/0); override in terraform.tfvars to restrict."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "control_instance_type" {
  description = "Instance type for the Airflow control plane (webserver+scheduler+Postgres+Redis). t3.small (2GB) is the realistic minimum; t3.micro fits free tier but will swap heavily."
  type        = string
  default     = "t3.small"
}

variable "dev_instance_type" {
  description = "Instance type for dev-ec2-instance (SSH-accessible ad hoc development box)"
  type        = string
  default     = "t3.micro"
}

variable "dev_ssh_public_key_path" {
  description = "Local path to the SSH public key registered for dev-ec2-instance"
  type        = string
  default     = "~/.ssh/dws-dev-ec2.pub"
}

variable "dev_ssh_cidr" {
  description = "CIDR allowed to SSH to dev-ec2-instance"
  type        = string
  default     = "106.51.217.210/32"
}

variable "idle_cpu_threshold" {
  description = "Average CPU % below which an EC2 instance is considered idle and auto-stopped by CloudWatch"
  type        = number
  default     = 5
}

variable "idle_evaluation_periods" {
  description = "Number of 15-minute periods with low CPU before CloudWatch triggers an EC2 stop (e.g. 2 = 30 minutes)"
  type        = number
  default     = 2
}

variable "repo_url" {
  description = "HTTPS git URL of this repository, cloned onto the instances at boot (must be public or reachable without credentials)"
  type        = string
}

variable "repo_branch" {
  description = "Git branch deployed to the instances"
  type        = string
  default     = "master"
}

variable "airflow_param_path" {
  description = "SSM parameter path prefix for Airflow runtime secrets/discovery values"
  type        = string
  default     = "/dws/airflow"
}

variable "alert_emails" {
  description = "Email addresses subscribed to the SNS alert topic (each must confirm the subscription email once)"
  type        = list(string)
}
