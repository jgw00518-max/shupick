"""Add only the verified-number table to the local test database. Never seed data."""

import argparse
from pathlib import Path

from app.config import settings
from app.database import mysql_connection


EXPECTED = {
    "customer_id": "bigint unsigned", "verified_phone": "varchar(20)",
    "firebase_phone_uid": "varchar(128)", "phone_verified_at": "datetime(6)",
    "phone_consent_at": "datetime(6)", "birth_date_consent_at": "datetime(6)",
}


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    if settings.mysql_host not in {"localhost", "127.0.0.1", "::1"} or settings.mysql_database != "shupick_v2":
        print("Refusing: only the local shupick_v2 test database is supported.")
        return 1
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT COLUMN_NAME,COLUMN_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='customer_enrollments'")
                existing = {row["COLUMN_NAME"]: row["COLUMN_TYPE"].lower() for row in cursor.fetchall()}
                if existing:
                    if existing != EXPECTED:
                        print("Unexpected enrollment schema. No changes were made.")
                        return 1
                    print("Enrollment table is ready. No changes were made.")
                    return 0
                cursor.execute("SELECT COLUMN_NAME,COLUMN_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='customers' AND COLUMN_NAME IN ('customer_id','birth_date')")
                customer = {row["COLUMN_NAME"]: row["COLUMN_TYPE"].lower() for row in cursor.fetchall()}
                if customer != {"customer_id": "bigint unsigned", "birth_date": "date"}:
                    print("Unexpected customer schema. No changes were made.")
                    return 1
                if args.check:
                    print("Enrollment table needs to be created. No changes were made.")
                    return 0
                migration = Path(__file__).resolve().parent.parent / "database" / "migrations" / "026_customer_enrollment.sql"
                cursor.execute(migration.read_text(encoding="utf-8"))
            connection.commit()
        print("Enrollment table created. Existing customers, orders and shopping data were not rewritten.")
        return 0
    except Exception as error:
        print("Migration could not be confirmed. Error type:", type(error).__name__)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
