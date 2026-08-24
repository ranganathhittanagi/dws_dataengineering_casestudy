# Wires the existing S3 landing bucket to Snowflake via a storage integration.
#
# Snowflake and IAM have a circular dependency: the integration needs the IAM role ARN,
# and the role's trust policy needs the IAM user ARN + external ID that Snowflake only
# generates once the integration exists. The cycle is broken by composing the role ARN
# from the account ID instead of referencing the aws_iam_role resource.

data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "trades_source" {
  bucket = var.s3_bucket_name
}

locals {
  snowflake_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.snowflake_integration_role_name}"
  s3_stage_url       = "s3://${var.s3_bucket_name}/${trimsuffix(var.s3_source_prefix, "/")}/"
}

resource "snowflake_storage_integration" "s3" {
  name                      = var.storage_integration_name
  type                      = "EXTERNAL_STAGE"
  storage_provider          = "S3"
  storage_aws_role_arn      = local.snowflake_role_arn
  storage_allowed_locations = [local.s3_stage_url]
  enabled                   = true
  comment                   = "Read-only access to the trades landing prefix in S3."
}

# Least-privilege read access for Snowflake: only the trades prefix, no writes.
data "aws_iam_policy_document" "snowflake_s3_read" {
  statement {
    sid    = "ReadTradeObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    resources = ["${data.aws_s3_bucket.trades_source.arn}/${trimsuffix(var.s3_source_prefix, "/")}/*"]
  }

  statement {
    sid       = "ListTradePrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [data.aws_s3_bucket.trades_source.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${trimsuffix(var.s3_source_prefix, "/")}/*"]
    }
  }
}

data "aws_iam_policy_document" "snowflake_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [snowflake_storage_integration.s3.storage_aws_iam_user_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [snowflake_storage_integration.s3.storage_aws_external_id]
    }
  }
}

resource "aws_iam_role" "snowflake_integration" {
  name               = var.snowflake_integration_role_name
  description        = "Assumed by Snowflake to read trade files from the S3 landing bucket."
  assume_role_policy = data.aws_iam_policy_document.snowflake_assume_role.json
}

resource "aws_iam_role_policy" "snowflake_s3_read" {
  name   = "${var.snowflake_integration_role_name}-s3-read"
  role   = aws_iam_role.snowflake_integration.id
  policy = data.aws_iam_policy_document.snowflake_s3_read.json
}

# IAM trust policy changes can take up to ~1 minute to propagate globally. Without this,
# Snowflake's validation of the storage integration/stage can race ahead of AWS and fail
# with "not authorized to perform: sts:AssumeRole" even though the config is correct.
resource "time_sleep" "wait_for_iam_propagation" {
  depends_on      = [aws_iam_role.snowflake_integration, aws_iam_role_policy.snowflake_s3_read]
  create_duration = "30s"
}

resource "snowflake_grant_privileges_to_account_role" "storage_integration_usage" {
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.service_role.name

  on_account_object {
    object_type = "INTEGRATION"
    object_name = snowflake_storage_integration.s3.name
  }
}
