"""Generate simulated daily trade files as CSV (all values as strings)."""
import argparse
import csv
import os
import random
from datetime import date, datetime, timedelta
from pathlib import Path
from uuid import uuid4

CURRENCIES = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF"]
COUNTERPARTIES = [f"CP_{i:03d}" for i in range(1, 21)]

TRADE_COLUMNS = [
    "TRADE_ID",
    "VERSION",
    "COUNTERPARTY",
    "NOTIONAL",
    "CURRENCY",
    "MATURITY_DATE",
    "EXECUTION_DATE",
]


def valid_maturity_date(execution_date: date) -> date:
    return execution_date + timedelta(days=random.randint(30, 365 * 5))


def invalid_maturity_date(execution_date: date) -> date:
    return execution_date - timedelta(days=random.randint(1, 30))


def build_trade(execution_date: date, trade_id: str, version: int, maturity_date: date) -> dict:
    """Return a single trade row with all values as strings."""
    return {
        "TRADE_ID": trade_id,
        "VERSION": str(version),
        "COUNTERPARTY": random.choice(COUNTERPARTIES),
        "NOTIONAL": f"{round(random.uniform(10_000, 10_000_000), 2)}",
        "CURRENCY": random.choice(CURRENCIES),
        "MATURITY_DATE": maturity_date.isoformat(),
        "EXECUTION_DATE": execution_date.isoformat(),
    }


def generate_trades_data(
    output_dir: str,
    execution_date: date,
    count: int = 1_000,
    multi_version_count: int = 50,
    invalid_maturity_count: int = 50,
) -> Path:
    """Write simulated trades for `execution_date` to a CSV file.

    Generates `count` normal trades, `multi_version_count` TRADE_IDs repeated
    with increasing VERSION numbers, and `invalid_maturity_count` trades with
    MATURITY_DATE before EXECUTION_DATE.
    """
    rows = [
        build_trade(execution_date, str(uuid4())[:8].upper(), random.randint(1, 3), valid_maturity_date(execution_date))
        for _ in range(count)
    ]

    for _ in range(multi_version_count):
        trade_id = str(uuid4())[:8].upper()
        for version in range(1, random.randint(2, 3) + 1):
            rows.append(build_trade(execution_date, trade_id, version, valid_maturity_date(execution_date)))

    rows += [
        build_trade(execution_date, str(uuid4())[:8].upper(), random.randint(1, 3), invalid_maturity_date(execution_date))
        for _ in range(invalid_maturity_count)
    ]

    random.shuffle(rows)

    out_dir = Path(output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    file_path = out_dir / f"trades_{execution_date.isoformat()}.csv"
    with file_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=TRADE_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    return file_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate simulated daily trade data.")
    parser.add_argument("--date", default=date.today().isoformat(), help="Execution date (YYYY-MM-DD). Defaults to today.")
    args = parser.parse_args()

    output_dir = os.getenv("TRADE_DATA_DIR", "data/raw")
    trade_count = int(os.getenv("TRADE_COUNT", "1000"))
    execution_date = datetime.strptime(args.date, "%Y-%m-%d").date()

    generated = generate_trades_data(output_dir, execution_date, count=trade_count)
    print(f"Generated {generated}")
