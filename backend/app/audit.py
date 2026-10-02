"""Append-only audit log helpers."""

import json
from typing import Any

from pymysql.connections import Connection


def write_employee_audit(
    connection: Connection,
    *,
    employee_id: int,
    action_code: str,
    entity_type: str,
    entity_id: int,
    before_data: dict[str, Any] | None,
    after_data: dict[str, Any] | None,
    request_id: str | None = None,
    ip_address: str | None = None,
) -> None:
    """Write an employee action inside the caller's business transaction."""

    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO audit_logs
              (actor_type,actor_employee_id,action_code,entity_type,entity_id,
               before_data,after_data,request_id,ip_address)
            VALUES ('EMPLOYEE',%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                employee_id,
                action_code,
                entity_type,
                entity_id,
                None if before_data is None else json.dumps(before_data, ensure_ascii=False, default=str),
                None if after_data is None else json.dumps(after_data, ensure_ascii=False, default=str),
                request_id,
                ip_address,
            ),
        )
