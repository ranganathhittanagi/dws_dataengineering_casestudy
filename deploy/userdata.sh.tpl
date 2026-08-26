#!/bin/bash
# EC2 bootstrap for the ${role} node (rendered by Terraform templatefile()).
# role = "control" (complete Airflow stack, Postgres, and Redis) or
# role = "dev" (SSH/SSM-accessible ad hoc development box).
# Idempotent: safe to re-run. Installs Docker + Compose, prepares storage (control only),
# clones the repo, fetches runtime secrets from SSM, and starts the Compose stack.
set -euxo pipefail

exec > >(tee -a /var/log/bootstrap.log) 2>&1

REPO_URL="${repo_url}"
REPO_BRANCH="${repo_branch}"
AWS_REGION="${aws_region}"
AIRFLOW_PARAM_PATH="${airflow_param_path}"
ROLE="${role}"
APP_DIR=/opt/app

# Allow root (bootstrap, SSM deploy) to operate on a repo whose owner is the container user.
git config --global --add safe.directory "$APP_DIR"

# --- Base packages ---
dnf install -y docker git
systemctl enable --now docker

# Docker Compose v2 plugin (not packaged in AL2023 repos).
if ! docker compose version >/dev/null 2>&1; then
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

# --- Swap: keeps small burstable instances stable under Airflow's memory profile ---
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# --- Control only: mount the dedicated EBS data volume for Postgres/Redis ---
if [ "$ROLE" = "control" ]; then
  # Wait for the attached data volume (shows up as the non-root NVMe device).
  DATA_DEV=""
  for _ in $(seq 1 30); do
    DATA_DEV=$(lsblk -dnpo NAME,TYPE | awk '$2=="disk"{print $1}' | while read -r dev; do
      if ! lsblk -no MOUNTPOINT "$dev" | grep -q '^/$'; then echo "$dev"; fi
    done | head -n1)
    [ -n "$DATA_DEV" ] && break
    sleep 5
  done
  if [ -z "$DATA_DEV" ]; then echo "data volume not found"; exit 1; fi

  if ! blkid "$DATA_DEV" >/dev/null 2>&1; then
    mkfs -t xfs "$DATA_DEV"
  fi
  mkdir -p /data
  if ! grep -q ' /data ' /etc/fstab; then
    echo "UUID=$(blkid -s UUID -o value "$DATA_DEV") /data xfs defaults,nofail 0 2" >> /etc/fstab
  fi
  mountpoint -q /data || mount /data
  mkdir -p /data/postgres /data/redis
fi

# --- Application checkout ---
if [ ! -d "$APP_DIR/.git" ]; then
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$APP_DIR"
else
  git -C "$APP_DIR" fetch origin "$REPO_BRANCH"
  git -C "$APP_DIR" checkout "$REPO_BRANCH"
  git -C "$APP_DIR" pull --ff-only origin "$REPO_BRANCH"
fi

# Ensure the checked-out repo is writable by the container airflow user.
# The apache/airflow image uses uid 50000 for airflow; group 0 (root) is kept
# so host root processes (e.g. git pull, SSM, deploy scripts) remain able to
# manage files while the container user can write dbt packages/lock files.
chown -R 50000:0 "$APP_DIR"

# --- Runtime secrets/config from SSM, then start the stack ---
export AWS_REGION AIRFLOW_PARAM_PATH
bash "$APP_DIR/deploy/fetch_runtime_env.sh" "$ROLE"

cd "$APP_DIR"
docker compose -f "deploy/docker-compose.$ROLE.yml" up -d --build
