"""Authenticated order history using the immutable purchase snapshots."""

from fastapi import APIRouter, Depends, HTTPException
from pymysql import MySQLError

from .auth import CurrentCustomer, get_current_customer
from .branches import DISTRICT_NAMES
from .database import mysql_connection

router = APIRouter(prefix="/orders", tags=["orders"])


def read_orders(customer_id: int, order_id: int | None = None) -> list[dict]:
    """Apply ownership in SQL for both list and detail requests."""
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """SELECT o.*, b.district_code
                    FROM orders o LEFT JOIN branches b
                    ON b.branch_id=o.pickup_branch_id
                    WHERE o.customer_id=%s"""
                    + (" AND o.order_id=%s" if order_id is not None else "")
                    + " ORDER BY o.ordered_at DESC,o.order_id DESC",
                    (customer_id, order_id) if order_id is not None else (customer_id,),
                )
                orders = cursor.fetchall()
                if not orders:
                    return []
                ids = [row["order_id"] for row in orders]
                cursor.execute(
                    """SELECT oi.*,v.product_id,
                    (SELECT image_url FROM product_images im
                     WHERE im.product_id=v.product_id
                     ORDER BY im.is_primary DESC,im.sort_order,im.product_image_id LIMIT 1) AS image_url
                    FROM order_items oi JOIN product_variants v
                    ON v.product_variant_id=oi.product_variant_id
                    WHERE oi.order_id IN (""" + ",".join(["%s"] * len(ids))
                    + ") ORDER BY oi.order_item_id", tuple(ids),
                )
                items = cursor.fetchall()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    grouped = {identifier: [] for identifier in ids}
    for item in items:
        grouped[item["order_id"]].append({
            "orderItemId": item["order_item_id"],
            "productId": item["product_id"], "name": item["product_name"],
            "color": item["color_name"], "size": str(item["size_mm"]),
            "unitPrice": item["unit_price"], "quantity": item["quantity"],
            "imageUrl": item["image_url"] or "",
        })
    return [{
        "orderId": row["order_id"], "orderNumber": row["order_number"],
        "orderStatus": row["order_status"], "orderedAt": row["ordered_at"].isoformat(),
        "district": DISTRICT_NAMES.get(row["district_code"], row["district_code"] or ""),
        "paidTotal": row["paid_total"], "couponDiscount": row["coupon_discount"],
        "pointsUsed": row["points_used"], "items": grouped[row["order_id"]],
        "purchaseConfirmed":row['purchase_confirmed_at'] is not None,
    } for row in orders]


@router.get("")
def list_orders(customer: CurrentCustomer = Depends(get_current_customer)) -> list[dict]:
    return read_orders(customer.customer_id)


@router.get("/{order_id}")
def order_detail(order_id: int, customer: CurrentCustomer = Depends(get_current_customer)) -> dict:
    rows = read_orders(customer.customer_id, order_id)
    if not rows:
        raise HTTPException(status_code=404, detail="Order not found")
    return rows[0]
