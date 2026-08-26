"""Shared helper for running dbt commands from Airflow.

This keeps the dbt invocation logic in one place so the layer-specific DAGs
only declare the subcommand and selector for each stage.
"""
import os
import subprocess

from src.config import dbt_environment

DBT_PROJECT_DIR = "/opt/home/dbt"
DBT_BIN = ["/opt/home/dbt_venv/bin/python", "-I", "/opt/home/dbt_venv/bin/dbt"]


def run_dbt(subcommand: str, selector: str, full_refresh: bool = False, **context):
    """Run a dbt subcommand with the given selector and SSM-sourced env."""
    etl_date = context.get("ds") or context.get("etl_date", "")
    command = DBT_BIN + [subcommand, "--select"] + selector.split()
    if full_refresh:
        command.append("--full-refresh")
    command += ["--vars", f'{{"etl_date": "{etl_date}"}}']
    env = {**os.environ, **dbt_environment()}
    result = subprocess.run(
        command,
        cwd=DBT_PROJECT_DIR,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)
    if result.returncode != 0:
        raise RuntimeError(
            f"dbt {subcommand} --select {selector} failed with exit code {result.returncode}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
