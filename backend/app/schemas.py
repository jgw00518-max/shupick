"""Public API request and response models."""

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class ProductResponse(BaseModel):
    """Product fields currently consumed by the Flutter catalog."""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    name: str
    category: str
    price: int
    imageUrl: str
    color: str
    gender: str
    middleCategory: str
    subcategory: str
    images: dict[str, str]
    reviewCount: int
    salesCount: int


class ProductOptionResponse(BaseModel):
    """Available stock for one product color and size combination."""

    productVariantId: int
    productCode: str
    color: str
    size: str
    availableQuantity: int
    inventoryStatus: str


class ProductRecommendationsResponse(BaseModel):
    """Ranked products with aggregate-view recommendations identified separately."""

    products: list[ProductResponse]
    coViewedProductIds: list[int] = Field(default_factory=list)


class PickupBranchResponse(BaseModel):
    """Active branch available for customer pickup."""

    branchId: int
    branchCode: str
    branchName: str
    districtCode: str
    districtName: str
    address: str
    phone: str
    businessHours: list[dict] = Field(default_factory=list)


class EmployeeRoleResponse(BaseModel):
    """An active business role assigned to the authenticated employee."""

    roleCode: str
    roleName: str


class EmployeeBranchResponse(BaseModel):
    """An active branch with a current employee assignment."""

    branchId: int
    branchCode: str
    branchName: str
    districtCode: str


class EmployeeProfileResponse(BaseModel):
    """Staff-app session resolved from verified Firebase identity, never client roles."""

    employeeId: int
    employeeCode: str
    employeeName: str
    roles: list[EmployeeRoleResponse]
    branches: list[EmployeeBranchResponse]


class RefundItemRequest(BaseModel):
    """One order line and quantity included in a return refund."""

    orderItemId: int = Field(gt=0)
    quantity: int = Field(gt=0)
    refundAmount: int = Field(ge=0)


class RefundCreateRequest(BaseModel):
    """Internal request to reserve a refundable amount safely."""

    paymentId: int = Field(gt=0)
    returnRequestId: int | None = Field(default=None, gt=0)
    refundType: Literal["ORDER_CANCEL", "RETURN", "MANUAL_ADJUSTMENT"]
    refundAmount: int = Field(ge=0)
    idempotencyKey: str = Field(min_length=1, max_length=100)
    items: list[RefundItemRequest] = Field(default_factory=list)


class RefundCompleteRequest(BaseModel):
    """Successful payment-provider result for a reserved refund."""

    providerRefundKey: str = Field(min_length=1, max_length=100)


class RefundResponse(BaseModel):
    """Refund ledger state returned to callers."""

    refundId: int
    refundNumber: str
    paymentId: int
    orderId: int
    refundType: str
    refundStatus: str
    refundAmount: int
    retryCount: int
    restoredCouponCount: int = 0


class OrderItemCreateRequest(BaseModel):
    """Requested SKU and quantity for checkout stock reservation."""

    productVariantId: int = Field(gt=0)
    quantity: int = Field(gt=0)


class OrderReserveRequest(BaseModel):
    """Pickup order request that reserves headquarters stock."""

    pickupBranchId: int = Field(gt=0)
    idempotencyKey: str = Field(min_length=1, max_length=100)
    items: list[OrderItemCreateRequest] = Field(min_length=1)


class PaymentCompleteRequest(BaseModel):
    """Successful payment result for a reserved order."""

    paymentMethod: str = Field(min_length=1, max_length=30)
    transactionKey: str = Field(min_length=1, max_length=100)
    customerCouponId: int | None = Field(default=None, gt=0)
    pointsUsed: int = Field(default=0, ge=0)


class PaymentFailRequest(BaseModel):
    """Failed payment attempt that releases its order reservation."""

    paymentMethod: str = Field(min_length=1, max_length=30)
    transactionKey: str = Field(min_length=1, max_length=100)
    failureReason: str = Field(min_length=1, max_length=255)


class OrderCancelRequest(BaseModel):
    """Reason for canceling an unpaid order."""

    reason: str = Field(min_length=1, max_length=255)


class OrderTransactionResponse(BaseModel):
    """Order and inventory state after one transactional operation."""

    orderId: int
    orderNumber: str
    orderStatus: str
    reservedQuantity: int
    paymentId: int | None = None
    fulfillmentId: int | None = None
    paidTotal: int | None = None
    couponDiscount: int = 0
    pointsUsed: int = 0


class StatusHistoryResponse(BaseModel):
    """One append-only state transition exposed to clients or staff tools."""

    previousStatus: str | None
    newStatus: str
    changeSource: str
    changeReason: str | None
    actorType: str
    actorCustomerId: int | None
    actorEmployeeId: int | None
    changedAt: datetime


class CustomerProfileSyncRequest(BaseModel):
    """Business profile fields synchronized after Firebase sign-in."""

    customerName: str = Field(min_length=1, max_length=100)
    phone: str | None = Field(default=None, max_length=20)
    birthDate: date | None = None
    ensureOnly: bool = False


class CustomerProfileResponse(BaseModel):
    """MySQL customer linked to the verified Firebase identity."""

    customerId: int
    firebaseUid: str
    email: str | None
    customerName: str
    phone: str | None
    birthDate: str | None


class ProcurementItemRequest(BaseModel):
    productVariantId: int = Field(gt=0)
    requestedQuantity: int = Field(gt=0)


class ProcurementRequisitionCreateRequest(BaseModel):
    title: str = Field(min_length=1, max_length=150)
    reason: str = Field(min_length=1)
    items: list[ProcurementItemRequest] = Field(min_length=1)


class ProcurementApprovalDecisionRequest(BaseModel):
    decision: Literal["APPROVED", "REJECTED"]
    comment: str | None = None


class ProcurementApprovalResponse(BaseModel):
    sequence: int
    requiredRole: str
    status: str
    approverEmployeeId: int | None
    comment: str | None
    decidedAt: datetime | None


class ProcurementRequisitionResponse(BaseModel):
    purchaseRequisitionId: int
    status: str
    requestedByEmployeeId: int
    title: str
    approvals: list[ProcurementApprovalResponse]


class PointCreditRequest(BaseModel):
    """Administrative point credit that creates one independently expiring lot."""

    customerId: int = Field(gt=0)
    amount: int = Field(gt=0)
    idempotencyKey: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=255)


class PointUseRequest(BaseModel):
    """Customer request to spend points from the earliest-expiring lots."""

    amount: int = Field(gt=0)
    idempotencyKey: str = Field(min_length=1, max_length=100)
    orderId: int | None = Field(default=None, gt=0)


class PointTransactionResponse(BaseModel):
    pointTransactionId: int
    transactionType: str
    pointAmount: int
    balanceAfter: int
    expiresAt: datetime | None


class PointLotResponse(BaseModel):
    remainingAmount: int
    earnedAt: datetime
    expiresAt: datetime


class PointWalletResponse(BaseModel):
    balance: int
    lots: list[PointLotResponse]
