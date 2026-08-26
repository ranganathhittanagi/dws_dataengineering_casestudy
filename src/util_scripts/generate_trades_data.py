"""Generate a sample trades CSV for a given ETL date.

The output schema matches the raw layer: TRADE_ID, VERSION, COUNTERPARTY,
NOTIONAL, CURRENCY, MATURITY_DATE and EXECUTION_DATE. By default the rows are
valid; use --invalid-ratio to inject rows that should be quarantined by the
quality rules.
"""
import argparse
import csv
import random
import sys
from datetime import datetime, timedelta
from pathlib import Path

CURRENCIES = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF"]
COUNTERPARTIES = [
    "Bank of America",
    "JPMorgan Chase",
    "Goldman Sachs",
    "Morgan Stanley",
    "Citigroup",
    "Deutsche Bank",
    "HSBC",
    "Barclays",
    "BNP Paribas",
    "Societe Generale",
    "UBS",
    "Credit Suisse",
    "Nomura",
    "Mizuho",
    "TD Securities",
]


def random_trade_id():
    return f"T{random.randint(1, 999_999_999):09d}"


def random_valid_row(etl_date: datetime) -> dict:
    exec_date = etl_date - timedelta(days=random.randint(0, 5))
    maturity = exec_date + timedelta(days=random.randint(30, 180))
    return {
        "TRADE_ID": random_trade_id(),
        "VERSION": str(random.randint(1, 10)),
        "COUNTERPARTY": random.choice(COUNTERPARTIES),
        "NOTIONAL": f"{random.uniform(10_000, 10_000_000):.2f}",
        "CURRENCY": random.choice(CURRENCIES),
        "MATURITY_DATE": maturity.strftime("%Y-%m-%d"),
        "EXECUTION_DATE": exec_date.strftime("%Y-%m-%d"),
    }


def corrupt_row(row: dict, etl_date: datetime) -> dict:
    """Mutate one field to exercise the quarantine rules."""
    flaw = random.choice(
        [
            "missing_id",
            "negative_version",
            "bad_notional",
            "bad_currency",
            "maturity_before_execution",
            "bad_date_format",
        ]
    )
    if flaw == "missing_id":
        row["TRADE_ID"] = ""
    elif flaw == "negative_version":
        row["VERSION"] = str(-random.randint(1, 5))
    elif flaw == "bad_notional":
        row["NOTIONAL"] = random.choice(["n/a", "-1000.00", ""])
    elif flaw == "bad_currency":
        row["CURRENCY"] = random.choice(["XYZ", "ABC", ""])
    elif flaw == "maturity_before_execution":
        exec_date = etl_date - timedelta(days=random.randint(30, 90))
        mat = exec_date - timedelta(days=random.randint(1, 30))
        row["EXECUTION_DATE"] = exec_date.strftime("%Y-%m-%d")
        row["MATURITY_DATE"] = mat.strftime("%Y-%m-%d")
    elif flaw == "bad_date_format":
        row["MATURITY_DATE"] = random.choice(
            ["12/31/2026", "not-a-date", "2026-13-45", ""]
        )
    return row


def generate_rows(etl_date: datetime, n_rows: int, invalid_ratio: float, seed: int):
    random.seed(seed)
    n_invalid = int(n_rows * invalid_ratio)
    n_valid = n_rows - n_invalid

    rows = [random_valid_row(etl_date) for _ in range(n_valid)]
    rows += [corrupt_row(random_valid_row(etl_date), etl_date) for _ in range(n_invalid)]
    random.shuffle(rows)

    return rows


def main():
    parser = argparse.ArgumentParser(description="Generate sample trade CSV files.")
    parser.add_argument(
        "--date",
        required=True,
        help="ETL date in YYYY-MM-DD format; also used for filename.",
    )
    parser.add_argument(
        "--rows",
        type=int,
        default=100,
        help="Number of rows to generate (default 100).",
    )
    parser.add_argument(
        "--invalid-ratio",
        type=float,
        default=0.0,
        help="Share of rows that should intentionally fail quality rules (0.0-1.0).",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "data",
        help="Directory to write the CSV to.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducible sample data.",
    )
    args = parser.parse_args()

    if not (0.0 <= args.invalid_ratio <= 1.0):
        print("--invalid-ratio must be between 0.0 and 1.0", file=sys.stderr)
        sys.exit(1)

    etl_date = datetime.strptime(args.date, "%Y-%m-%d")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    rows = generate_rows(etl_date, args.rows, args.invalid_ratio, args.seed)

    columns = [
        "TRADE_ID",
        "VERSION",
        "COUNTERPARTY",
        "NOTIONAL",
        "CURRENCY",
        "MATURITY_DATE",
        "EXECUTION_DATE",
    ]
    output_file = args.output_dir / f"trades_{args.date}.csv"

    with open(output_file, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Generated {len(rows)} rows ({int(args.invalid_ratio * args.rows)} invalid) at {output_file}")


if __name__ == "__main__":
    main()
