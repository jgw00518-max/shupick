from app.schemas import RefundCreateRequest, RefundItemRequest
from app.refunds import validate_refund_items


def test_point_only_return_accepts_zero_cash():
    item=RefundItemRequest(orderItemId=1,quantity=1,refundAmount=0)
    request=RefundCreateRequest(paymentId=1,returnRequestId=1,refundType='RETURN',refundAmount=0,idempotencyKey='zero-return',items=[item])
    validate_refund_items(request.refundType,request.refundAmount,request.items)
