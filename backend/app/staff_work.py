"""Read models for the employee inventory, procurement and support screens."""

from datetime import date, datetime, time, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from pymysql import MySQLError

from .auth import CurrentEmployee, get_current_employee, require_permission
from .database import mysql_connection
from .staff_orders import _has_head_office_role


router = APIRouter(prefix="/staff", tags=["staff work"])


@router.get("/inventory")
def staff_inventory(
    branch_id: int | None = Query(default=None, alias="branchId"),
    as_of: date | None = Query(default=None, alias="asOf"),
    employee: CurrentEmployee = Depends(get_current_employee),
) -> dict:
    """Show headquarters stock or held stock at an authorized branch."""
    if as_of is not None and as_of > date.today():
        raise HTTPException(status_code=422, detail="Inventory date cannot be in the future")
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                is_hq = _has_head_office_role(cursor, employee.employee_id)
                if branch_id is None:
                    if not is_hq:
                        raise HTTPException(status_code=422, detail="Branch ID is required")
                    if as_of is not None:
                        raise HTTPException(status_code=422, detail="Historical headquarters stock is unavailable")
                    cursor.execute(
                        """SELECT v.product_variant_id,p.product_name,v.product_code,
                                  v.color_name,v.size_mm,h.on_hand_quantity AS quantity,
                                  h.reserved_quantity,h.defective_quantity,
                                  h.available_quantity,ip.initial_stock_quantity AS target_quantity
                           FROM headquarters_inventory h
                           JOIN product_variants v ON v.product_variant_id=h.product_variant_id
                           JOIN products p ON p.product_id=v.product_id
                           LEFT JOIN inventory_policies ip ON ip.product_variant_id=v.product_variant_id
                           ORDER BY p.product_name,v.color_name,v.size_mm"""
                    )
                    rows = cursor.fetchall()
                    return {"scope": "HQ", "asOf": None, "rows": rows}

                if not is_hq:
                    cursor.execute(
                        """SELECT 1 FROM employee_branch_assignments
                           WHERE employee_id=%s AND branch_id=%s AND ended_at IS NULL""",
                        (employee.employee_id, branch_id),
                    )
                    if cursor.fetchone() is None:
                        raise HTTPException(status_code=403, detail="Employee is not assigned to this branch")
                cursor.execute("SELECT branch_id,branch_name FROM branches WHERE branch_id=%s AND is_active=TRUE", (branch_id,))
                branch = cursor.fetchone()
                if branch is None:
                    raise HTTPException(status_code=404, detail="Branch not found")
                cutoff = datetime.combine(as_of + timedelta(days=1), time.min) if as_of else datetime.now()
                cursor.execute(
                    """SELECT v.product_variant_id,p.product_name,v.product_code,
                              v.color_name,v.size_mm,COALESCE(SUM(ph.quantity),0) AS quantity
                       FROM pickup_holdings ph
                       JOIN fulfillment_items fi ON fi.fulfillment_item_id=ph.fulfillment_item_id
                       JOIN order_items oi ON oi.order_item_id=fi.order_item_id
                       JOIN product_variants v ON v.product_variant_id=oi.product_variant_id
                       JOIN products p ON p.product_id=v.product_id
                       WHERE ph.branch_id=%s AND ph.received_at < %s
                         AND (ph.picked_up_at IS NULL OR ph.picked_up_at >= %s)
                         AND (ph.recalled_at IS NULL OR ph.recalled_at >= %s)
                       GROUP BY v.product_variant_id,p.product_name,v.product_code,v.color_name,v.size_mm
                       ORDER BY p.product_name,v.color_name,v.size_mm""",
                    (branch_id, cutoff, cutoff, cutoff),
                )
                rows = cursor.fetchall()
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return {"scope": "BRANCH", "branchId": branch_id, "branchName": branch["branch_name"],
            "asOf": as_of.isoformat() if as_of else None, "rows": rows}


@router.get("/procurement/requisitions")
def staff_requisitions(employee: CurrentEmployee = Depends(get_current_employee)) -> list[dict]:
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                if not _has_head_office_role(cursor, employee.employee_id):
                    raise HTTPException(status_code=403, detail="Head office role required")
                cursor.execute(
                    """SELECT pr.purchase_requisition_id,pr.requested_by_employee_id,
                              pr.branch_id,pr.title,pr.reason,pr.requisition_status,
                              pr.created_at,b.branch_name,e.employee_name
                       FROM purchase_requisitions pr
                       LEFT JOIN branches b ON b.branch_id=pr.branch_id
                       JOIN employees e ON e.employee_id=pr.requested_by_employee_id
                       ORDER BY pr.created_at DESC,pr.purchase_requisition_id DESC LIMIT 100"""
                )
                rows = cursor.fetchall()
                if not rows:
                    return []
                ids = [row["purchase_requisition_id"] for row in rows]
                cursor.execute(
                    """SELECT pri.purchase_requisition_id,pri.product_variant_id,
                              pri.requested_quantity,p.product_name,v.color_name,v.size_mm
                       FROM purchase_requisition_items pri
                       JOIN product_variants v ON v.product_variant_id=pri.product_variant_id
                       JOIN products p ON p.product_id=v.product_id
                       WHERE pri.purchase_requisition_id IN (""" + ",".join(["%s"] * len(ids)) + ")",
                    tuple(ids),
                )
                items = cursor.fetchall()
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    grouped = {identifier: [] for identifier in ids}
    for item in items:
        grouped[item["purchase_requisition_id"]].append({
            "productVariantId": item["product_variant_id"],
            "productName": item["product_name"], "colorName": item["color_name"],
            "sizeMm": item["size_mm"], "quantity": item["requested_quantity"],
        })
    return [{"id": row["purchase_requisition_id"], "requestedByEmployeeId": row["requested_by_employee_id"],
             "branchId": row["branch_id"], "branchName": row["branch_name"], "title": row["title"],
             "reason": row["reason"], "status": row["requisition_status"],
             "createdAt": row["created_at"].isoformat(), "employeeName": row["employee_name"],
             "items": grouped[row["purchase_requisition_id"]]} for row in rows]


@router.get("/inquiries")
def staff_inquiries(_: CurrentEmployee = Depends(require_permission("SUPPORT_MANAGE"))) -> list[dict]:
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
    return [{"id": row["inquiry_id"], "customerId": row["customer_id"],
             "customerName": row["customer_name"], "type": row["inquiry_type"],
             "title": row["title"], "body": row["inquiry_content"],
             "status": row["inquiry_status"], "createdAt": row["created_at"].isoformat(),
             "answer": row["answer"]} for row in rows]


@router.get("/customers")
def staff_customers(_: CurrentEmployee = Depends(require_permission("SUPPORT_MANAGE"))) -> list[dict]:
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
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return [{"id": row["customer_id"], "name": row["customer_name"],
             "email": row["email"], "phone": row["phone"],
             "orderCount": row["order_count"], "paidTotal": row["paid_total"],
             "lastOrderedAt": row["last_ordered_at"].isoformat() if row["last_ordered_at"] else None,
             "pointBalance": row["point_balance"]} for row in rows]


@router.get("/customers/{customer_id}")
def staff_customer_detail(customer_id: int, _: CurrentEmployee = Depends(require_permission("SUPPORT_MANAGE"))) -> dict:
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
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return {"id": customer["customer_id"], "name": customer["customer_name"],
            "email": customer["email"], "phone": customer["phone"],
            "orders": [{"id": row["order_id"], "number": row["order_number"],
                        "status": row["order_status"], "paidTotal": row["paid_total"],
                        "orderedAt": row["ordered_at"].isoformat(), "branchName": row["branch_name"]}
                       for row in orders],
            "returns": [{"id": row["return_request_id"], "orderId": row["order_id"],
                         "status": row["request_status"], "reason": row["return_reason"]}
                        for row in returns]}


@router.get("/returns")
def staff_returns(
    branch_id: int | None = Query(default=None, alias="branchId"),
    employee: CurrentEmployee = Depends(get_current_employee),
) -> list[dict]:
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                is_hq = _has_head_office_role(cursor, employee.employee_id)
                cursor.execute(
                    """SELECT rr.return_request_id,rr.order_id,rr.request_status,
                              rr.return_reason,rr.requested_at,o.order_number,
                              c.customer_name,b.branch_name
                       FROM return_requests rr
                       JOIN orders o ON o.order_id=rr.order_id
                       JOIN customers c ON c.customer_id=rr.customer_id
                       JOIN branches b ON b.branch_id=rr.branch_id
                       WHERE (%s IS NULL OR rr.branch_id=%s)
                         AND (%s=1 OR EXISTS (
                           SELECT 1 FROM employee_branch_assignments eba
                           WHERE eba.employee_id=%s AND eba.branch_id=rr.branch_id
                             AND eba.ended_at IS NULL))
                       ORDER BY rr.requested_at DESC,rr.return_request_id DESC LIMIT 100""",
                    (branch_id, branch_id, int(is_hq), employee.employee_id),
                )
                rows = cursor.fetchall()
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return [{"id": row["return_request_id"], "orderId": row["order_id"],
             "orderNumber": row["order_number"], "status": row["request_status"],
             "reason": row["return_reason"], "customerName": row["customer_name"],
             "branchName": row["branch_name"], "requestedAt": row["requested_at"].isoformat()}
            for row in rows]


@router.get("/analytics")
def staff_analytics(
    days: int = Query(default=28, ge=1, le=365),
    branch_id: int | None = Query(default=None, alias="branchId"),
    product_id: int | None = Query(default=None, alias="productId"),
    employee: CurrentEmployee = Depends(get_current_employee),
) -> dict:
    """Report paid orders and item quantities from existing order snapshots."""
    since = datetime.combine(date.today() - timedelta(days=days - 1), time.min)
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                if not _has_head_office_role(cursor, employee.employee_id):
                    raise HTTPException(status_code=403, detail="Head office role required")
                cursor.execute("SELECT product_id,product_name FROM products WHERE is_active=TRUE ORDER BY product_name")
                products = cursor.fetchall()
                cursor.execute("SELECT branch_id,branch_name FROM branches WHERE is_active=TRUE ORDER BY branch_name")
                branches = cursor.fetchall()
                predicate = """o.order_status IN ('PAID','PREPARING','IN_TRANSIT','READY_FOR_PICKUP','COMPLETED')
                    AND o.ordered_at >= %s AND (%s IS NULL OR o.pickup_branch_id=%s)
                    AND (%s IS NULL OR EXISTS (
                        SELECT 1 FROM order_items x JOIN product_variants xv
                          ON xv.product_variant_id=x.product_variant_id
                        WHERE x.order_id=o.order_id AND xv.product_id=%s))"""
                args = (since, branch_id, branch_id, product_id, product_id)
                cursor.execute(
                    f"SELECT COUNT(*) AS order_count,COALESCE(SUM(o.paid_total),0) AS revenue FROM orders o WHERE {predicate}",
                    args,
                )
                summary = cursor.fetchone()
                cursor.execute(
                    f"""SELECT DATE(o.ordered_at) AS day,COALESCE(SUM(oi.quantity),0) AS quantity
                        FROM orders o JOIN order_items oi ON oi.order_id=o.order_id
                        JOIN product_variants v ON v.product_variant_id=oi.product_variant_id
                        WHERE {predicate} AND (%s IS NULL OR v.product_id=%s)
                        GROUP BY DATE(o.ordered_at) ORDER BY day""",
                    (*args, product_id, product_id),
                )
                by_day = cursor.fetchall()
                cursor.execute(
                    f"""SELECT p.product_id,p.product_name,COALESCE(SUM(oi.quantity),0) AS quantity
                        FROM orders o JOIN order_items oi ON oi.order_id=o.order_id
                        JOIN product_variants v ON v.product_variant_id=oi.product_variant_id
                        JOIN products p ON p.product_id=v.product_id
                        WHERE {predicate} AND (%s IS NULL OR p.product_id=%s)
                        GROUP BY p.product_id,p.product_name ORDER BY quantity DESC""",
                    (*args, product_id, product_id),
                )
                by_product = cursor.fetchall()
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
    return {"days": days, "orderCount": int(summary["order_count"]), "revenue": int(summary["revenue"]),
            "quantity": sum(int(row["quantity"]) for row in by_day),
            "byDay": [{"day": row["day"].isoformat(), "quantity": int(row["quantity"])} for row in by_day],
            "byProduct": [{"productId": row["product_id"], "productName": row["product_name"],
                           "quantity": int(row["quantity"])} for row in by_product],
            "products": [{"id": row["product_id"], "name": row["product_name"]} for row in products],
            "branches": [{"id": row["branch_id"], "name": row["branch_name"]} for row in branches]}
