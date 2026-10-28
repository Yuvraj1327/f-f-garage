"""Coupons: what an admin manages and what a customer's quote shows."""

from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator

from app.schemas.common import Money, PatchModel, optional_text

DiscountType = Literal["percent", "flat"]


def clean_coupon_code(raw: str) -> str:
    """Codes are typed by people: trim and upper-case them, 3-20 of A-Z 0-9 _ -."""
    code = raw.strip().upper()
    if not (3 <= len(code) <= 20) or any(
        not (ch.isascii() and (ch.isalnum() or ch in "_-")) for ch in code
    ):
        raise ValueError("A coupon code has 3-20 letters, digits, - or _")
    return code


CouponCode = Annotated[str, AfterValidator(clean_coupon_code)]
Percent = Annotated[Decimal, Field(gt=0, le=100, max_digits=5, decimal_places=2)]


class CouponCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: CouponCode
    description: Annotated[str | None, optional_text(200)] = None
    discount_type: DiscountType
    # Percent (1-100) for "percent", rupees for "flat".
    discount_value: Annotated[Decimal, Field(gt=0, le=1000000, max_digits=9, decimal_places=2)]
    # Upper limit of a percent discount, in rupees.
    max_discount: Annotated[Money, Field(gt=0)] | None = None
    min_order_amount: Money = Decimal("0")
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    usage_limit: Annotated[int, Field(ge=1, le=1_000_000)] | None = None
    per_customer_limit: Annotated[int, Field(ge=1, le=1000)] = 1
    is_active: bool = True

    @model_validator(mode="after")
    def _consistent(self) -> "CouponCreate":
        if self.discount_type == "percent" and self.discount_value > 100:
            raise ValueError("A percentage discount cannot be above 100")
        if self.starts_at and self.ends_at and self.ends_at <= self.starts_at:
            raise ValueError("The end must be after the start")
        return self


class CouponUpdate(PatchModel):
    """The code and the kind of discount are fixed once created (make a new coupon)."""

    nullable = frozenset({"description", "max_discount", "starts_at", "ends_at", "usage_limit"})

    description: Annotated[str | None, optional_text(200)] = None
    discount_value: (
        Annotated[Decimal, Field(gt=0, le=1000000, max_digits=9, decimal_places=2)] | None
    ) = None
    max_discount: Annotated[Money, Field(gt=0)] | None = None
    min_order_amount: Money | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    usage_limit: Annotated[int, Field(ge=1, le=1_000_000)] | None = None
    per_customer_limit: Annotated[int, Field(ge=1, le=1000)] | None = None
    is_active: bool | None = None


class CouponRecord(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    code: str
    description: str | None = None
    discount_type: str
    discount_value: Decimal
    max_discount: Decimal | None = None
    min_order_amount: Decimal = Decimal("0")
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    usage_limit: int | None = None
    per_customer_limit: int = 1
    is_active: bool = True
    created_at: datetime
    updated_at: datetime


class CouponOut(CouponRecord):
    """What the admin sees: the coupon and how many live bookings use it."""

    times_used: int = 0
