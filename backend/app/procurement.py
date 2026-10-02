"""Role-protected procurement requisition and ordered approval workflow."""

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pymysql import MySQLError
from pymysql.connections import Connection

from .audit import write_employee_audit
from .auth import CurrentEmployee, get_current_employee, require_permission
from .database import mysql_connection
from .schemas import (
    ProcurementApprovalDecisionRequest,
    ProcurementApprovalResponse,
    ProcurementRequisitionCreateRequest,
    ProcurementRequisitionResponse,
)


router = APIRouter(prefix="/procurement", tags=["procurement"])
audit_router = APIRouter(prefix="/internal/audit-logs", tags=["internal"])


def validate_procurement_items(items: list[Any]) -> None:
    variant_ids = [item.productVariantId for item in items]
    if len(variant_ids) != len(set(variant_ids)):
        raise ValueError("Duplicate product variants are not allowed")


def _request_metadata(request: Request) -> tuple[str | None, str | None]:
    request_id = request.headers.get("X-Request-Id")
    ip_address = None if request.client is None else request.client.host
    return request_id, ip_address


def _requisition_response(connection: Connection, requisition_id: int) -> ProcurementRequisitionResponse:
    with connection.cursor() as cursor:
        cursor.execute("SELECT * FROM purchase_requisitions WHERE purchase_requisition_id=%s", (requisition_id,))
        requisition = cursor.fetchone()
        if requisition is None:
            raise HTTPException(status_code=404, detail="Purchase requisition not found")
        cursor.execute(
            """
            SELECT pa.approval_sequence,r.role_code,pa.approval_status,
                   pa.approver_employee_id,pa.approval_comment,pa.decided_at
            FROM purchase_approvals pa
            JOIN roles r ON r.role_id=pa.required_role_id
            WHERE pa.purchase_requisition_id=%s
            ORDER BY pa.approval_sequence
            """,
            (requisition_id,),
        )
        approvals = cursor.fetchall()
    return ProcurementRequisitionResponse(
        purchaseRequisitionId=requisition_id,
        status=str(requisition["requisition_status"]),
        requestedByEmployeeId=int(requisition["requested_by_employee_id"]),
        title=str(requisition["title"]),
        approvals=[
            ProcurementApprovalResponse(
                sequence=int(row["approval_sequence"]),
                requiredRole=str(row["role_code"]),
                status=str(row["approval_status"]),
                approverEmployeeId=row["approver_employee_id"],
                comment=row["approval_comment"],
                decidedAt=row["decided_at"],
            )
            for row in approvals
        ],
    )


@router.post("/requisitions", response_model=ProcurementRequisitionResponse, status_code=status.HTTP_201_CREATED)
def create_requisition(
    body: ProcurementRequisitionCreateRequest,
    request: Request,
    current: CurrentEmployee = Depends(require_permission("PROCUREMENT_REQUISITION_CREATE")),
) -> ProcurementRequisitionResponse:
    """Create a draft requisition for the authenticated employee."""

    try:
        validate_procurement_items(body.items)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT branch_id FROM branches WHERE branch_id=%s", (body.branchId,))
                    if cursor.fetchone() is None:
                        raise HTTPException(status_code=404, detail="Branch not found")
                    variant_ids = [item.productVariantId for item in body.items]
                    placeholders = ",".join(["%s"] * len(variant_ids))
                    cursor.execute(
                        f"SELECT product_variant_id FROM product_variants WHERE product_variant_id IN ({placeholders})",
                        variant_ids,
                    )
                    if len(cursor.fetchall()) != len(variant_ids):
                        raise HTTPException(status_code=409, detail="One or more product variants do not exist")
                    cursor.execute(
                        """
                        SELECT approval_workflow_id FROM approval_workflows
                        WHERE workflow_code='PROCUREMENT_STANDARD' AND is_active=TRUE
                        """
                    )
                    workflow = cursor.fetchone()
                    if workflow is None:
                        raise HTTPException(status_code=503, detail="Procurement approval workflow is unavailable")
                    cursor.execute(
                        """
                        INSERT INTO purchase_requisitions
                          (requested_by_employee_id,branch_id,approval_workflow_id,title,reason,requisition_status)
                        VALUES (%s,%s,%s,%s,%s,'DRAFT')
                        """,
                        (current.employee_id, body.branchId, workflow["approval_workflow_id"], body.title, body.reason),
                    )
                    requisition_id = cursor.lastrowid
                    for item in body.items:
                        cursor.execute(
                            """
                            INSERT INTO purchase_requisition_items
                              (purchase_requisition_id,product_variant_id,requested_quantity)
                            VALUES (%s,%s,%s)
                            """,
                            (requisition_id, item.productVariantId, item.requestedQuantity),
                        )
                    request_id, ip_address = _request_metadata(request)
                    write_employee_audit(
                        connection,
                        employee_id=current.employee_id,
                        action_code="PROCUREMENT_REQUISITION_CREATED",
                        entity_type="PURCHASE_REQUISITION",
                        entity_id=requisition_id,
                        before_data=None,
                        after_data={"status": "DRAFT", "title": body.title},
                        request_id=request_id,
                        ip_address=ip_address,
                    )
                connection.commit()
                return _requisition_response(connection, requisition_id)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error


@router.post("/requisitions/{requisition_id}/submit", response_model=ProcurementRequisitionResponse)
def submit_requisition(
    requisition_id: int,
    request: Request,
    current: CurrentEmployee = Depends(require_permission("PROCUREMENT_REQUISITION_SUBMIT")),
) -> ProcurementRequisitionResponse:
    """Create ordered approval instances and send a draft to the team lead."""

    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute(
                        "SELECT * FROM purchase_requisitions WHERE purchase_requisition_id=%s FOR UPDATE",
                        (requisition_id,),
                    )
                    requisition = cursor.fetchone()
                    if requisition is None:
                        raise HTTPException(status_code=404, detail="Purchase requisition not found")
                    if int(requisition["requested_by_employee_id"]) != current.employee_id:
                        raise HTTPException(status_code=403, detail="Only the requester can submit this requisition")
                    if requisition["requisition_status"] != "DRAFT":
                        raise HTTPException(status_code=409, detail="Only a draft requisition can be submitted")
                    cursor.execute(
                        """
                        INSERT INTO purchase_approvals
                          (purchase_requisition_id,approval_sequence,required_role_id,approval_status)
                        SELECT %s,step_order,required_role_id,'PENDING'
                        FROM approval_workflow_steps
                        WHERE approval_workflow_id=%s
                        ORDER BY step_order
                        """,
                        (requisition_id, requisition["approval_workflow_id"]),
                    )
                    cursor.execute(
                        """
                        UPDATE purchase_requisitions
                        SET requisition_status='PENDING_TEAM_LEAD',submitted_at=NOW()
                        WHERE purchase_requisition_id=%s
                        """,
                        (requisition_id,),
                    )
                    request_id, ip_address = _request_metadata(request)
                    write_employee_audit(
                        connection,
                        employee_id=current.employee_id,
                        action_code="PROCUREMENT_REQUISITION_SUBMITTED",
                        entity_type="PURCHASE_REQUISITION",
                        entity_id=requisition_id,
                        before_data={"status": "DRAFT"},
                        after_data={"status": "PENDING_TEAM_LEAD"},
                        request_id=request_id,
                        ip_address=ip_address,
                    )
                connection.commit()
                return _requisition_response(connection, requisition_id)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error


@router.post("/requisitions/{requisition_id}/decision", response_model=ProcurementRequisitionResponse)
def decide_requisition(
    requisition_id: int,
    body: ProcurementApprovalDecisionRequest,
    request: Request,
    current: CurrentEmployee = Depends(get_current_employee),
) -> ProcurementRequisitionResponse:
    """Allow only the role required by the current approval step to decide."""

    try:
        with mysql_connection() as connection:
            try:
                with connection.cursor() as cursor:
                    cursor.execute(
                        "SELECT * FROM purchase_requisitions WHERE purchase_requisition_id=%s FOR UPDATE",
                        (requisition_id,),
                    )
                    requisition = cursor.fetchone()
                    if requisition is None:
                        raise HTTPException(status_code=404, detail="Purchase requisition not found")
                    if int(requisition["requested_by_employee_id"]) == current.employee_id:
                        raise HTTPException(status_code=409, detail="Requester cannot approve their own requisition")
                    cursor.execute(
                        """
                        SELECT pa.*,r.role_code
                        FROM purchase_approvals pa
                        JOIN roles r ON r.role_id=pa.required_role_id
                        WHERE pa.purchase_requisition_id=%s AND pa.approval_status='PENDING'
                        ORDER BY pa.approval_sequence
                        LIMIT 1 FOR UPDATE
                        """,
                        (requisition_id,),
                    )
                    approval = cursor.fetchone()
                    if approval is None:
                        raise HTTPException(status_code=409, detail="No pending approval step")
                    cursor.execute(
                        "SELECT 1 FROM employee_roles WHERE employee_id=%s AND role_id=%s",
                        (current.employee_id, approval["required_role_id"]),
                    )
                    if cursor.fetchone() is None:
                        raise HTTPException(status_code=403, detail=f"Current step requires role: {approval['role_code']}")
                    permission_code = (
                        "PROCUREMENT_APPROVE_TEAM_LEAD"
                        if approval["role_code"] == "TEAM_LEAD"
                        else "PROCUREMENT_APPROVE_DIRECTOR"
                    )
                    cursor.execute(
                        """
                        SELECT 1 FROM role_permissions rp
                        JOIN permissions p ON p.permission_id=rp.permission_id
                        WHERE rp.role_id=%s AND p.permission_code=%s
                        """,
                        (approval["required_role_id"], permission_code),
                    )
                    if cursor.fetchone() is None:
                        raise HTTPException(status_code=403, detail=f"Missing permission: {permission_code}")
                    cursor.execute(
                        """
                        UPDATE purchase_approvals
                        SET approver_employee_id=%s,approval_status=%s,approval_comment=%s,decided_at=NOW()
                        WHERE purchase_approval_id=%s
                        """,
                        (current.employee_id, body.decision, body.comment, approval["purchase_approval_id"]),
                    )
                    if body.decision == "REJECTED":
                        next_status = "REJECTED"
                    else:
                        cursor.execute(
                            """
                            SELECT r.role_code FROM purchase_approvals pa
                            JOIN roles r ON r.role_id=pa.required_role_id
                            WHERE pa.purchase_requisition_id=%s AND pa.approval_status='PENDING'
                            ORDER BY pa.approval_sequence LIMIT 1
                            """,
                            (requisition_id,),
                        )
                        next_step = cursor.fetchone()
                        if next_step is None:
                            next_status = "APPROVED"
                        elif next_step["role_code"] == "DIRECTOR":
                            next_status = "PENDING_DIRECTOR"
                        else:
                            next_status = "PENDING_TEAM_LEAD"
                    cursor.execute(
                        "UPDATE purchase_requisitions SET requisition_status=%s WHERE purchase_requisition_id=%s",
                        (next_status, requisition_id),
                    )
                    request_id, ip_address = _request_metadata(request)
                    write_employee_audit(
                        connection,
                        employee_id=current.employee_id,
                        action_code=f"PROCUREMENT_{body.decision}",
                        entity_type="PURCHASE_REQUISITION",
                        entity_id=requisition_id,
                        before_data={
                            "status": requisition["requisition_status"],
                            "approvalSequence": approval["approval_sequence"],
                        },
                        after_data={"status": next_status, "decision": body.decision},
                        request_id=request_id,
                        ip_address=ip_address,
                    )
                connection.commit()
                return _requisition_response(connection, requisition_id)
            except Exception:
                connection.rollback()
                raise
    except HTTPException:
        raise
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error


@audit_router.get("")
def list_audit_logs(
    entity_type: str | None = Query(default=None, alias="entityType"),
    entity_id: int | None = Query(default=None, alias="entityId"),
    limit: int = Query(default=100, ge=1, le=500),
    _: CurrentEmployee = Depends(require_permission("AUDIT_LOG_READ")),
) -> list[dict[str, Any]]:
    """Return recent audit entries to authorized employees."""

    clauses: list[str] = []
    values: list[Any] = []
    if entity_type is not None:
        clauses.append("entity_type=%s")
        values.append(entity_type)
    if entity_id is not None:
        clauses.append("entity_id=%s")
        values.append(entity_id)
    where = "" if not clauses else "WHERE " + " AND ".join(clauses)
    try:
        with mysql_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    f"SELECT * FROM audit_logs {where} ORDER BY audit_log_id DESC LIMIT %s",
                    (*values, limit),
                )
                return list(cursor.fetchall())
    except MySQLError as error:
        raise HTTPException(status_code=503, detail="Database unavailable") from error
