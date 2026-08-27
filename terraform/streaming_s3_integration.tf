# Streaming ingestion pipeline: S3 -> S3 event notification -> SNS -> Snowpipe -> TRADES_STREAM.
#
# Files land in s3://streaming-trades-source-dws/raw/trades/ and are auto-loaded by
# Snowpipe into RAW_DB.RAW_SCHEMA.TRADES_STREAM. A separate dbt model
# (STG_TRADES_STREAM) reads the bronze table and is merged into VALID_TRADES.

locals {
  streaming_snowflake_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.streaming_snowflake_role_name}"
  streaming_s3_stage_url       = "s3://${var.streaming_s3_bucket_name}/${trimsuffix(var.streaming_s3_source_prefix, "/")}/"
}

resource "aws_s3_bucket" "streaming_trades_source" {
  bucket = var.streaming_s3_bucket_name
}

# SNS topic receives S3 ObjectCreated events from the streaming bucket.
# Snowpipe auto-ingest subscribes its SQS queue to this topic.
resource "aws_sns_topic" "streaming_s3_events" {
  name = var.streaming_sns_topic_name
}

resource "aws_sns_topic_policy" "streaming_s3_events" {
  arn = aws_sns_topic.streaming_s3_events.arn

  policy = data.aws_iam_policy_document.streaming_s3_to_sns.json
}

data "aws_iam_policy_document" "streaming_s3_to_sns" {
  statement {
    sid    = "AllowS3EventNotifications"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.streaming_s3_events.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.streaming_trades_source.arn]
    }
  }

  statement {
    sid    = "AllowSnowflakeSubscribeAndReceive"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [snowflake_storage_integration.streaming_s3.storage_aws_iam_user_arn]
    }

    actions   = ["sns:Subscribe", "sns:Receive"]
    resources = [aws_sns_topic.streaming_s3_events.arn]
  }
}

resource "aws_s3_bucket_notification" "streaming_trades_source" {
  bucket = aws_s3_bucket.streaming_trades_source.id

  topic {
    topic_arn     = aws_sns_topic.streaming_s3_events.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = trimsuffix(var.streaming_s3_source_prefix, "/") == "" ? "" : "${trimsuffix(var.streaming_s3_source_prefix, "/")}/"
    filter_suffix = ".csv"
  }

  depends_on = [aws_sns_topic_policy.streaming_s3_events]
}

resource "snowflake_storage_integration" "streaming_s3" {
  name                      = var.streaming_storage_integration_name
  type                      = "EXTERNAL_STAGE"
  storage_provider          = "S3"
  storage_aws_role_arn      = local.streaming_snowflake_role_arn
  storage_allowed_locations = [local.streaming_s3_stage_url]
  enabled                   = true
  comment                   = "Read-only access to the streaming trades S3 bucket for Snowpipe."
}

data "aws_iam_policy_document" "streaming_snowflake_s3_read" {
  statement {
    sid    = "ReadStreamingTradeObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    resources = ["${aws_s3_bucket.streaming_trades_source.arn}/${trimsuffix(var.streaming_s3_source_prefix, "/")}/*"]
  }

  statement {
    sid       = "ListStreamingTradePrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.streaming_trades_source.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${trimsuffix(var.streaming_s3_source_prefix, "/")}/*"]
    }
  }
}

data "aws_iam_policy_document" "streaming_snowflake_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [snowflake_storage_integration.streaming_s3.storage_aws_iam_user_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [snowflake_storage_integration.streaming_s3.storage_aws_external_id]
    }
  }
}

resource "aws_iam_role" "streaming_snowflake" {
  name               = var.streaming_snowflake_role_name
  description        = "Assumed by Snowflake to read streaming trade files from S3."
  assume_role_policy = data.aws_iam_policy_document.streaming_snowflake_assume_role.json
}

resource "aws_iam_role_policy" "streaming_snowflake_s3_read" {
  name   = "${var.streaming_snowflake_role_name}-s3-read"
  role   = aws_iam_role.streaming_snowflake.id
  policy = data.aws_iam_policy_document.streaming_snowflake_s3_read.json
}

resource "time_sleep" "wait_for_streaming_iam_propagation" {
  depends_on      = [aws_iam_role.streaming_snowflake, aws_iam_role_policy.streaming_snowflake_s3_read]
  create_duration = "30s"
}

resource "snowflake_stage" "streaming_raw_data" {
  name                = "STREAMING_RAW_DATA_STAGE"
  database            = snowflake_database.raw.name
  schema              = snowflake_schema.raw.name
  url                 = local.streaming_s3_stage_url
  storage_integration = snowflake_storage_integration.streaming_s3.name
  file_format         = "FORMAT_NAME = ${snowflake_database.raw.name}.${snowflake_schema.raw.name}.${snowflake_file_format.csv.name}"

  depends_on = [
    snowflake_file_format.csv,
    time_sleep.wait_for_streaming_iam_propagation,
  ]
}

# Bronze table for streaming data. Snowpipe loads files here as they arrive.
resource "snowflake_table" "trades_stream" {
  database = snowflake_database.raw.name
  schema   = snowflake_schema.raw.name
  name     = "TRADES_STREAM"
  comment  = "Streaming bronze table for trade records loaded by Snowpipe."

  column {
    name = "TRADE_ID"
    type = "VARCHAR"
  }
  column {
    name = "VERSION"
    type = "VARCHAR"
  }
  column {
    name = "COUNTERPARTY"
    type = "VARCHAR"
  }
  column {
    name = "NOTIONAL"
    type = "VARCHAR"
  }
  column {
    name = "CURRENCY"
    type = "VARCHAR"
  }
  column {
    name = "MATURITY_DATE"
    type = "VARCHAR"
  }
  column {
    name = "EXECUTION_DATE"
    type = "VARCHAR"
  }
  column {
    name = "ROW_ID"
    type = "VARCHAR"
  }
  column {
    name = "SOURCE_FILENAME"
    type = "VARCHAR"
  }
  column {
    name    = "LOAD_TIMESTAMP"
    type    = "TIMESTAMP_NTZ"
    default { expression = "CURRENT_TIMESTAMP()" }
  }
}

resource "snowflake_pipe" "trades_stream" {
  database     = snowflake_database.raw.name
  schema       = snowflake_schema.raw.name
  name         = "TRADES_STREAM_PIPE"
  comment      = "Snowpipe auto-ingest for streaming trade files."
  auto_ingest  = true
  aws_sns_topic_arn = aws_sns_topic.streaming_s3_events.arn

  copy_statement = "COPY INTO ${snowflake_database.raw.name}.${snowflake_schema.raw.name}.${snowflake_table.trades_stream.name} (TRADE_ID, VERSION, COUNTERPARTY, NOTIONAL, CURRENCY, MATURITY_DATE, EXECUTION_DATE, ROW_ID, SOURCE_FILENAME, LOAD_TIMESTAMP) FROM (SELECT $1, $2, $3, $4, $5, $6, $7, METADATA$FILE_ROW_NUMBER::VARCHAR, METADATA$FILENAME::VARCHAR, CURRENT_TIMESTAMP() FROM @${snowflake_database.raw.name}.${snowflake_schema.raw.name}.${snowflake_stage.streaming_raw_data.name}) FILE_FORMAT = (FORMAT_NAME = ${snowflake_database.raw.name}.${snowflake_schema.raw.name}.${snowflake_file_format.csv.name})"

  depends_on = [
    snowflake_stage.streaming_raw_data,
    snowflake_table.trades_stream,
    aws_s3_bucket_notification.streaming_trades_source,
  ]
}

resource "snowflake_grant_privileges_to_account_role" "streaming_storage_integration_usage" {
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.service_role.name

  on_account_object {
    object_type = "INTEGRATION"
    object_name = snowflake_storage_integration.streaming_s3.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "streaming_stage_usage" {
  privileges        = ["READ", "WRITE"]
  account_role_name = snowflake_account_role.service_role.name
  on_schema_object {
    object_type = "STAGE"
    object_name = "${var.raw_database_name}.${var.raw_schema_name}.${snowflake_stage.streaming_raw_data.name}"
  }
  depends_on = [snowflake_stage.streaming_raw_data]
}

resource "snowflake_grant_privileges_to_account_role" "streaming_table_all" {
  all_privileges    = true
  account_role_name = snowflake_account_role.service_role.name
  on_schema_object {
    object_type = "TABLE"
    object_name = "${var.raw_database_name}.${var.raw_schema_name}.${snowflake_table.trades_stream.name}"
  }
  depends_on = [snowflake_table.trades_stream]
}
