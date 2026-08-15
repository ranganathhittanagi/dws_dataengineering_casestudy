FROM apache/airflow:2.9.2

USER root

RUN apt-get update && apt-get install -y --no-install-recommends gcc git && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/home/airflow /opt/home/src /opt/home/dbt /opt/home/data /opt/home/secrets /opt/home/dbt_venv

# Remove the default Airflow home and other unused base-image directories so /opt only contains /opt/home.
RUN rm -rf /opt/airflow /opt/dbt /opt/microsoft

COPY requirements.txt /tmp/requirements.txt

# Install dbt-snowflake in an isolated virtual environment under /opt/home to keep the filesystem tidy.
# The version is sourced from the single root requirements.txt (one source of truth).
RUN python -m venv /opt/home/dbt_venv && \
    grep '^dbt-' /tmp/requirements.txt > /tmp/dbt-requirements.txt && \
    /opt/home/dbt_venv/bin/pip install --no-cache-dir -r /tmp/dbt-requirements.txt

# The base Airflow image only allows pip as the airflow user.
USER airflow
RUN grep -v -E '^(apache-airflow|dbt-|streamlit)' /tmp/requirements.txt > /tmp/airflow-requirements.txt && \
    pip install --no-cache-dir -r /tmp/airflow-requirements.txt

# Make the DBT binary available on PATH.
ENV PATH="${PATH}:/opt/home/dbt_venv/bin"
