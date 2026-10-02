"""Transactional pickup ordering, payment, reservation release, and shipment."""

from collections.abc import Sequence
from datetime import datetime
from typing import Any
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from pymysql import MySQLError
from pymysql.connections import Connection

from .auth import CurrentCustomer, CurrentEmployee, get_current_customer, require_permission
from .database import mysql_connection
from .outbox import enqueue_outbox_event
from .schemas import (
    OrderCancelRequest,
    OrderItemCreateRequest,
    OrderReserveRequest,
    OrderTransactionResponse,
    PaymentCompleteRequest,
    PaymentFailRequest,
)
from .status_history import (
    record_fulfillment_status,
    record_initial_fulfillment_status,
    record_initial_order_status,
    record_initial_pickup_status,
    record_order_status,
)


router = APIRouter(tags=["orders"])


def validate_order_items(items: Sequence[OrderItemCreateRequest]) -> None:
    """Reject duplicate SKUs so each order has one unambiguous reservation row."""

    variant_ids = [item.productVariantId for item in items]
    if len(variant_ids) != len(set(variant_ids)):
        raise ValueError("Duplicate product variants are not allowed")


def _order_response(
    connection: Connection,
    order_id: int,
    payment_id: int | None = None,
    fulfillment_id: int | None = None,
) -> OrderTransactionResponse:
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT order_number,order_status FROM orders WHERE order_id=%s",
            (order_id,),
        )
        order = cursor.fetchone()
        cursor.execute(
            """
            SELECT COALESCE(SUM(reserved_quantity),0) AS reserved_quantity
            FROM inventory_reservations
            WHERE order_id=%s AND reservation_status='RESERVED'
            """,
            (order_id,),
        )
        reserved_quantity = int(cursor.fetchone()["reserved_quantity"])
    return OrderTransactionResponse(
        orderId=order_id,
        orderNumber=str(order["order_number"]),
        orderStatus=str(order["order_status"]),
        reservedQuantity=reserved_quantity,
        paymentId=payment_id,
        fulfillmentId=fulfillment_id,
    )


def _insert_movement(
    connection: Connection,
    *,
    product_variant_id: int,
    movement_type: str,
    on_hand_delta: int,
    reserved_delta: int,
    defective_delta: int,
    reference_type: str,
    reference_id: int,
    idempotency_key: str,
    reason: str,
) -> None:
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT on_hand_quantity,reserved_quantity,defective_quantity
            FROM headquarters_inventory WHERE product_variant_id=%s
            """,
            (product_variant_id,),
        )
        inventory = cursor.fetchone()
        cursor.execute(
            """
            INSERT INTO inventory_movements
              (product_variant_id,movement_type,on_hand_delta,reserved_delta,defective_delta,
               on_hand_after,reserved_after,defective_after,reference_type,reference_id,
               idempotency_key,reason)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                product_variant_id,
                movement_type,
                on_hand_delta,
                reserved_delta,
                defective_delta,
                inventory["on_hand_quantity"],
                inventory["reserved_quantity"],
                inventory["defective_quantity"],
                reference_type,
                reference_id,
                idempotency_key,
                reason,
            ),
        )
        movement_id = cursor.lastrowid
    enqueue_outbox_event(
        connection,
        aggregate_type="INVENTORY",
        aggregate_id=product_variant_id,
        event_type="INVENTORY_STATUS_CHANGED",
        payload={
            "productVariantId": product_variant_id,
            "onHandQuantity": int(inventory["on_hand_quantity"]),
            "reservedQuantity": int(inventory["reserved_quantity"]),
            "defectiveQuantity": int(inventory["defective_quantity"]),
            "availableQuantity": int(inventory["on_hand_quantity"])
            - int(inventory["reserved_quantity"])
            - int(inventory["defective_quantity"]),
            "movementType": movement_type,
        },
        idempotency_key=f"inventory-movement-{movement_id}",
    )


def _release_reservations(connection: Connection, order_id: int, reason: str, status_value: str = "RELEASED") -> None:
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT inventory_reservation_id,product_variant_id,reserved_quantity
            FROM inventory_reservations
            WHERE order_id=%s AND reservation_status='RESERVED'
            ORDER BY product_variant_id
            FOR UPDATE
            """,
            (order_id,),
        )
        reservations = cursor.fetchall()
        for reservation in reservations:
            cursor.execute(
                "SELECT product_variant_id FROM headquarters_inventory WHERE product_variant_id=%s FOR UPDATE",
                (reservation["product_variant_id"],),
            )
            cursor.execute(
                """
                UPDATE headquarters_inventory
                SET reserved_quantity=reserved_quantity-%s
                WHERE product_variant_id=%s AND reserved_quantity >= %s
                """,
                (
                    reservation["reserved_quantity"],
                    reservation["product_variant_id"],
                    reservation["reserved_quantity"],
                ),
            )
            if cursor.rowcount != 1:
                raise HTTPException(status_code=409, detail="Inventory reservation aggregate is inconsistent")
            _insert_movement(
                connection,
                product_variant_id=int(reservation["product_variant_id"]),
                movement_type="RESERVATION_RELEASE",
                on_hand_delta=0,
                reserved_delta=-int(reservation["reserved_quantity"]),
                defective_delta=0,
                reference_type="ORDER",
                reference_id=order_id,
                idempotency_key=f"order-release-{order_id}-{reservation['product_variant_id']}",
                reason=reason,
            )
        cursor.execute(
            """
            UPDATE inventory_reservations
            SET reservation_status=%s,released_at=NOW(),release_reason=%s
            WHERE order_id=%s AND reservation_status='RESERVED'
            """,
            (status_value, reason, order_id),
        )


@router.post("/orders/reserve", response_model=OrderTransactionResponse, status_code=status.HTTP_201_CREATED)
def reserve_order(
    request: OrderReserveRequest,
    current: CurrentCustomer = Depends(get_current_customer),
) -> OrderTransactionResponse:
    """Create a pickup order and reserve each SKU under one database transaction."""

    try:
        validate_order_items(request.items)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT order_id FROM orders WHERE order_request_key=%s", (request.idempotencyKey,))
                    existing = cursor.fetchone()
                    if existing is not None:
                        return _order_response(connection, int(existing["order_id"]))

                    cursor.execute("SELECT branch_id FROM branches WHERE branch_id=%s", (request.pickupBranchId,))
                    if cursor.fetchone() is None:
                        raise HTTPException(status_code=404, detail="Pickup branch not found")

                    variant_ids = sorted(item.productVariantId for item in request.items)
                    placeholders = ",".join(["%s"] * len(variant_ids))
                    cursor.execute(
                        f"""
                        SELECT v.product_variant_id,v.product_code,v.color_name,v.size_mm,
                               p.product_name,p.price,hi.on_hand_quantity,hi.reserved_quantity,
                               hi.defective_quantity,hi.available_quantity
                        FROM product_variants v
                        JOIN products p ON p.product_id=v.product_id
                        JOIN headquarters_inventory hi ON hi.product_variant_id=v.product_variant_id
                        WHERE v.product_variant_id IN ({placeholders})
                          AND v.is_active=TRUE AND p.is_active=TRUE
                        ORDER BY v.product_variant_id
                        FOR UPDATE
                        """,
                        variant_ids,
                    )
                    variants = {int(row["product_variant_id"]): row for row in cursor.fetchall()}
                    if len(variants) != len(variant_ids):
                        raise HTTPException(status_code=409, detail="One or more product variants are unavailable")
                    for item in request.items:
                        if item.quantity > int(variants[item.productVariantId]["available_quantity"]):
                            raise HTTPException(status_code=409, detail="Insufficient headquarters inventory")

                    subtotal = sum(int(variants[item.productVariantId]["price"]) * item.quantity for item in request.items)
                    order_number = f"ORD-{datetime.now():%Y%m%d}-{uuid4().hex[:12].upper()}"
                    cursor.execute(
                        """
                        INSERT INTO orders
                          (order_number,order_request_key,customer_id,pickup_branch_id,fulfillment_type,
                           order_status,subtotal_amount,coupon_discount,points_used,paid_total)
                        VALUES (%s,%s,%s,%s,'PICKUP','PENDING_PAYMENT',%s,0,0,%s)
                        """,
                        (order_number, request.idempotencyKey, current.customer_id, request.pickupBranchId, subtotal, subtotal),
                    )
                    order_id = cursor.lastrowid
                    record_initial_order_status(
                        connection,
                        order_id,
                        "PENDING_PAYMENT",
                        source="ORDER_API",
                        actor_customer_id=current.customer_id,
                    )

                    for item in request.items:
                        variant = variants[item.productVariantId]
                        cursor.execute(
                            """
                            INSERT INTO order_items
                              (order_id,product_variant_id,product_name,product_code,color_name,size_mm,unit_price,quantity)
                            VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                            """,
                            (
                                order_id,
                                item.productVariantId,
                                variant["product_name"],
                                variant["product_code"],
                                variant["color_name"],
                                variant["size_mm"],
                                variant["price"],
                                item.quantity,
                            ),
                        )
                        order_item_id = cursor.lastrowid
                        cursor.execute(
                            """
                            UPDATE headquarters_inventory
                            SET reserved_quantity=reserved_quantity+%s
                            WHERE product_variant_id=%s AND available_quantity >= %s
                            """,
                            (item.quantity, item.productVariantId, item.quantity),
                        )
                        if cursor.rowcount != 1:
                            raise HTTPException(status_code=409, detail="Inventory changed during reservation")
                        cursor.execute(
                            """
                            INSERT INTO inventory_reservations
                              (order_id,order_item_id,product_variant_id,reserved_quantity,expires_at)
                            VALUES (%s,%s,%s,%s,DATE_ADD(NOW(),INTERVAL 15 MINUTE))
                            """,
                            (order_id, order_item_id, item.productVariantId, item.quantity),
                        )
                        _insert_movement(
                            connection,
                            product_variant_id=item.productVariantId,
                            movement_type="ORDER_RESERVATION",
                            on_hand_delta=0,
                            reserved_delta=item.quantity,
                            defective_delta=0,
                            reference_type="ORDER",
                            reference_id=order_id,
                            idempotency_key=f"order-reserve-{order_id}-{item.productVariantId}",
                            reason="주문 결제 대기 재고 예약",
                        )

                    cursor.execute(
                        """
                        SELECT pickup_retention_policy_id
                        FROM pickup_retention_policies
                        WHERE effective_from <= CURRENT_DATE
                          AND (effective_to IS NULL OR effective_to >= CURRENT_DATE)
                        ORDER BY effective_from DESC LIMIT 1
                        """
                    )
                    policy = cursor.fetchone()
                    cursor.execute(
                        """
                        INSERT INTO pickups (order_id,pickup_retention_policy_id,branch_id,pickup_status)
                        VALUES (%s,%s,%s,'PREPARING')
                        """,
                        (
                            order_id,
                            None if policy is None else policy["pickup_retention_policy_id"],
                            request.pickupBranchId,
                        ),
                    )
                    pickup_id = cursor.lastrowid
                    record_initial_pickup_status(
                        connection,
                        pickup_id,
                        "PREPARING",
                        source="ORDER_API",
                    )
                connection.commit()
                return _order_response(connection, order_id)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error


@router.post("/orders/{order_id}/payments/complete", response_model=OrderTransactionResponse)
def complete_payment(order_id: int, request: PaymentCompleteRequest) -> OrderTransactionResponse:
    """Confirm payment and create the headquarters-to-branch fulfillment."""

    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT * FROM orders WHERE order_id=%s FOR UPDATE", (order_id,))
                    order = cursor.fetchone()
                    if order is None:
                        raise HTTPException(status_code=404, detail="Order not found")
                    cursor.execute("SELECT payment_id,order_id FROM payments WHERE transaction_key=%s", (request.transactionKey,))
                    existing_payment = cursor.fetchone()
                    if existing_payment is not None:
                        if int(existing_payment["order_id"]) != order_id:
                            raise HTTPException(status_code=409, detail="Transaction key belongs to another order")
                        cursor.execute("SELECT fulfillment_id FROM fulfillments WHERE order_id=%s ORDER BY fulfillment_id LIMIT 1", (order_id,))
                        fulfillment = cursor.fetchone()
                        return _order_response(
                            connection,
                            order_id,
                            int(existing_payment["payment_id"]),
                            None if fulfillment is None else int(fulfillment["fulfillment_id"]),
                        )
                    if order["order_status"] != "PENDING_PAYMENT":
                        raise HTTPException(status_code=409, detail="Order is not awaiting payment")
                    cursor.execute(
                        """
                        SELECT COUNT(*) AS count
                        FROM inventory_reservations
                        WHERE order_id=%s AND reservation_status='RESERVED' AND expires_at > NOW()
                        """,
                        (order_id,),
                    )
                    active_count = int(cursor.fetchone()["count"])
                    cursor.execute("SELECT COUNT(*) AS count FROM order_items WHERE order_id=%s", (order_id,))
                    if active_count != int(cursor.fetchone()["count"]):
                        raise HTTPException(status_code=409, detail="Inventory reservation expired or was released")

                    cursor.execute(
                        """
                        INSERT INTO payments
                          (order_id,payment_method,payment_status,payment_amount,transaction_key,paid_at)
                        VALUES (%s,%s,'PAID',%s,%s,NOW())
                        """,
                        (order_id, request.paymentMethod, order["paid_total"], request.transactionKey),
                    )
                    payment_id = cursor.lastrowid
                    record_order_status(
                        connection,
                        order_id,
                        "PAID",
                        source="PAYMENT_API",
                        reason="결제 성공",
                    )
                    fulfillment_number = f"FF-{datetime.now():%Y%m%d}-{uuid4().hex[:12].upper()}"
                    cursor.execute(
                        """
                        INSERT INTO fulfillments
                          (fulfillment_number,order_id,destination_branch_id,fulfillment_status)
                        VALUES (%s,%s,%s,'PREPARING')
                        """,
                        (fulfillment_number, order_id, order["pickup_branch_id"]),
                    )
                    fulfillment_id = cursor.lastrowid
                    record_initial_fulfillment_status(
                        connection,
                        fulfillment_id,
                        "PREPARING",
                        source="PAYMENT_API",
                    )
                    cursor.execute(
                        """
                        INSERT INTO fulfillment_items (fulfillment_id,order_id,order_item_id,quantity)
                        SELECT %s,order_id,order_item_id,quantity FROM order_items WHERE order_id=%s
                        """,
                        (fulfillment_id, order_id),
                    )
                connection.commit()
                return _order_response(connection, order_id, payment_id, fulfillment_id)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error


@router.post("/orders/{order_id}/payments/fail", response_model=OrderTransactionResponse)
def fail_payment(order_id: int, request: PaymentFailRequest) -> OrderTransactionResponse:
    """Record a failed attempt and return all reserved stock."""

    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT * FROM orders WHERE order_id=%s FOR UPDATE", (order_id,))
                    order = cursor.fetchone()
                    if order is None:
                        raise HTTPException(status_code=404, detail="Order not found")
                    if order["order_status"] != "PENDING_PAYMENT":
                        raise HTTPException(status_code=409, detail="Order is not awaiting payment")
                    cursor.execute(
                        """
                        INSERT INTO payments
                          (order_id,payment_method,payment_status,payment_amount,transaction_key)
                        VALUES (%s,%s,'FAILED',%s,%s)
                        """,
                        (order_id, request.paymentMethod, order["paid_total"], request.transactionKey),
                    )
                    payment_id = cursor.lastrowid
                    _release_reservations(connection, order_id, request.failureReason)
                    record_order_status(
                        connection,
                        order_id,
                        "CANCELED",
                        source="PAYMENT_API",
                        reason=request.failureReason,
                    )
                    cursor.execute("UPDATE orders SET canceled_at=NOW() WHERE order_id=%s", (order_id,))
                connection.commit()
                return _order_response(connection, order_id, payment_id)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error


@router.post("/orders/{order_id}/cancel", response_model=OrderTransactionResponse)
def cancel_order(
    order_id: int,
    request: OrderCancelRequest,
    current: CurrentCustomer = Depends(get_current_customer),
) -> OrderTransactionResponse:
    """Cancel an unpaid order and release its reservation."""

    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT order_status,customer_id FROM orders WHERE order_id=%s FOR UPDATE", (order_id,))
                    order = cursor.fetchone()
                    if order is None:
                        raise HTTPException(status_code=404, detail="Order not found")
                    if int(order["customer_id"]) != current.customer_id:
                        raise HTTPException(status_code=403, detail="Order belongs to another customer")
                    if order["order_status"] != "PENDING_PAYMENT":
                        raise HTTPException(status_code=409, detail="Paid orders must use the refund flow")
                    _release_reservations(connection, order_id, request.reason)
                    record_order_status(
                        connection,
                        order_id,
                        "CANCELED",
                        source="ORDER_API",
                        reason=request.reason,
                        actor_type="CUSTOMER",
                        actor_customer_id=int(order["customer_id"]),
                    )
                    cursor.execute("UPDATE orders SET canceled_at=NOW() WHERE order_id=%s", (order_id,))
                connection.commit()
                return _order_response(connection, order_id)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error


@router.post("/fulfillments/{fulfillment_id}/ship", response_model=OrderTransactionResponse)
def ship_fulfillment(
    fulfillment_id: int,
    current: CurrentEmployee = Depends(require_permission("INVENTORY_SHIP")),
) -> OrderTransactionResponse:
    """Consume reserved stock when goods physically leave headquarters."""

    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT * FROM fulfillments WHERE fulfillment_id=%s FOR UPDATE", (fulfillment_id,))
                    fulfillment = cursor.fetchone()
                    if fulfillment is None:
                        raise HTTPException(status_code=404, detail="Fulfillment not found")
                    if fulfillment["fulfillment_status"] == "IN_TRANSIT":
                        return _order_response(connection, int(fulfillment["order_id"]), fulfillment_id=fulfillment_id)
                    if fulfillment["fulfillment_status"] != "PREPARING":
                        raise HTTPException(status_code=409, detail="Fulfillment is not ready to ship")
                    cursor.execute(
                        """
                        SELECT ir.inventory_reservation_id,ir.product_variant_id,ir.reserved_quantity
                        FROM inventory_reservations ir
                        WHERE ir.order_id=%s AND ir.reservation_status='RESERVED'
                        ORDER BY ir.product_variant_id
                        FOR UPDATE
                        """,
                        (fulfillment["order_id"],),
                    )
                    reservations = cursor.fetchall()
                    if not reservations:
                        raise HTTPException(status_code=409, detail="No active inventory reservation")
                    for reservation in reservations:
                        cursor.execute(
                            "SELECT product_variant_id FROM headquarters_inventory WHERE product_variant_id=%s FOR UPDATE",
                            (reservation["product_variant_id"],),
                        )
                        cursor.execute(
                            """
                            UPDATE headquarters_inventory
                            SET on_hand_quantity=on_hand_quantity-%s,
                                reserved_quantity=reserved_quantity-%s
                            WHERE product_variant_id=%s
                              AND on_hand_quantity >= %s AND reserved_quantity >= %s
                            """,
                            (
                                reservation["reserved_quantity"], reservation["reserved_quantity"],
                                reservation["product_variant_id"], reservation["reserved_quantity"],
                                reservation["reserved_quantity"],
                            ),
                        )
                        if cursor.rowcount != 1:
                            raise HTTPException(status_code=409, detail="Reserved inventory is inconsistent")
                        _insert_movement(
                            connection,
                            product_variant_id=int(reservation["product_variant_id"]),
                            movement_type="ORDER_SHIPMENT",
                            on_hand_delta=-int(reservation["reserved_quantity"]),
                            reserved_delta=-int(reservation["reserved_quantity"]),
                            defective_delta=0,
                            reference_type="FULFILLMENT",
                            reference_id=fulfillment_id,
                            idempotency_key=f"fulfillment-ship-{fulfillment_id}-{reservation['product_variant_id']}",
                            reason="결제 완료 주문 본사 출고",
                        )
                    cursor.execute(
                        """
                        UPDATE inventory_reservations
                        SET reservation_status='CONSUMED',consumed_at=NOW()
                        WHERE order_id=%s AND reservation_status='RESERVED'
                        """,
                        (fulfillment["order_id"],),
                    )
                    record_fulfillment_status(
                        connection,
                        fulfillment_id,
                        "IN_TRANSIT",
                        source="FULFILLMENT_API",
                        reason="본사 출고 완료",
                        actor_employee_id=current.employee_id,
                    )
                    cursor.execute("UPDATE fulfillments SET shipped_at=NOW() WHERE fulfillment_id=%s", (fulfillment_id,))
                    record_order_status(
                        connection,
                        int(fulfillment["order_id"]),
                        "SHIPPING",
                        source="FULFILLMENT_API",
                        reason="본사에서 수령 대리점으로 출고",
                        actor_type="EMPLOYEE",
                        actor_employee_id=current.employee_id,
                    )
                connection.commit()
                return _order_response(connection, int(fulfillment["order_id"]), fulfillment_id=fulfillment_id)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
