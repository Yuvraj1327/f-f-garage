"""Extra charge requests, the bill of a booking and refund records."""

from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

from app.domain.enums import BookingStatus, ExtraChargeType
from app.schemas.common import optional_text, single_line

Amount = Annotated[
    Decimal, AfterValidator(lambda v: v.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
]
ExtraStatus = Literal["proposed", "approved", "declined", "withdrawn"]


# ---- Extra charge requests ------------------------------------------------------------


class ExtraRequestCreate(BaseModel):
    """Raised by the driver (or an admin) while the service is in progress. The customer must
    approve it before it is added to the bill."""

    model_config = ConfigDict(extra="forbid")

    name: Annotated[str, single_line(2, 120)]
    amount: Annotated[Decimal, Field(gt=0, le=500000, max_digits=8, decimal_places=2)]
    charge_type: ExtraChargeType = ExtraChargeType.OTHER
    description: Annotated[str | None, optional_text(500)] = None


class ExtraRequestRecord(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    booking_id: UUID
    charge_type: ExtraChargeType
    name: str
    description: str | None = None
    amount: Amount
    status: ExtraStatus
    requested_by: UUID | None = None
    requested_by_role: str
    decided_at: datetime | None = None
    created_at: datetime


class ExtraRequestOut(BaseModel):
    id: UUID
    booking_id: UUID
    charge_type: ExtraChargeType
    name: str
    description: str | None = None
    amount: Amount
    status: ExtraStatus
    requested_by_role: str
    decided_at: datetime | None = None
    created_at: datetime


class ExtrasSummary(BaseModel):
    """What the extra requests of one booking add up to (for list screens)."""

    approved_total: Amount = Decimal("0.00")
    pending_count: int = 0


# ---- Refunds --------------------------------------------------------------------------


class RefundCreate(BaseModel):
    """An admin records a refund they already made in the payment gateway's dashboard."""

    model_config = ConfigDict(extra="forbid")

    amount: Annotated[Decimal, Field(gt=0, le=1000000, max_digits=9, decimal_places=2)]
    note: Annotated[str | None, optional_text(300)] = None


class ReviewResolve(BaseModel):
    """An admin has looked at a flagged payment and decided nothing more is needed."""

    model_config = ConfigDict(extra="forbid")


class RefundRecord(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    payment_id: UUID
    booking_id: UUID
    amount: Amount
    note: str | None = None
    created_at: datetime


# ---- The bill -------------------------------------------------------------------------


class BillPayment(BaseModel):
    id: UUID
    kind: Literal["advance", "balance"]
    status: str
    amount: Amount
    method: str | None = None
    receipt: str | None = None
    transaction_id: str | None = None
    paid_at: datetime | None = None
    created_at: datetime


class BillOut(BaseModel):
    """Everything about what a booking costs and what has been paid.

    final_total = estimated_total + approved_extras_total; balance_due = final_total minus
    everything already paid. `is_final` is true once the service is completed: until then
    more extras can still be approved, so the figures are the bill so far.
    """

    booking_id: UUID
    booking_code: str
    status: BookingStatus
    is_final: bool
    service_name: str
    package_name: str

    package_price: Amount
    addons_total: Amount
    coupon_code: str | None = None
    discount_amount: Amount
    estimated_total: Amount

    advance_percent: Amount
    advance_due: Amount
    advance_paid: Amount

    approved_extras: list[ExtraRequestOut]
    approved_extras_total: Amount
    pending_extras: list[ExtraRequestOut]
    pending_extras_total: Amount

    final_total: Amount
    amount_paid: Amount
    balance_due: Amount
    can_pay_balance: bool

    refunded_total: Amount
    payments: list[BillPayment]
    refunds: list[RefundRecord]
    # The policy text the garage configured (empty = none configured).
    refund_policy: str = ""
