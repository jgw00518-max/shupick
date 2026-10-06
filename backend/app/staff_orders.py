"""Employee order lookup and branch-scoped pickup code verification."""

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from pymysql import MySQLError

from .auth import CurrentEmployee, get_current_employee
from .database import mysql_connection


router = APIRouter(prefix="/staff", tags=["staff orders"])


class PickupCodeRequest(BaseModel):
    paymentCode: str = Field(min_length=1, max_length=32)


def _has_head_office_role(cursor, employee_id: int) -> bool:
    cursor.execute(
        """SELECT 1 FROM employee_roles er JOIN roles r ON r.role_id=er.role_id
           WHERE er.employee_id=%s AND r.is_active=TRUE
             AND r.role_code IN ('HQ_STAFF','TEAM_LEAD','DIRECTOR','EXECUTIVE','ADMIN')
           LIMIT 1""",
        (employee_id,),
    )
    return cursor.fetchone() is not None


@router.get("/orders")
def list_staff_orders(
    employee: CurrentEmployee = Depends(get_current_employee),
    branch_id: int | None = Query(default=None, alias="branchId"),
) -> list[dict]:
    """Show recent orders in the employee's branch, or all orders for HQ."""
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                is_hq = _has_head_office_role(cursor, employee.employee_id)
                if branch_id is not None and not is_hq:
                    cursor.execute(
                        """SELECT 1 FROM employee_branch_assignments
                           WHERE employee_id=%s AND branch_id=%s AND ended_at IS NULL""",
                        (employee.employee_id, branch_id),
                    )
                    if cursor.fetchone() is None:
                        raise HTTPException(status_code=403, detail="Employee is not assigned to this branch")
                cursor.execute(
                    """SELECT o.order_id,o.order_number,o.order_status,o.ordered_at,
                              o.pickup_branch_id,c.customer_name,b.branch_name,
                              f.fulfillment_id,f.fulfillment_status
                       FROM orders o
                       JOIN customers c ON c.customer_id=o.customer_id
                       JOIN branches b ON b.branch_id=o.pickup_branch_id
                       LEFT JOIN fulfillments f ON f.fulfillment_id=(
                           SELECT MAX(f2.fulfillment_id) FROM fulfillments f2
                           WHERE f2.order_id=o.order_id)
                       WHERE (%s=1 OR EXISTS (
                           SELECT 1 FROM employee_branch_assignments eba
                           WHERE eba.employee_id=%s AND eba.branch_id=o.pickup_branch_id
                             AND eba.ended_at IS NULL))
                         AND (%s IS NULL OR o.pickup_branch_id=%s)
                       ORDER BY o.ordered_at DESC,o.order_id DESC LIMIT 100""",
                    (int(is_hq), employee.employee_id, branch_id, branch_id),
                )
                orders = cursor.fetchall()
                if not orders:
                    return []
                ids = [row["order_id"] for row in orders]
                cursor.execute(
                    "SELECT order_id,product_name,color_name,size_mm,quantity FROM order_items "
                    "WHERE order_id IN (" + ",".join(["%s"] * len(ids)) + ") ORDER BY order_item_id",
                    tuple(ids),
                )
                items = cursor.fetchall()
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    grouped = {order_id: [] for order_id in ids}
    for item in items:
        grouped[item["order_id"]].append(
            f'{item["product_name"]} · {item["color_name"]} / {item["size_mm"]} × {item["quantity"]}'
        )
    return [
        {
            "orderId": row["order_id"], "orderNumber": row["order_number"],
            "orderStatus": row["order_status"], "orderedAt": row["ordered_at"].isoformat(),
            "customerName": row["customer_name"], "branchName": row["branch_name"],
            "branchId": row["pickup_branch_id"], "fulfillmentId": row["fulfillment_id"],
            "fulfillmentStatus": row["fulfillment_status"],
            "products": grouped[row["order_id"]],
        }
        for row in orders
    ]


@router.post("/pickups/verify")
def verify_pickup_code(
    request: PickupCodeRequest,
    employee: CurrentEmployee = Depends(get_current_employee),
) -> dict:
    """Find only a ready pickup at one of the employee's current branches."""
    code = request.paymentCode.strip().upper()
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """SELECT o.order_id,o.order_number,o.order_status,o.pickup_branch_id,
                              c.customer_name,b.branch_name
                       FROM orders o
                       JOIN customers c ON c.customer_id=o.customer_id
                       JOIN branches b ON b.branch_id=o.pickup_branch_id
                       JOIN employee_branch_assignments eba
                         ON eba.branch_id=o.pickup_branch_id AND eba.ended_at IS NULL
                       WHERE o.order_number=%s AND eba.employee_id=%s
                       LIMIT 1""",
                    (code, employee.employee_id),
                )
                order = cursor.fetchone()
                if order is None:
                    raise HTTPException(status_code=404, detail="Pickup code not found for this branch")
                if order["order_status"] != "READY_FOR_PICKUP":
                    raise HTTPException(status_code=409, detail="Order is not ready for pickup")
                cursor.execute(
                    "SELECT product_name,color_name,size_mm,quantity FROM order_items WHERE order_id=%s ORDER BY order_item_id",
                    (order["order_id"],),
                )
                items = cursor.fetchall()
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return {
        "orderId": order["order_id"], "orderNumber": order["order_number"],
        "orderStatus": order["order_status"], "customerName": order["customer_name"],
        "branchName": order["branch_name"], "branchId": order["pickup_branch_id"],
        "products": [
            f'{item["product_name"]} · {item["color_name"]} / {item["size_mm"]} × {item["quantity"]}'
            for item in items
        ],
    }
