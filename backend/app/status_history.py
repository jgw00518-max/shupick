"""Append-only status history writers and read endpoints."""

from typing import Any, Literal

from fastapi import APIRouter, HTTPException
from pymysql import MySQLError
from pymysql.connections import Connection

from .database import mysql_connection
from .outbox import enqueue_outbox_event
from .schemas import StatusHistoryResponse


router = APIRouter(tags=["status-history"])
ActorType = Literal["SYSTEM", "CUSTOMER", "EMPLOYEE"]


def record_order_status(
    connection: Connection,
    order_id: int,
    new_status: str,
    *,
    source: str,
    reason: str | None = None,
    actor_type: ActorType = "SYSTEM",
    actor_customer_id: int | None = None,
    actor_employee_id: int | None = None,
) -> None:
    """Update an order and append its transition within the caller transaction."""

    with connection.cursor() as cursor:
        cursor.execute("SELECT order_status FROM orders WHERE order_id=%s FOR UPDATE", (order_id,))
        row = cursor.fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Order not found")
        previous_status = str(row["order_status"])
        if previous_status == new_status:
            return
        cursor.execute("UPDATE orders SET order_status=%s WHERE order_id=%s", (new_status, order_id))
        cursor.execute(
            """
            INSERT INTO order_status_history
              (order_id,previous_status,new_status,change_source,change_reason,
               actor_type,actor_customer_id,actor_employee_id)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                order_id, previous_status, new_status, source, reason,
                actor_type, actor_customer_id, actor_employee_id,
            ),
        )
        history_id = cursor.lastrowid
    enqueue_outbox_event(
        connection,
        aggregate_type="ORDER",
        aggregate_id=order_id,
        event_type="ORDER_STATUS_CHANGED",
        payload={
            "orderId": order_id,
            "previousStatus": previous_status,
            "status": new_status,
            "changeSource": source,
            "changeReason": reason,
        },
        idempotency_key=f"order-status-history-{history_id}",
    )


def record_initial_order_status(
    connection: Connection,
    order_id: int,
    status_value: str,
    *,
    source: str,
    actor_customer_id: int,
) -> None:
    """Append the initial order state after its row is created."""

    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO order_status_history
              (order_id,previous_status,new_status,change_source,actor_type,actor_customer_id)
            VALUES (%s,NULL,%s,%s,'CUSTOMER',%s)
            """,
            (order_id, status_value, source, actor_customer_id),
        )
        history_id = cursor.lastrowid
    enqueue_outbox_event(
        connection,
        aggregate_type="ORDER",
        aggregate_id=order_id,
        event_type="ORDER_STATUS_CHANGED",
        payload={"orderId": order_id, "previousStatus": None, "status": status_value, "changeSource": source},
        idempotency_key=f"order-status-history-{history_id}",
    )


def record_fulfillment_status(
    connection: Connection,
    fulfillment_id: int,
    new_status: str,
    *,
    source: str,
    reason: str | None = None,
    actor_employee_id: int | None = None,
) -> None:
    """Update a fulfillment and append its transition."""

    actor_type: ActorType = "EMPLOYEE" if actor_employee_id is not None else "SYSTEM"
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT fulfillment_status FROM fulfillments WHERE fulfillment_id=%s FOR UPDATE",
            (fulfillment_id,),
        )
        row = cursor.fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Fulfillment not found")
        previous_status = str(row["fulfillment_status"])
        if previous_status == new_status:
            return
        cursor.execute(
            "UPDATE fulfillments SET fulfillment_status=%s WHERE fulfillment_id=%s",
            (new_status, fulfillment_id),
        )
        cursor.execute(
            """
            INSERT INTO fulfillment_status_history
              (fulfillment_id,previous_status,new_status,change_source,change_reason,
               actor_type,actor_employee_id)
            VALUES (%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                fulfillment_id, previous_status, new_status, source, reason,
                actor_type, actor_employee_id,
            ),
        )
        history_id = cursor.lastrowid
    enqueue_outbox_event(
        connection,
        aggregate_type="FULFILLMENT",
        aggregate_id=fulfillment_id,
        event_type="FULFILLMENT_STATUS_CHANGED",
        payload={
            "fulfillmentId": fulfillment_id,
            "previousStatus": previous_status,
            "status": new_status,
            "changeSource": source,
            "changeReason": reason,
        },
        idempotency_key=f"fulfillment-status-history-{history_id}",
    )


def record_initial_fulfillment_status(
    connection: Connection,
    fulfillment_id: int,
    status_value: str,
    *,
    source: str,
) -> None:
    """Append the initial fulfillment state after its row is created."""

    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO fulfillment_status_history
              (fulfillment_id,previous_status,new_status,change_source,actor_type)
            VALUES (%s,NULL,%s,%s,'SYSTEM')
            """,
            (fulfillment_id, status_value, source),
        )
        history_id = cursor.lastrowid
    enqueue_outbox_event(
        connection,
        aggregate_type="FULFILLMENT",
        aggregate_id=fulfillment_id,
        event_type="FULFILLMENT_STATUS_CHANGED",
        payload={
            "fulfillmentId": fulfillment_id,
            "previousStatus": None,
            "status": status_value,
            "changeSource": source,
        },
        idempotency_key=f"fulfillment-status-history-{history_id}",
    )


def record_initial_pickup_status(
    connection: Connection,
    pickup_id: int,
    status_value: str,
    *,
    source: str,
) -> None:
    """Append the initial pickup state after its row is created."""

    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO pickup_status_history
              (pickup_id,previous_status,new_status,change_source,actor_type)
            VALUES (%s,NULL,%s,%s,'SYSTEM')
            """,
            (pickup_id, status_value, source),
        )
        history_id = cursor.lastrowid
    enqueue_outbox_event(
        connection,
        aggregate_type="PICKUP",
        aggregate_id=pickup_id,
        event_type="PICKUP_STATUS_CHANGED",
        payload={"pickupId": pickup_id, "previousStatus": None, "status": status_value, "changeSource": source},
        idempotency_key=f"pickup-status-history-{history_id}",
    )


def _history_response(row: dict[str, Any]) -> StatusHistoryResponse:
    return StatusHistoryResponse(
        previousStatus=row["previous_status"],
        newStatus=str(row["new_status"]),
        changeSource=str(row["change_source"]),
        changeReason=row["change_reason"],
        actorType=str(row["actor_type"]),
        actorCustomerId=row.get("actor_customer_id"),
        actorEmployeeId=row.get("actor_employee_id"),
        changedAt=row["changed_at"],
    )


def _read_history(table: str, id_column: str, entity_id: int) -> list[StatusHistoryResponse]:
    primary_keys = {
        ("order_status_history", "order_id"): "order_status_history_id",
        ("fulfillment_status_history", "fulfillment_id"): "fulfillment_status_history_id",
        ("pickup_status_history", "pickup_id"): "pickup_status_history_id",
    }
    history_key = primary_keys.get((table, id_column))
    if history_key is None:
        raise ValueError("Unsupported history table")
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    f"SELECT * FROM {table} WHERE {id_column}=%s ORDER BY changed_at,{history_key}",
                    (entity_id,),
                )
                rows = cursor.fetchall()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return [_history_response(row) for row in rows]


@router.get("/orders/{order_id}/status-history", response_model=list[StatusHistoryResponse])
def get_order_status_history(order_id: int) -> list[StatusHistoryResponse]:
    return _read_history("order_status_history", "order_id", order_id)


@router.get("/fulfillments/{fulfillment_id}/status-history", response_model=list[StatusHistoryResponse])
def get_fulfillment_status_history(fulfillment_id: int) -> list[StatusHistoryResponse]:
    return _read_history("fulfillment_status_history", "fulfillment_id", fulfillment_id)


@router.get("/pickups/{pickup_id}/status-history", response_model=list[StatusHistoryResponse])
def get_pickup_status_history(pickup_id: int) -> list[StatusHistoryResponse]:
    return _read_history("pickup_status_history", "pickup_id", pickup_id)
