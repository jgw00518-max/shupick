"""MySQL connection helpers shared by API repositories."""

from contextlib import contextmanager
from typing import Iterator

import pymysql
from pymysql.connections import Connection

from .config import settings


@contextmanager
def mysql_connection() -> Iterator[Connection]:
    """Open one request-scoped connection and always close it."""

    connection = pymysql.connect(
        host=settings.mysql_host,
        port=settings.mysql_port,
        user=settings.mysql_user,
        password=settings.mysql_password,
        database=settings.mysql_database,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
    )
    try:
        yield connection
    finally:
        connection.close()
