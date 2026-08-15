locals {
  raw_public_key = file(var.service_user_public_key_file)
  service_user_public_key = trimspace(
    replace(
      replace(
        replace(local.raw_public_key, "-----BEGIN PUBLIC KEY-----", ""),
        "-----END PUBLIC KEY-----", ""
      ),
      "\n", ""
    )
  )
}

resource "snowflake_warehouse" "warehouse" {
  name           = var.warehouse_name
  warehouse_size = "XSMALL"
  auto_suspend   = 60
  auto_resume    = true
}

resource "snowflake_database" "raw" {
  name = var.raw_database_name
}

resource "snowflake_database" "transform" {
  name = var.transform_database_name
}

resource "snowflake_database" "datawarehouse" {
  name = var.datawarehouse_database_name
}

resource "snowflake_schema" "raw" {
  name     = var.raw_schema_name
  database = snowflake_database.raw.name
}

resource "snowflake_schema" "transform" {
  name     = var.transform_schema_name
  database = snowflake_database.transform.name
}

resource "snowflake_schema" "datawarehouse" {
  name     = var.datawarehouse_schema_name
  database = snowflake_database.datawarehouse.name
}

resource "snowflake_database" "compliance" {
  name = var.compliance_database_name
}

resource "snowflake_schema" "compliance" {
  name     = var.compliance_schema_name
  database = snowflake_database.compliance.name
}

resource "snowflake_account_role" "service_role" {
  name = var.service_role_name
}

resource "snowflake_user" "service_user" {
  name              = var.service_user_name
  rsa_public_key    = local.service_user_public_key
  default_role      = snowflake_account_role.service_role.name
  default_warehouse = snowflake_warehouse.warehouse.name
  default_namespace = "${snowflake_database.raw.name}.${snowflake_schema.raw.name}"
}

resource "snowflake_grant_account_role" "service_role_to_user" {
  role_name = snowflake_account_role.service_role.name
  user_name = snowflake_user.service_user.name
}

resource "snowflake_grant_account_role" "service_role_to_sysadmin" {
  role_name        = snowflake_account_role.service_role.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_privileges_to_account_role" "warehouse_usage" {
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.service_role.name
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.warehouse.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  for_each   = toset([var.raw_database_name, var.transform_database_name, var.datawarehouse_database_name, var.compliance_database_name])
  privileges = ["USAGE", "CREATE SCHEMA"]
  account_role_name = snowflake_account_role.service_role.name
  on_account_object {
    object_type = "DATABASE"
    object_name = each.value
  }
  depends_on = [
    snowflake_database.raw,
    snowflake_database.transform,
    snowflake_database.datawarehouse,
    snowflake_database.compliance,
  ]
}

resource "snowflake_grant_privileges_to_account_role" "schema_all" {
  for_each = toset([
    "${var.raw_database_name}.${var.raw_schema_name}",
    "${var.transform_database_name}.${var.transform_schema_name}",
    "${var.datawarehouse_database_name}.${var.datawarehouse_schema_name}",
    "${var.compliance_database_name}.${var.compliance_schema_name}",
  ])
  all_privileges    = true
  account_role_name = snowflake_account_role.service_role.name
  on_schema {
    schema_name = each.value
  }
  depends_on = [
    snowflake_schema.raw,
    snowflake_schema.transform,
    snowflake_schema.datawarehouse,
    snowflake_schema.compliance,
  ]
}

resource "snowflake_file_format" "csv" {
  name        = "CSV_FORMAT"
  database    = snowflake_database.raw.name
  schema      = snowflake_schema.raw.name
  format_type = "CSV"
  compression = "AUTO"
  skip_header = 1
}

resource "snowflake_stage" "raw_data" {
  name        = "RAW_DATA_STAGE"
  database    = snowflake_database.raw.name
  schema      = snowflake_schema.raw.name
  file_format = "FORMAT_NAME = ${snowflake_database.raw.name}.${snowflake_schema.raw.name}.${snowflake_file_format.csv.name}"
  depends_on  = [snowflake_file_format.csv]
}

resource "snowflake_grant_privileges_to_account_role" "file_format_usage" {
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.service_role.name
  on_schema_object {
    object_type = "FILE FORMAT"
    object_name = "${var.raw_database_name}.${var.raw_schema_name}.${snowflake_file_format.csv.name}"
  }
  depends_on = [snowflake_file_format.csv]
}

resource "snowflake_grant_privileges_to_account_role" "stage_usage" {
  privileges        = ["READ", "WRITE"]
  account_role_name = snowflake_account_role.service_role.name
  on_schema_object {
    object_type = "STAGE"
    object_name = "${var.raw_database_name}.${var.raw_schema_name}.${snowflake_stage.raw_data.name}"
  }
  depends_on = [snowflake_stage.raw_data]
}
