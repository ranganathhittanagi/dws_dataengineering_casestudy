# Networking for the two-instance Airflow deployment.
#
# Cost-conscious layout: public subnets with locked-down security groups instead of
# private subnets + NAT Gateway (~$32+/month, not free-tier eligible). No instance has
# any inbound port open to the internet; admin access is SSM Session Manager only
# (outbound HTTPS, no inbound required) and the webserver is reachable only via the ALB.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "pipeline" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "pipeline" {
  vpc_id = aws_vpc.pipeline.id

  tags = { Name = "${var.project_name}-igw" }
}

# ALB requires subnets in at least two AZs.
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.pipeline.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.pipeline.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pipeline.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Security groups ---

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Airflow ALB: inbound HTTP from the admin IP allowlist only"
  vpc_id      = aws_vpc.pipeline.id

  ingress {
    description = "HTTP from admin allowlist"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.admin_ip_allowlist
  }

  egress {
    description = "To the Airflow webserver"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_security_group" "airflow_control" {
  name        = "${var.project_name}-control-sg"
  description = "Airflow control plane: webserver from ALB, Postgres/Redis from dev-ec2-instance"
  vpc_id      = aws_vpc.pipeline.id

  ingress {
    description     = "Webserver from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Outbound (AWS APIs, Snowflake, package installs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-control-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "control_postgres_from_dev" {
  security_group_id            = aws_security_group.airflow_control.id
  referenced_security_group_id = aws_security_group.dev_ec2.id
  description                  = "Postgres from dev-ec2-instance Airflow CLI"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "control_redis_from_dev" {
  security_group_id            = aws_security_group.airflow_control.id
  referenced_security_group_id = aws_security_group.dev_ec2.id
  description                  = "Redis from dev-ec2-instance Airflow CLI"
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "dev_ec2" {
  name        = "${var.project_name}-dev-sg"
  description = "dev-ec2-instance: SSH from the configured admin CIDR and unrestricted outbound"
  vpc_id      = aws_vpc.pipeline.id

  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.dev_ssh_cidr]
  }

  egress {
    description = "Outbound (control plane, AWS APIs, Snowflake, package installs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-dev-sg" }
}
