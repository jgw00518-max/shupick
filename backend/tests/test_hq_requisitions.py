from contextlib import contextmanager
from datetime import datetime
from unittest.mock import MagicMock

from starlette.requests import Request

from app import procurement, staff_work
from app.auth import CurrentEmployee
from app.schemas import ProcurementRequisitionCreateRequest, ProcurementRequisitionResponse

EMPLOYEE = CurrentEmployee(7, 'uid', 'EMP-7', '본사 직원')


def test_headquarters_requisition_needs_no_branch_and_stores_null(monkeypatch):
    cursor = MagicMock(); cursor.__enter__.return_value = cursor
    cursor.lastrowid = 70
    cursor.fetchall.return_value = [{'product_variant_id': 5}]
    cursor.fetchone.return_value = {'approval_workflow_id': 1}
    connection = MagicMock(); connection.cursor.return_value = cursor
    @contextmanager
    def database(): yield connection
    monkeypatch.setattr(procurement, 'mysql_connection', database)
    monkeypatch.setattr(procurement, 'write_employee_audit', MagicMock())
    monkeypatch.setattr(procurement, '_requisition_response', lambda _, identifier:
        ProcurementRequisitionResponse(purchaseRequisitionId=identifier,status='DRAFT',requestedByEmployeeId=7,title='재고 보충',approvals=[]))
    body = ProcurementRequisitionCreateRequest(title='재고 보충',reason='본사 재고 부족',items=[{'productVariantId':5,'requestedQuantity':10}])
    response = procurement.create_requisition(body, Request({'type':'http','headers':[],'client':('127.0.0.1',1)}), EMPLOYEE)
    assert response.purchaseRequisitionId == 70
    insert = [call for call in cursor.execute.call_args_list if 'INSERT INTO purchase_requisitions' in call.args[0]][0]
    assert insert.args[1][:2] == (7, None)
    assert not any('FROM branches' in call.args[0] for call in cursor.execute.call_args_list)
    connection.commit.assert_called_once()


def test_requisition_list_keeps_branchless_requests(monkeypatch):
    cursor = MagicMock(); cursor.__enter__.return_value = cursor
    cursor.fetchone.return_value = {'hq':1}
    cursor.fetchall.side_effect = [[{'purchase_requisition_id':70,'requested_by_employee_id':7,'branch_id':None,
        'branch_name':None,'title':'再庫','reason':'본사 재고 부족','requisition_status':'PENDING_TEAM_LEAD',
        'created_at':datetime(2026,10,6),'employee_name':'본사 직원'}],
        [{'purchase_requisition_id':70,'product_variant_id':5,'requested_quantity':10,'product_name':'운동화','color_name':'BLACK','size_mm':260}]]
    connection = MagicMock(); connection.cursor.return_value = cursor
    @contextmanager
    def database(): yield connection
    monkeypatch.setattr(staff_work, 'mysql_connection', database)
    response = staff_work.staff_requisitions(EMPLOYEE)
    assert len(response) == 1 and response[0]['branchId'] is None
    assert response[0]['items'][0]['quantity'] == 10
    assert any('LEFT JOIN branches' in call.args[0] for call in cursor.execute.call_args_list)
