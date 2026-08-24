# IAM instance roles for the two EC2 instances. These replace all static credentials
# (no ~/.aws mounts, no access keys): boto3/awscli on the instances resolve credentials
# from the instance profile automatically. Once live, the static-key dws-pipeline-service
# IAM user can be retired.

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

locals {
  dws_param_arn_prefix = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/dws/*"
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Shared baseline: SSM parameters under /dws/*, KMS decrypt for SecureStrings,
# CloudWatch Logs for the awslogs Docker driver, SNS publish for alerting.
data "aws_iam_policy_document" "instance_baseline" {
  statement {
    sid       = "ReadDwsParameters"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [local.dws_param_arn_prefix]
  }

  statement {
    sid       = "DecryptSsmSecureStrings"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]
  }

  statement {
    sid    = "ShipAndReadLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:GetLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/${var.project_name}/*",
    ]
  }

  statement {
    sid       = "PublishPipelineAlerts"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.pipeline_alerts.arn]
  }
}

# dev-ec2-instance additionally reads trade files from S3 (same least-privilege scope
# previously attached to the dws-pipeline-service IAM user).
data "aws_iam_policy_document" "dev_s3_read" {
  statement {
    sid       = "ReadTradeObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
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

# --- Control plane role ---

resource "aws_iam_role" "airflow_control" {
  name               = "${var.project_name}-control-role"
  description        = "Instance role for the Airflow control-plane EC2 (webserver/scheduler)."
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "control_ssm_core" {
  role       = aws_iam_role.airflow_control.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "control_baseline" {
  name   = "${var.project_name}-control-baseline"
  role   = aws_iam_role.airflow_control.id
  policy = data.aws_iam_policy_document.instance_baseline.json
}

resource "aws_iam_instance_profile" "airflow_control" {
  name = "${var.project_name}-control-profile"
  role = aws_iam_role.airflow_control.name
}

# --- dev-ec2-instance role (Celery worker + ad hoc dev box) ---

resource "aws_iam_role" "dev_ec2" {
  name               = "${var.project_name}-dev-role"
  description        = "Instance role for dev-ec2-instance: runs the Celery worker (ingestion/dbt) and doubles as the ad hoc dev box."
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dev_ssm_core" {
  role       = aws_iam_role.dev_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "dev_baseline" {
  name   = "${var.project_name}-dev-baseline"
  role   = aws_iam_role.dev_ec2.id
  policy = data.aws_iam_policy_document.instance_baseline.json
}

resource "aws_iam_role_policy" "dev_s3_read" {
  name   = "${var.project_name}-dev-s3-read"
  role   = aws_iam_role.dev_ec2.id
  policy = data.aws_iam_policy_document.dev_s3_read.json
}

resource "aws_iam_instance_profile" "dev_ec2" {
  name = "${var.project_name}-dev-profile"
  role = aws_iam_role.dev_ec2.name
}
