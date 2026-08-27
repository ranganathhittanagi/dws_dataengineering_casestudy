# Consumer roles and the access-control schema that houses entitlements and
# Snowflake dynamic data masking / row access policies.
# The policies themselves are created and applied by dbt macros; Terraform only
# provisions the roles, schemas, and base grants.

locals {
  consumer_role_names = toset(var.consumer_role_names)
  consumer_databases  = toset([var.raw_database_name, var.transform_database_name, var.datawarehouse_database_name, var.compliance_database_name])
  consumer_schemas = toset([
    "${var.raw_database_name}.${var.raw_schema_name}",
    "${var.transform_database_name}.${var.transform_schema_name}",
    "${var.datawarehouse_database_name}.${var.datawarehouse_schema_name}",
    "${var.compliance_database_name}.${var.compliance_schema_name}",
    "${var.compliance_database_name}.${snowflake_schema.access_control.name}",
    "${var.compliance_database_name}.DQ_OBSERVABILITY",
  ])
}

resource "snowflake_schema" "access_control" {
  name     = var.access_control_schema_name
  database = snowflake_database.compliance.name
}

# The service role creates/manages policies and the currency entitlement seed.
resource "snowflake_grant_privileges_to_account_role" "service_access_control_all" {
  all_privileges    = true
  account_role_name = snowflake_account_role.service_role.name
  on_schema {
    schema_name = "${snowflake_database.compliance.name}.${snowflake_schema.access_control.name}"
  }
  depends_on = [snowflake_schema.access_control]
}

# Consumer roles
resource "snowflake_account_role" "consumer" {
  for_each = local.consumer_role_names
  name     = each.value
}

resource "snowflake_grant_privileges_to_account_role" "consumer_warehouse" {
  for_each          = local.consumer_role_names
  privileges        = ["USAGE"]
  account_role_name = each.value
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.warehouse_name
  }
  depends_on = [snowflake_account_role.consumer]
}

resource "snowflake_grant_privileges_to_account_role" "consumer_database_usage" {
  for_each = {
    for pair in setproduct(local.consumer_role_names, local.consumer_databases) : "${pair[0]}-${pair[1]}" => {
      role = pair[0]
      db   = pair[1]
    }
  }
  privileges        = ["USAGE"]
  account_role_name = each.value.role
  on_account_object {
    object_type = "DATABASE"
    object_name = each.value.db
  }
  depends_on = [snowflake_account_role.consumer]
}

resource "snowflake_grant_privileges_to_account_role" "consumer_schema_usage" {
  for_each = {
    for pair in setproduct(local.consumer_role_names, local.consumer_schemas) : "${pair[0]}-${pair[1]}" => {
      role   = pair[0]
      schema = pair[1]
    }
  }
  privileges        = ["USAGE"]
  account_role_name = each.value.role
  on_schema {
    schema_name = each.value.schema
  }
  depends_on = [snowflake_account_role.consumer, snowflake_schema.access_control]
}

# Table-level SELECT is applied by dbt grants after the models are built.
