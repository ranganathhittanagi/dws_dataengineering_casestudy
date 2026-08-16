# Trade Data ETL Pipeline

Cloud-native ETL pipeline for daily trade data ingestion, validation, and reporting using Snowflake, dbt, Airflow, and Terraform.

---

## Architecture

![Architecture Diagram](docs/architecture_diagram.png)

---

## Tech Stack Choices

| Technology | Purpose |
|---|---|
| **Snowflake** | Cloud data warehouse with native stages, `COPY INTO`, and Streamlit apps — zero infrastructure management |
| **Terraform** | Infrastructure as code for provisioning databases, schemas, roles, users, stages, and grants reproducibly |
| **dbt** | SQL-based transformations with incremental materializations, built-in testing, and custom `copy_into_table` materialization for raw data loading |
| **Apache Airflow** | Orchestrates the pipeline (file sensing → upload → dbt run → dbt test) with retries, timeouts, and email alerts |
| **Docker** | Containerizes Airflow and all dependencies for consistent local development and deployment |
| **GitHub Actions** | CI pipelines validate dbt models and Terraform code on every push/PR to `master` |
| **Streamlit in Snowflake** | Serverless dashboard running natively inside Snowflake using Snowpark — no external hosting needed |
| **RSA key-pair auth** | Secure, non-interactive Snowflake access across all components (no passwords stored) |

---

## Validation Logic

### Valid Trades

- Trade must have a **non-null** `MATURITY_DATE`
- `MATURITY_DATE` must be **>=** `EXECUTION_DATE`
- Incoming `VERSION` must be **>=** the version already stored for that `TRADE_ID`
- If multiple records arrive for the same `TRADE_ID` in one batch, only the **highest version** is kept
- Status is set to **ACTIVE** if `MATURITY_DATE >= CURRENT_DATE`, otherwise **EXPIRED**
- On every run, all existing rows are re-evaluated — trades transition from ACTIVE to EXPIRED once their maturity date passes

### Rejected Trades

- `MATURITY_DATE` is **NULL** or unparseable → `INVALID_MATURITY_DATE`
- `MATURITY_DATE` is **earlier than** `EXECUTION_DATE` → `MATURITY_BEFORE_EXECUTION`
- Incoming `VERSION` is **lower than** the version already stored → `STALE_VERSION`
- All rejected records are stored with `(TRADE_ID, VERSION)` as composite key

---

## Setup & Execution Guide

### Prerequisites

- Docker Desktop installed locally
- Terraform (>= 1.5.0) installed locally
- A Snowflake account with `ACCOUNTADMIN` access
- Git installed
- A Gmail account (for Airflow email alerting)

### Step 1: Clone the repository

```bash
git clone https://github.com/ranganathhittanagi/dws_dataengineering_casestudy.git
cd dws_dataengineering_casestudy
```

### Step 2: Generate RSA key pair

Generate a key pair for Snowflake key-pair authentication and store it in the `secrets/` folder.

> **Note:** In production, store secrets in a secure vault (HashiCorp Vault, AWS Secrets Manager, etc.). Never commit the `secrets/` folder to version control.

```bash
mkdir -p secrets

# Generate private key (PKCS#8 format, no passphrase)
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out secrets/rsa_key.p8 -nocrypt

# Extract public key
openssl rsa -in secrets/rsa_key.p8 -pubout -out secrets/rsa_key.pub
```

Assign the public key to the Snowflake user (login as `ACCOUNTADMIN`):

```sql
ALTER USER DWS_SERVICE_USER SET RSA_PUBLIC_KEY='<paste key without header/footer>';
```

To get the key content without headers:

```bash
grep -v "BEGIN\|END" secrets/rsa_key.pub | tr -d '\n'
```

### Step 3: Configure environment variables

Edit the `.env` file in the project root:

```
SNOWFLAKE_ACCOUNT=<your_snowflake_account_identifier>
SNOWFLAKE_USER=DWS_SERVICE_USER
SNOWFLAKE_ROLE=DWS_SERVICE_ROLE
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_PRIVATE_KEY_PATH=/opt/home/secrets/rsa_key.p8
TRADE_DATA_DIR=data/raw
```

**Gmail SMTP setup (for Airflow failure email alerts):**

1. Go to https://myaccount.google.com/security
2. Enable **2-Step Verification**
3. Go to https://myaccount.google.com/apppasswords
4. Select app: **Mail**, device: **Other** → enter "Airflow" → click **Generate**
5. Copy the 16-character app password

Add SMTP settings to `.env`:

```
AIRFLOW_SMTP_HOST=smtp.gmail.com
AIRFLOW_SMTP_PORT=587
AIRFLOW_SMTP_USER=<your_gmail_address>
AIRFLOW_SMTP_PASSWORD=<16_char_app_password>
AIRFLOW_SMTP_MAIL_FROM=<your_gmail_address>
ALERT_EMAIL_TO=<recipient_email_for_alerts>
```

### Step 4: Provision Snowflake infrastructure with Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
cd ..
```

This creates databases (`RAW_DB`, `TRANSFORM_DB`, `DATAWAREHOUSE_DB`, `COMPLIANCE_DB`), schemas, roles, users, warehouse, internal stage, file format, and all grants.

### Step 5: Start Docker containers

```bash
docker compose up --build -d
```

Wait ~1-2 minutes for services to initialize, then verify:

```bash
# Check container is running
docker ps

# Verify dbt can connect to Snowflake
docker exec -it dws_etl_service_container bash -c "cd /opt/home/dbt && /opt/home/dbt_venv/bin/dbt debug"
```

Open http://localhost:8080 — login with **admin / admin**.

### Step 6: Generate and load sample trade data

```bash
# Connect to the container
docker exec -it dws_etl_service_container bash

# Generate sample trades file for a specific date
python3 src/ingestion/generate_trades_data.py --date 2026-08-15

# Upload the generated file to Snowflake internal stage
python3 src/ingestion/load_to_snowflake.py

exit
```

### Step 7: Trigger the Airflow DAG

1. Open http://localhost:8080
2. Find `trade_pipeline_dag`
3. Unpause the DAG (toggle switch)
4. Click **Play** → **Trigger DAG**
5. The DAG executes: **sense file → upload to Snowflake → dbt run → dbt test**

### Step 8: Verify data in Snowflake

Login to Snowflake UI (Snowsight) and run:

```sql
SELECT * FROM DATAWAREHOUSE_DB.DATAWAREHOUSE_SCHEMA.VALID_TRADES;
SELECT * FROM COMPLIANCE_DB.COMPLIANCE_SCHEMA.REJECTED_TRADES;
```

### Step 9: View Streamlit dashboard

1. In Snowsight → **Streamlit** → **+ Streamlit App**
2. Set database: `RAW_DB`, schema: `RAW_SCHEMA`, warehouse: `COMPUTE_WH`
3. Paste the contents of `streamlit_app_snowflake.py` into the editor
4. Click **Run** — the dashboard displays Active, Expired, and Rejected trade metrics with a bar chart

### Step 10: CI/CD with GitHub Actions

Any push or PR to `master` automatically triggers:

- **dbt CI** (`dbt-ci.yml`) — runs `dbt deps`, `dbt parse`, `dbt compile`, `dbt test`
- **Terraform CI** (`terraform-ci.yml`) — runs `terraform fmt -check`, `terraform init`, `terraform validate`, `terraform plan`

No `terraform apply` runs in CI — infrastructure changes are applied manually (Step 4).

**Required GitHub Secrets** (Settings → Secrets → Actions):

| Secret | Value |
|---|---|
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier |
| `SNOWFLAKE_USER` | `DWS_SERVICE_USER` |
| `SNOWFLAKE_ROLE` | `DWS_SERVICE_ROLE` |
| `SNOWFLAKE_WAREHOUSE` | `COMPUTE_WH` |
| `SNOWFLAKE_PRIVATE_KEY_B64` | Base64-encoded private key: `base64 -w 0 secrets/rsa_key.p8` |

---

## Verification Checks

- `terraform show` — lists created Snowflake resources
- `docker compose ps` — all services healthy
- `dbt debug` — reports `Connection test: OK`
- Snowflake console shows `TRADES` table under `RAW_DB.RAW_SCHEMA`
- Airflow DAG completes all tasks (green)
- No passwords stored in `.env` or committed to git
