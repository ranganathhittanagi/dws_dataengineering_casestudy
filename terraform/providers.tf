terraform {
  required_version = ">= 1.5.0"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 0.98.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Key material is read from SSM Parameter Store, so Terraform needs no local key files.
data "aws_ssm_parameter" "snowflake_private_key" {
  name            = var.snowflake_private_key_param
  with_decryption = true
}

data "aws_ssm_parameter" "service_user_public_key" {
  name            = var.service_user_public_key_param
  with_decryption = true
}

provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  role              = var.snowflake_role
  authenticator     = "JWT"
  private_key       = data.aws_ssm_parameter.snowflake_private_key.value
}
