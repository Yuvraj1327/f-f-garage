"""Coupons: checking a code for a customer's order, and admin management.

The discount is always worked out here from the coupon's own rules; the app never sends
one. The database re-checks the limits atomically when the booking is created.
"""

import logging
from collections.abc import Callable
from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

from app.core.errors import NotFoundError, UnprocessableError
from app.db.coupon_repository import CouponRepository
from app.domain import billing
from app.schemas.coupon import CouponCreate, CouponOut, CouponRecord, CouponUpdate
from app.schemas.profile import ProfileOut

logger = logging.getLogger(__name__)


def _rupees(value: Decimal) -> str:
    return f"₹{value:,.2f}".replace(".00", "")


class CouponService:
    def __init__(
        self, coupons: CouponRepository, clock: Callable[[], datetime] | None = None
    ) -> None:
        self._coupons = coupons
        self._clock = clock or (lambda: datetime.now(UTC))

    # ---- Customer: apply a code to an order ----------------------------------------------
    def apply(
        self, customer_id: UUID, code: str, subtotal: Decimal
    ) -> tuple[CouponRecord, Decimal]:
        """Returns the coupon and the discount it gives on `subtotal`, or raises 422 with the
        reason the customer should see."""
        coupon = self._coupons.get_by_code(code)
        if coupon is None or not coupon.is_active:
            raise UnprocessableError("This coupon code is not valid")
        now = self._clock()
        if coupon.starts_at is not None and now < coupon.starts_at:
            raise UnprocessableError("This coupon is not active yet")
        if coupon.ends_at is not None and now > coupon.ends_at:
            raise UnprocessableError("This coupon has expired")
        if subtotal < coupon.min_order_amount:
            raise UnprocessableError(
                f"This coupon needs an order of at least {_rupees(coupon.min_order_amount)}"
            )
        if coupon.usage_limit is not None and self._coupons.usage(coupon.id) >= coupon.usage_limit:
            raise UnprocessableError("This coupon has been fully used")
        if self._coupons.usage(coupon.id, customer_id) >= coupon.per_customer_limit:
            raise UnprocessableError("You have already used this coupon")

        if coupon.discount_type == "percent":
            discount = billing.percent_discount(
                subtotal, coupon.discount_value, coupon.max_discount
            )
        else:
            discount = billing.flat_discount(subtotal, coupon.discount_value)
        if discount <= 0:
            raise UnprocessableError("This coupon does not apply to this order")
        return coupon, discount

    # ---- Admin ---------------------------------------------------------------------------
    def list_all(self) -> list[CouponOut]:
        counts = self._coupons.usage_counts()
        return [
            CouponOut(**c.model_dump(), times_used=counts.get(c.id, 0))
            for c in self._coupons.list_all()
        ]

    def create(self, admin: ProfileOut, payload: CouponCreate) -> CouponOut:
        coupon = self._coupons.create(payload.model_dump(mode="json"))
        logger.info("admin %s created coupon %s", admin.id, coupon.code)
        return CouponOut(**coupon.model_dump())

    def update(self, admin: ProfileOut, coupon_id: UUID, payload: CouponUpdate) -> CouponOut:
        current = self._coupons.get(coupon_id)
        if current is None:
            raise NotFoundError("Coupon not found")
        sent = payload.model_fields_set
        value = payload.discount_value if "discount_value" in sent else current.discount_value
        if current.discount_type == "percent" and value is not None and value > 100:
            raise UnprocessableError("A percentage discount cannot be above 100")
        starts = payload.starts_at if "starts_at" in sent else current.starts_at
        ends = payload.ends_at if "ends_at" in sent else current.ends_at
        if starts and ends and ends <= starts:
            raise UnprocessableError("The end must be after the start")
        updated = self._coupons.update(coupon_id, payload.to_update_values())
        if updated is None:
            raise NotFoundError("Coupon not found")
        logger.info(
            "admin %s updated coupon %s (%s)", admin.id, updated.code, ", ".join(sorted(sent))
        )
        return CouponOut(**updated.model_dump(), times_used=self._coupons.usage(coupon_id))
