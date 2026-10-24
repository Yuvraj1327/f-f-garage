"""API contracts for payments."""

from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated, Any
from uuid import UUID

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

from app.domain.enums import BookingStatus, PaymentStatus

# Money always shows two decimals ("849.00"), like in the booking schemas.
Amount = Annotated[
    Decimal, AfterValidator(lambda v: v.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
]

_GATEWAY_ID = r"^[A-Za-z0-9_]{1,64}$"


class PaymentRecord(BaseModel):
    """A payments row as stored."""

    model_config = ConfigDict(extra="ignore")

    id: UUID
    booking_id: UUID
    customer_id: UUID
    provider: str
    provider_order_id: str | None = None
    provider_payment_id: str | None = None
    amount: Amount
    currency: str
    status: PaymentStatus
    failure_reason: str | None = None
    paid_at: datetime | None = None
    method: str | None = None
    receipt: str | None = None
    livemode: bool = False
    needs_review: bool = False
    review_reason: str | None = None
    created_at: datetime
    updated_at: datetime


class PaymentSummary(BaseModel):
    """The payment line shown inside a booking."""

    id: UUID
    status: PaymentStatus
    amount: Amount
    currency: str
    method: str | None = None
    transaction_id: str | None = None
    paid_at: datetime | None = None
    failure_reason: str | None = None
    livemode: bool = False
    created_at: datetime


class PaymentOut(PaymentSummary):
    booking_id: UUID
    provider: str
    gateway_order_id: str | None = None


class CheckoutOptions(BaseModel):
    """Everything the app hands to the Razorpay checkout. No secrets: `key_id` is the
    public key, and the amount is the server's own."""

    key_id: str
    order_id: str
    amount_paise: int
    currency: str
    name: str
    description: str
    prefill_name: str | None = None
    prefill_contact: str | None = None
    prefill_email: str | None = None
    mode: str = Field(description="'test' (sandbox) or 'live'")


class PaymentInitiated(BaseModel):
    payment: PaymentOut
    checkout: CheckoutOptions


def _clean(value: str) -> str:
    return value.strip()


GatewayId = Annotated[str, AfterValidator(_clean), Field(pattern=_GATEWAY_ID)]


class PaymentVerify(BaseModel):
    """What the Razorpay checkout returns to the app. The app is only a messenger: the
    backend re-computes the signature and asks the gateway before believing any of it."""

    model_config = ConfigDict(extra="forbid")

    razorpay_order_id: GatewayId
    razorpay_payment_id: GatewayId
    razorpay_signature: Annotated[str, Field(min_length=16, max_length=128)]


class PaymentResult(BaseModel):
    payment: PaymentOut
    booking_status: BookingStatus
    outcome: str
    paid: bool


class PaymentEventOut(BaseModel):
    id: UUID
    source: str
    event_type: str
    outcome: str
    provider_order_id: str | None = None
    provider_payment_id: str | None = None
    detail: dict[str, Any] | None = None
    created_at: datetime


class AdminPaymentOut(PaymentOut):
    customer_id: UUID
    receipt: str | None = None
    needs_review: bool = False
    review_reason: str | None = None
    updated_at: datetime


class AdminPaymentDetail(AdminPaymentOut):
    events: list[PaymentEventOut] = Field(default_factory=list)


class AdminPaymentPage(BaseModel):
    items: list[AdminPaymentOut]
    total: int
    limit: int
    offset: int


class WebhookAck(BaseModel):
    status: str
