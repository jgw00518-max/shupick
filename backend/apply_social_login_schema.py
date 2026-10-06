"""Apply only optional customer email to the local test DB, preserving all data."""

import argparse

from app.config import settings
from app.database import mysql_connection


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='Read-only schema check')
    args = parser.parse_args(argv)
    if settings.mysql_host not in {'127.0.0.1', 'localhost', '::1'} or settings.mysql_database != 'shupick_v2':
        print('Refusing: only the local shupick_v2 test DB is supported.')
        return 1
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT COLUMN_TYPE,IS_NULLABLE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='customers' AND COLUMN_NAME='email'")
                column = cursor.fetchone()
                if column is None or column['COLUMN_TYPE'].lower() != 'varchar(255)':
                    print('Unexpected customer email schema; no change was made.')
                    return 1
                if column['IS_NULLABLE'] == 'YES':
                    print('Customer email is already optional. No change was made.')
                    return 0
                if args.check:
                    print('Customer email must become optional for social login. No change was made.')
                    return 0
                cursor.execute('ALTER TABLE customers MODIFY COLUMN email VARCHAR(255) NULL')
            connection.commit()
            print('Customer email is now optional. No customer/order/inquiry data was rewritten.')
            return 0
    except Exception as error:
        print('Schema change could not be confirmed. Error type:', type(error).__name__)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
