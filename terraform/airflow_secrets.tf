# Airflow shared secrets, generated once by Terraform and stored in SSM Parameter Store.
#
# With CeleryExecutor spanning two hosts, the Fernet key (connection encryption) and the
# webserver secret key (session/log-serving auth) must be identical on every Airflow
# process. Instances fetch these at boot via their IAM role (deploy/fetch_runtime_env.sh);
# nothing sensitive is baked into images, user-data, or the repo.

# Fernet requires 32 random bytes encoded as URL-safe base64.
resource "random_bytes" "fernet_key" {
  length = 32
}

resource "random_password" "webserver_secret_key" {
  length  = 40
  special = false
}

resource "random_password" "airflow_db_password" {
  length  = 32
  special = false
}

resource "random_password" "redis_password" {
  length  = 32
  special = false
}

resource "random_password" "webserver_admin_password" {
  length  = 20
  special = false
}

locals {
  # Convert standard base64 to the URL-safe alphabet Fernet expects.
  fernet_key_urlsafe = replace(replace(random_bytes.fernet_key.base64, "+", "-"), "/", "_")
}

resource "aws_ssm_parameter" "fernet_key" {
  name  = "${var.airflow_param_path}/fernet_key"
  type  = "SecureString"
  value = local.fernet_key_urlsafe
}

resource "aws_ssm_parameter" "webserver_secret_key" {
  name  = "${var.airflow_param_path}/webserver_secret_key"
  type  = "SecureString"
  value = random_password.webserver_secret_key.result
}

resource "aws_ssm_parameter" "airflow_db_password" {
  name  = "${var.airflow_param_path}/postgres_password"
  type  = "SecureString"
  value = random_password.airflow_db_password.result
}

resource "aws_ssm_parameter" "redis_password" {
  name  = "${var.airflow_param_path}/redis_password"
  type  = "SecureString"
  value = random_password.redis_password.result
}

# Initial Airflow UI admin password (read it with:
# aws ssm get-parameter --name /dws/airflow/webserver_admin_password --with-decryption)
resource "aws_ssm_parameter" "webserver_admin_password" {
  name  = "${var.airflow_param_path}/webserver_admin_password"
  type  = "SecureString"
  value = random_password.webserver_admin_password.result
}
