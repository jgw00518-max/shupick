"""Transactional refund creation, completion, and coupon restoration."""

from collections.abc import Sequence
from datetime import datetime
from typing import Any
from uuid import uuid4

from fastapi import APIRouter, HTTPException, status
from pymysql import MySQLError
from pymysql.connections import Connection

from .database import mysql_connection
from .schemas import (
    RefundCompleteRequest,
    RefundCreateRequest,
    RefundItemRequest,
    RefundResponse,
)
from .status_history import record_order_status


router = APIRouter(prefix="/refunds", tags=["refunds"])


def validate_refund_items(
    refund_type: str,
    refund_amount: int,
    items: Sequence[RefundItemRequest],
) -> None:
    """Reject incomplete or ambiguous item allocation before opening a transaction."""

    if refund_type != "RETURN":
        if items:
            raise ValueError("Only RETURN refunds can include items")
        return

    if not items:
        raise ValueError("RETURN refunds require at least one item")
    item_ids = [item.orderItemId for item in items]
    if len(item_ids) != len(set(item_ids)):
        raise ValueError("Duplicate order items are not allowed")
    if sum(item.refundAmount for item in items) != refund_amount:
        raise ValueError("Refund item amounts must equal the refund amount")


def _refund_response(row: dict[str, Any], restored_coupon_count: int = 0) -> RefundResponse:
    return RefundResponse(
        refundId=int(row["refund_id"]),
        refundNumber=str(row["refund_number"]),
        paymentId=int(row["payment_id"]),
        orderId=int(row["order_id"]),
        refundType=str(row["refund_type"]),
        refundStatus=str(row["refund_status"]),
        refundAmount=int(row["refund_amount"]),
        retryCount=int(row["retry_count"]),
        restoredCouponCount=restored_coupon_count,
    )


def _load_refund_by_idempotency(connection: Connection, key: str) -> dict[str, Any] | None:
    with connection.cursor() as cursor:
        cursor.execute("SELECT * FROM refunds WHERE idempotency_key = %s", (key,))
        return cursor.fetchone()


def _validate_return_items(
    connection: Connection,
    order_id: int,
    items: Sequence[RefundItemRequest],
) -> None:
    item_ids = [item.orderItemId for item in items]
    placeholders = ",".join(["%s"] * len(item_ids))
    with connection.cursor() as cursor:
        cursor.execute(
            f"""
            SELECT order_item_id, quantity, unit_price
            FROM order_items
            WHERE order_id = %s AND order_item_id IN ({placeholders})
            FOR UPDATE
            """,
            (order_id, *item_ids),
        )
        order_items = {int(row["order_item_id"]): row for row in cursor.fetchall()}
        if len(order_items) != len(item_ids):
            raise HTTPException(status_code=409, detail="Refund item does not belong to the payment order")

        cursor.execute(
            f"""
            SELECT ri.order_item_id, COALESCE(SUM(ri.quantity), 0) AS refunded_quantity
            FROM refund_items ri
            JOIN refunds r ON r.refund_id = ri.refund_id
            WHERE ri.order_id = %s
              AND ri.order_item_id IN ({placeholders})
              AND r.refund_status IN ('REQUESTED','PROCESSING','SUCCEEDED')
            GROUP BY ri.order_item_id
            """,
            (order_id, *item_ids),
        )
        used_quantities = {
            int(row["order_item_id"]): int(row["refunded_quantity"])
            for row in cursor.fetchall()
        }

    for item in items:
        order_item = order_items[item.orderItemId]
        remaining_quantity = int(order_item["quantity"]) - used_quantities.get(item.orderItemId, 0)
        if item.quantity > remaining_quantity:
            raise HTTPException(status_code=409, detail="Refund quantity exceeds the remaining order quantity")
        if item.refundAmount > int(order_item["unit_price"]) * item.quantity:
            raise HTTPException(status_code=409, detail="Refund item amount exceeds its order line amount")


@router.post("", response_model=RefundResponse, status_code=status.HTTP_201_CREATED)
def create_refund(request: RefundCreateRequest) -> RefundResponse:
    """Reserve a refund amount while locking its original payment."""

    try:
        validate_refund_items(request.refundType, request.refundAmount, request.items)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """
                        SELECT payment_id, order_id, payment_status, payment_amount
                        FROM payments
                        WHERE payment_id = %s
                        FOR UPDATE
                        """,
                        (request.paymentId,),
                    )
                    payment = cursor.fetchone()
                    if payment is None:
                        raise HTTPException(status_code=404, detail="Payment not found")
                    if payment["payment_status"] not in ("PAID", "PARTIALLY_REFUNDED"):
                        raise HTTPException(status_code=409, detail="Payment is not refundable")

                    order_id = int(payment["order_id"])
                    existing = _load_refund_by_idempotency(connection, request.idempotencyKey)
                    if existing is not None:
                        same_request = (
                            int(existing["payment_id"]) == request.paymentId
                            and str(existing["refund_type"]) == request.refundType
                            and int(existing["refund_amount"]) == request.refundAmount
                        )
                        if not same_request:
                            raise HTTPException(status_code=409, detail="Idempotency key was used for another refund")
                        return _refund_response(existing)

                    cursor.execute(
                        """
                        SELECT COALESCE(SUM(refund_amount), 0) AS reserved_amount
                        FROM refunds
                        WHERE payment_id = %s
                          AND refund_status IN ('REQUESTED','PROCESSING','SUCCEEDED')
                        """,
                        (request.paymentId,),
                    )
                    reserved_amount = int(cursor.fetchone()["reserved_amount"])
                    remaining_amount = int(payment["payment_amount"]) - reserved_amount
                    if request.refundAmount > remaining_amount:
                        raise HTTPException(status_code=409, detail="Refund amount exceeds the remaining payment amount")
                    if request.refundType == "ORDER_CANCEL" and request.refundAmount != remaining_amount:
                        raise HTTPException(status_code=409, detail="Order cancellation must refund the full remaining amount")

                    if request.refundType == "RETURN":
                        if request.returnRequestId is None:
                            raise HTTPException(status_code=422, detail="RETURN refund requires returnRequestId")
                        cursor.execute(
                            "SELECT return_request_id FROM return_requests WHERE return_request_id=%s AND order_id=%s FOR UPDATE",
                            (request.returnRequestId, order_id),
                        )
                        if cursor.fetchone() is None:
                            raise HTTPException(status_code=409, detail="Return request does not belong to the payment order")
                        _validate_return_items(connection, order_id, request.items)
                    elif request.returnRequestId is not None:
                        raise HTTPException(status_code=422, detail="Only RETURN refunds can reference a return request")

                    refund_number = f"RF-{datetime.now():%Y%m%d}-{uuid4().hex[:12].upper()}"
                    cursor.execute(
                        """
                        INSERT INTO refunds
                          (refund_number, payment_id, order_id, return_request_id, refund_type,
                           refund_status, refund_amount, idempotency_key)
                        VALUES (%s,%s,%s,%s,%s,'REQUESTED',%s,%s)
                        """,
                        (
                            refund_number,
                            request.paymentId,
                            order_id,
                            request.returnRequestId,
                            request.refundType,
                            request.refundAmount,
                            request.idempotencyKey,
                        ),
                    )
                    refund_id = cursor.lastrowid
                    for item in request.items:
                        cursor.execute(
                            """
                            INSERT INTO refund_items
                              (refund_id, order_id, order_item_id, quantity, refund_amount)
                            VALUES (%s,%s,%s,%s,%s)
                            """,
                            (refund_id, order_id, item.orderItemId, item.quantity, item.refundAmount),
                        )
                    cursor.execute("SELECT * FROM refunds WHERE refund_id=%s", (refund_id,))
                    row = cursor.fetchone()
                connection.commit()
                return _refund_response(row)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error


@router.post("/{refund_id}/complete", response_model=RefundResponse)
def complete_refund(refund_id: int, request: RefundCompleteRequest) -> RefundResponse:
    """Record provider success and restore an eligible coupon atomically."""

    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """
                        SELECT r.*, p.payment_amount
                        FROM refunds r
                        JOIN payments p ON p.payment_id=r.payment_id AND p.order_id=r.order_id
                        WHERE r.refund_id=%s
                        FOR UPDATE
                        """,
                        (refund_id,),
                    )
                    refund = cursor.fetchone()
                    if refund is None:
                        raise HTTPException(status_code=404, detail="Refund not found")
                    if refund["refund_status"] == "SUCCEEDED":
                        return _refund_response(refund)
                    if refund["refund_status"] == "CANCELED":
                        raise HTTPException(status_code=409, detail="Canceled refund cannot be completed")

                    retry_increment = 1 if refund["refund_status"] == "FAILED" else 0
                    cursor.execute(
                        """
                        UPDATE refunds
                        SET refund_status='SUCCEEDED', provider_refund_key=%s,
                            retry_count=retry_count+%s, failure_code=NULL, failure_message=NULL,
                            failed_at=NULL, completed_at=NOW()
                        WHERE refund_id=%s
                        """,
                        (request.providerRefundKey, retry_increment, refund_id),
                    )
                    cursor.execute(
                        """
                        SELECT COALESCE(SUM(refund_amount),0) AS succeeded_amount
                        FROM refunds
                        WHERE payment_id=%s AND refund_status='SUCCEEDED'
                        """,
                        (refund["payment_id"],),
                    )
                    succeeded_amount = int(cursor.fetchone()["succeeded_amount"])
                    is_full_refund = succeeded_amount == int(refund["payment_amount"])
                    cursor.execute(
                        "UPDATE payments SET payment_status=%s WHERE payment_id=%s",
                        ("REFUNDED" if is_full_refund else "PARTIALLY_REFUNDED", refund["payment_id"]),
                    )

                    restored_coupon_count = 0
                    if is_full_refund and refund["refund_type"] == "ORDER_CANCEL":
                        cursor.execute(
                            """
                            SELECT * FROM coupon_refund_policies
                            WHERE effective_from <= CURRENT_DATE
                              AND (effective_to IS NULL OR effective_to >= CURRENT_DATE)
                              AND restore_on_full_cancel = TRUE
                            ORDER BY effective_from DESC LIMIT 1
                            """
                        )
                        policy = cursor.fetchone()
                        if policy is not None:
                            expiry_condition = "AND expires_at >= NOW()" if policy["require_unexpired_coupon"] else ""
                            cursor.execute(
                                f"""
                                SELECT customer_coupon_id, coupon_status
                                FROM customer_coupons
                                WHERE used_order_id=%s AND coupon_status='USED' {expiry_condition}
                                FOR UPDATE
                                """,
                                (refund["order_id"],),
                            )
                            coupons = cursor.fetchall()
                            for coupon in coupons:
                                cursor.execute(
                                    """
                                    INSERT INTO coupon_restorations
                                      (customer_coupon_id,refund_id,coupon_refund_policy_id,
                                       previous_status,restoration_reason)
                                    VALUES (%s,%s,%s,%s,'전체 주문 취소 환불 성공')
                                    """,
                                    (
                                        coupon["customer_coupon_id"], refund_id,
                                        policy["coupon_refund_policy_id"], coupon["coupon_status"],
                                    ),
                                )
                                cursor.execute(
                                    """
                                    UPDATE customer_coupons
                                    SET coupon_status='AVAILABLE', used_order_id=NULL, used_at=NULL
                                    WHERE customer_coupon_id=%s
                                    """,
                                    (coupon["customer_coupon_id"],),
                                )
                                restored_coupon_count += 1

                    if is_full_refund:
                        record_order_status(
                            connection,
                            int(refund["order_id"]),
                            "REFUNDED",
                            source="REFUND_API",
                            reason="전액 환불 성공",
                        )
                    cursor.execute("SELECT * FROM refunds WHERE refund_id=%s", (refund_id,))
                    completed = cursor.fetchone()
                connection.commit()
                return _refund_response(completed, restored_coupon_count)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
