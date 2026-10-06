"""Permission-checked customer-support reads for the staff/PAD app.

Uses the existing 001-017 schema. No demo migrations, account registration,
or client-selected roles are required for this support workflow.
"""

from fastapi import APIRouter, Depends, HTTPException
from pymysql import MySQLError

from .auth import CurrentEmployee, require_permission
from .database import mysql_connection


router = APIRouter(prefix="/staff", tags=["staff support"])


@router.get("/inquiries")
def staff_inquiries(
    _: CurrentEmployee = Depends(require_permission("SUPPORT_MANAGE")),
) -> list[dict]:
    """Return the latest 100 inquiries with the same latest-answer rule as customers."""
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """SELECT i.inquiry_id,i.customer_id,c.customer_name,i.inquiry_type,
                              i.title,i.inquiry_content,i.inquiry_status,i.created_at,
                              (SELECT response_content FROM inquiry_responses ir
                               WHERE ir.inquiry_id=i.inquiry_id
                               ORDER BY ir.responded_at DESC,ir.inquiry_response_id DESC LIMIT 1) AS answer
                       FROM inquiries i JOIN customers c ON c.customer_id=i.customer_id
                       ORDER BY i.created_at DESC,i.inquiry_id DESC LIMIT 100"""
                )
                rows = cursor.fetchall()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return [
        {
            "id": row["inquiry_id"],
            "customerId": row["customer_id"],
            "customerName": row["customer_name"],
            "type": row["inquiry_type"],
            "title": row["title"],
            "body": row["inquiry_content"],
            "status": row["inquiry_status"],
            "createdAt": row["created_at"].isoformat(),
            "answer": row["answer"],
        }
        for row in rows
    ]


@router.get("/customers")
def staff_customers(
    _: CurrentEmployee = Depends(require_permission("SUPPORT_MANAGE")),
) -> list[dict]:
    """Return a bounded customer summary; employee permission is checked server-side."""
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """SELECT c.customer_id,c.customer_name,c.email,c.phone,
                              COUNT(o.order_id) AS order_count,
                              COALESCE(SUM(o.paid_total),0) AS paid_total,
                              MAX(o.ordered_at) AS last_ordered_at,
                              COALESCE(pw.point_balance,0) AS point_balance
                       FROM customers c
                       LEFT JOIN orders o ON o.customer_id=c.customer_id
                       LEFT JOIN point_wallets pw ON pw.customer_id=c.customer_id
                       WHERE c.deleted_at IS NULL
                       GROUP BY c.customer_id,c.customer_name,c.email,c.phone,pw.point_balance
                       ORDER BY c.customer_id DESC LIMIT 200"""
                )
                rows = cursor.fetchall()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return [
        {
            "id": row["customer_id"],
            "name": row["customer_name"],
            "email": row["email"],
            "phone": row["phone"],
            "orderCount": row["order_count"],
            "paidTotal": row["paid_total"],
            "lastOrderedAt": row["last_ordered_at"].isoformat() if row["last_ordered_at"] else None,
            "pointBalance": row["point_balance"],
        }
        for row in rows
    ]


@router.get("/customers/{customer_id}")
def staff_customer_detail(
    customer_id: int,
    _: CurrentEmployee = Depends(require_permission("SUPPORT_MANAGE")),
) -> dict:
    """Read one customer's support history without changing orders or memberships."""
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT customer_id,customer_name,email,phone FROM customers WHERE customer_id=%s AND deleted_at IS NULL",
                    (customer_id,),
                )
                customer = cursor.fetchone()
                if customer is None:
                    raise HTTPException(status_code=404, detail="Customer not found")
                cursor.execute(
                    """SELECT o.order_id,o.order_number,o.order_status,o.paid_total,
                              o.ordered_at,b.branch_name
                       FROM orders o LEFT JOIN branches b ON b.branch_id=o.pickup_branch_id
                       WHERE o.customer_id=%s ORDER BY o.ordered_at DESC,o.order_id DESC LIMIT 50""",
                    (customer_id,),
                )
                orders = cursor.fetchall()
                cursor.execute(
                    """SELECT rr.return_request_id,rr.order_id,rr.request_status,rr.return_reason
                       FROM return_requests rr WHERE rr.customer_id=%s
                       ORDER BY rr.requested_at DESC,rr.return_request_id DESC LIMIT 50""",
                    (customer_id,),
                )
                returns = cursor.fetchall()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return {
        "id": customer["customer_id"],
        "name": customer["customer_name"],
        "email": customer["email"],
        "phone": customer["phone"],
        "orders": [
            {
                "id": row["order_id"],
                "number": row["order_number"],
                "status": row["order_status"],
                "paidTotal": row["paid_total"],
                "orderedAt": row["ordered_at"].isoformat(),
                "branchName": row["branch_name"],
            }
            for row in orders
        ],
        "returns": [
            {
                "id": row["return_request_id"],
                "orderId": row["order_id"],
                "status": row["request_status"],
                "reason": row["return_reason"],
            }
            for row in returns
        ],
    }
