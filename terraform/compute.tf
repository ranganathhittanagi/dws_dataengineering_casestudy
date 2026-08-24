# The two EC2 instances.
#
# airflow-control is a stateful singleton (Postgres/Redis/webserver/scheduler). It gets
# self-healing via a CloudWatch aws:recover alarm (same instance + EBS restored on
# hardware failure) and daily EBS snapshots via DLM.
#
# dev-ec2-instance is the second box: it runs the Celery worker that actually executes
# ingestion/dbt tasks dispatched by Airflow, AND doubles as the interactive box you SSM
# into to run ad hoc commands (git pull, dbt, aws cli) the same way you would locally. It
# is a stable singleton (not an ASG) precisely so its instance ID never changes under you
# - it gets the same aws:recover self-healing as the control instance instead.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  control_user_data = templatefile("${path.module}/../deploy/userdata.sh.tpl", {
    role               = "control"
    repo_url           = var.repo_url
    repo_branch        = var.repo_branch
    aws_region         = var.aws_region
    airflow_param_path = var.airflow_param_path
  })

  dev_user_data = templatefile("${path.module}/../deploy/userdata.sh.tpl", {
    role               = "dev"
    repo_url           = var.repo_url
    repo_branch        = var.repo_branch
    aws_region         = var.aws_region
    airflow_param_path = var.airflow_param_path
  })
}

# --- Control plane (stateful singleton) ---

resource "aws_instance" "airflow_control" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.control_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.airflow_control.id]
  iam_instance_profile   = aws_iam_instance_profile.airflow_control.name
  user_data              = local.control_user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 16
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-control"
    Role = "airflow-control"
  }

  lifecycle {
    # user_data changes shouldn't silently replace the stateful instance.
    ignore_changes = [ami, user_data]
  }
}

# Dedicated data volume for Postgres/Redis so state survives instance stop/start and can
# be snapshotted independently of the root disk.
resource "aws_ebs_volume" "control_data" {
  availability_zone = aws_subnet.public[0].availability_zone
  size              = 10
  type              = "gp3"
  encrypted         = true

  tags = {
    Name   = "${var.project_name}-control-data"
    Backup = "${var.project_name}-control"
  }
}

resource "aws_volume_attachment" "control_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.control_data.id
  instance_id = aws_instance.airflow_control.id
}

# Self-healing for the stateful node: on underlying hardware failure AWS migrates and
# restarts the SAME instance (same instance ID, same EBS volumes) - no data loss, no ASG.
resource "aws_cloudwatch_metric_alarm" "control_recover" {
  alarm_name          = "${var.project_name}-control-auto-recover"
  alarm_description   = "Auto-recover the Airflow control instance on system status check failure."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 60
  evaluation_periods  = 2

  dimensions = {
    InstanceId = aws_instance.airflow_control.id
  }

  alarm_actions = [
    "arn:aws:automate:${var.aws_region}:ec2:recover",
    aws_sns_topic.pipeline_alerts.arn,
  ]
}

# Airflow task logs go to CloudWatch (remote logging) so the webserver on the control
# instance can display logs for tasks executed on dev-ec2-instance.
resource "aws_cloudwatch_log_group" "airflow_tasks" {
  name              = "/${var.project_name}/tasks"
  retention_in_days = 30
}

resource "aws_ssm_parameter" "task_log_group_arn" {
  name  = "${var.airflow_param_path}/task_log_group_arn"
  type  = "String"
  value = aws_cloudwatch_log_group.airflow_tasks.arn
}

# dev-ec2-instance discovers the control plane's address at boot from SSM.
resource "aws_ssm_parameter" "control_private_ip" {
  name  = "${var.airflow_param_path}/control_private_ip"
  type  = "String"
  value = aws_instance.airflow_control.private_ip
}

# Daily snapshot of the data volume, 7-day retention.
resource "aws_iam_role" "dlm" {
  name = "${var.project_name}-dlm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "dlm.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "control_data_backup" {
  description        = "Daily snapshots of the Airflow control data volume"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    target_tags = {
      Backup = "${var.project_name}-control"
    }

    schedule {
      name = "daily-7day-retention"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["21:00"]
      }

      retain_rule {
        count = 7
      }

      copy_tags = true
    }
  }
}

# --- dev-ec2-instance (Celery worker + interactive dev box, stable singleton) ---

resource "aws_instance" "dev_ec2" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.dev_instance_type
  subnet_id              = aws_subnet.public[1].id
  vpc_security_group_ids = [aws_security_group.dev_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.dev_ec2.name
  user_data              = local.dev_user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 16
    encrypted   = true
  }

  tags = {
    Name = "dev-ec2-instance"
    Role = "dev-ec2-instance"
  }

  lifecycle {
    # user_data changes shouldn't silently replace this instance either - deploys
    # happen via CI (git pull + docker build), not by re-running Terraform.
    ignore_changes = [ami, user_data]
  }

  # Needs the control plane's address (SSM param) to exist before booting.
  depends_on = [aws_ssm_parameter.control_private_ip]
}

# Same self-healing approach as the control instance: same instance ID/EBS restored on
# hardware failure, so it stays a stable, always-discoverable box for ad hoc SSM access.
resource "aws_cloudwatch_metric_alarm" "dev_ec2_recover" {
  alarm_name          = "${var.project_name}-dev-auto-recover"
  alarm_description   = "Auto-recover dev-ec2-instance on system status check failure."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 60
  evaluation_periods  = 2

  dimensions = {
    InstanceId = aws_instance.dev_ec2.id
  }

  alarm_actions = [
    "arn:aws:automate:${var.aws_region}:ec2:recover",
    aws_sns_topic.pipeline_alerts.arn,
  ]
}
