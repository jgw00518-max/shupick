"""Checkout benefits applied atomically with demo payment confirmation."""
from fastapi import APIRouter, Depends, HTTPException
from .auth import CurrentCustomer, get_current_customer
from .database import mysql_connection
from .points import _expire_customer_points

router = APIRouter(tags=["coupons"])


def coupon_discount(coupon: dict, subtotal: int) -> int:
    if subtotal < int(coupon["minimum_order_amount"]):
        raise HTTPException(409, "Coupon minimum order amount not met")
    amount = (subtotal * int(coupon["discount_value"]) // 100
              if coupon["discount_type"] == "PERCENT" else int(coupon["discount_value"]))
    cap = coupon["maximum_discount_amount"]
    return min(subtotal, amount if cap is None else min(amount, int(cap)))


@router.get("/coupons")
def list_coupons(current: CurrentCustomer = Depends(get_current_customer)) -> list[dict]:
    with mysql_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""SELECT cc.customer_coupon_id AS id,cd.coupon_name AS name,
                cd.discount_type AS discountType,cd.discount_value AS discountValue,
                cd.minimum_order_amount AS minimumOrderAmount,
                cd.maximum_discount_amount AS maximumDiscountAmount,cc.expires_at AS expiresAt
                FROM customer_coupons cc JOIN coupon_definitions cd
                ON cd.coupon_definition_id=cc.coupon_definition_id
                WHERE cc.customer_id=%s AND cc.coupon_status='AVAILABLE'
                AND cc.issued_at<=NOW() AND cc.expires_at>NOW() AND cd.is_active=TRUE
                ORDER BY cc.expires_at,cc.customer_coupon_id""", (current.customer_id,))
            return cursor.fetchall()


def apply_benefits(connection, order: dict, coupon_id: int | None, points: int) -> int:
    """Caller holds the order lock; any later failure rolls all ledgers back."""
    customer_id, order_id = order["customer_id"], order["order_id"]
    subtotal = int(order["subtotal_amount"])
    discount = 0
    with connection.cursor() as cursor:
        if coupon_id is not None:
            cursor.execute("""SELECT cd.* FROM customer_coupons cc JOIN coupon_definitions cd
                ON cd.coupon_definition_id=cc.coupon_definition_id
                WHERE cc.customer_coupon_id=%s AND cc.customer_id=%s
                AND cc.coupon_status='AVAILABLE' AND cc.issued_at<=NOW()
                AND cc.expires_at>NOW() AND cd.is_active=TRUE FOR UPDATE""", (coupon_id, customer_id))
            coupon = cursor.fetchone()
            if coupon is None:
                raise HTTPException(409, "Coupon unavailable")
            discount = coupon_discount(coupon, subtotal)
        if points > subtotal - discount:
            raise HTTPException(409, "Points exceed payable amount")
        if points:
            _expire_customer_points(connection, customer_id)
            cursor.execute("SELECT point_balance FROM point_wallets WHERE customer_id=%s FOR UPDATE", (customer_id,))
            balance = int(cursor.fetchone()["point_balance"])
            cursor.execute("""SELECT point_lot_id,remaining_amount FROM point_lots
                WHERE customer_id=%s AND lot_status='AVAILABLE' AND remaining_amount>0
                AND expires_at>NOW() ORDER BY expires_at,point_lot_id FOR UPDATE""", (customer_id,))
            lots = cursor.fetchall()
            if balance < points or sum(int(lot["remaining_amount"]) for lot in lots) < points:
                raise HTTPException(409, "Insufficient spendable points")
            cursor.execute("""INSERT INTO point_transactions
                (customer_id,transaction_type,point_amount,balance_after,order_id,idempotency_key,description)
                VALUES (%s,'USE',%s,%s,%s,%s,'주문 포인트 사용')""",
                (customer_id, -points, balance-points, order_id, f"checkout-points-{order_id}"))
            transaction_id = cursor.lastrowid
            remaining = points
            for lot in lots:
                used = min(remaining, int(lot["remaining_amount"]))
                if not used:
                    break
                after = int(lot["remaining_amount"])-used
                cursor.execute("INSERT INTO point_usage_details (usage_transaction_id,point_lot_id,used_amount) VALUES (%s,%s,%s)", (transaction_id, lot["point_lot_id"], used))
                cursor.execute("UPDATE point_lots SET remaining_amount=%s,lot_status=%s WHERE point_lot_id=%s", (after, "AVAILABLE" if after else "CONSUMED", lot["point_lot_id"]))
                remaining -= used
            cursor.execute("UPDATE point_wallets SET point_balance=%s WHERE customer_id=%s", (balance-points, customer_id))
        if coupon_id is not None:
            cursor.execute("UPDATE customer_coupons SET coupon_status='USED',used_order_id=%s,used_at=NOW() WHERE customer_coupon_id=%s", (order_id, coupon_id))
        paid = subtotal-discount-points
        cursor.execute("UPDATE orders SET coupon_discount=%s,points_used=%s,paid_total=%s WHERE order_id=%s", (discount, points, paid, order_id))
        return paid
