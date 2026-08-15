# Trade Data ETL Pipeline

Cloud-native ETL pipeline for daily trade data ingestion, validation, and reporting using Snowflake, DBT, Airflow, and Terraform.

## Quick Start

1. Create a `terraform/terraform.tfvars` file with your Snowflake **admin** credentials.
2. Generate an RSA key pair for the service user.
3. Run Terraform to create the Snowflake warehouse, three databases, schemas, raw `TRADES` table, internal stage, CSV file format, service user, and service role.
4. Copy `.env.example` to `.env` and keep the service user key-pair path.
5. Build and start Airflow in Docker.
6. Verify DBT connects to Snowflake.
7. Open the Airflow UI.

## Setup & Run

### 1. Generate an RSA key pair

```bash
mkdir -p secrets
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out secrets/rsa_key.p8 -nocrypt
openssl rsa -in secrets/rsa_key.p8 -pubout -out secrets/rsa_key.pub
```

Terraform reads `secrets/rsa_key.pub` automatically.

### 2. Create the Terraform variables file

Create `terraform/terraform.tfvars` (it is gitignored):

```hcl
snowflake_organization_name = "YTQEMJI"
snowflake_account_name      = "TW17096"
snowflake_user              = "your_admin_username"
snowflake_password          = "your_admin_password"
snowflake_role              = "ACCOUNTADMIN"
```

By default, Terraform creates `RAW_DB`, `TRANSFORM_DB`, `DATAWAREHOUSE_DB`, and their schemas, plus a `TRADES` landing table, `CSV_FORMAT`, and `RAW_DATA_STAGE` in `RAW_DB.RAW_SCHEMA`.

### 3. Provision Snowflake with Terraform

**Option A: Terraform installed locally**

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

**Option B: Terraform via Docker**

```bash
docker run --rm -it -v $(pwd)/terraform:/workspace -w /workspace hashicorp/terraform:latest init
docker run --rm -it -v $(pwd)/terraform:/workspace -w /workspace hashicorp/terraform:latest plan
docker run --rm -it -v $(pwd)/terraform:/workspace -w /workspace hashicorp/terraform:latest apply -auto-approve
```

### 4. Configure runtime credentials

```bash
cp .env.example .env
# Edit .env with your Snowflake account details; SNOWFLAKE_PRIVATE_KEY_PATH is already set
```

The runtime `.env` only stores connection secrets:
- `SNOWFLAKE_ACCOUNT`
- `SNOWFLAKE_USER=DWS_SERVICE_USER`
- `SNOWFLAKE_ROLE=DWS_SERVICE_ROLE`
- `SNOWFLAKE_WAREHOUSE=COMPUTE_WH`
- `SNOWFLAKE_PRIVATE_KEY_PATH=/opt/airflow/secrets/rsa_key.p8`

Database and schema names live in `dbt/dbt_project.yml` as version-controlled vars with env-var overrides, so `.env` does not need them.

No password is stored.

### 5. Build and start Airflow

```bash
docker compose up --build -d
```

### 6. Generate sample trade files and PUT them to the Snowflake stage

The `dws_etl_service_container` container contains Airflow, the ingestion scripts, and the DBT virtualenv.

```bash
# Generate CSV trade data
docker compose exec dws_etl_service_container python -m src.ingestion.generate_trades_data

# PUT the CSV to the Snowflake internal stage
docker compose exec dws_etl_service_container python -m src.ingestion.load_to_snowflake
```

Before loading, the generated CSV files are in `data/raw/` on the host and `/opt/home/data/raw/` inside the container:
`trades_YYYY-MM-DD.csv` with columns `TRADE_ID, VERSION, COUNTERPARTY, NOTIONAL, CURRENCY, MATURITY_DATE, EXECUTION_DATE`.

After loading, the files are stored in the Snowflake internal stage `@RAW_DB.RAW_SCHEMA.RAW_DATA_STAGE`; the local CSV copies remain unless you delete them.

### 7. Load the staged files into `RAW_DB.RAW_SCHEMA.TRADES` with DBT

```bash
docker compose exec dws_etl_service_container dbt run --project-dir /opt/home/dbt --select trades
```

### 8. Verify DBT inside the service container

```bash
docker compose exec dws_etl_service_container dbt debug --project-dir /opt/home/dbt
```

### 9. Open Airflow UI

Visit `http://localhost:8080` and log in with `admin` / `admin`.

## Verification Checks

- `terraform show` lists the created resources.
- `docker compose ps` shows all Airflow services healthy.
- `docker compose logs airflow-webserver` has no startup errors.
- `dbt debug` reports `Connection test: OK` for Snowflake.
- Snowflake console shows the `TRADES` table under `RAW_DB.RAW_SCHEMA`.
- `dbt run --select trades` copies staged CSV files into `RAW_DB.RAW_SCHEMA.TRADES` using `COPY INTO`.
- No password is stored in `.env` or committed to git.
