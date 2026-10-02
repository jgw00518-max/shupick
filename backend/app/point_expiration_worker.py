"""Scheduled entrypoint for expiring point lots after one year."""

from pymysql import MySQLError

from .database import mysql_connection
from .points import expire_all_due_points


def run_once() -> int:
    with mysql_connection() as connection:
        expired = expire_all_due_points(connection)
        connection.commit()
        return expired


if __name__ == "__main__":
    try:
        print(f"expired_points={run_once()}")
    except MySQLError as error:
        raise SystemExit(f"Point expiration failed: {error}") from error
