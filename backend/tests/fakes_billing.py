"""In-memory coupons, extra charge requests and refunds for the tests.

They mirror the SQL in migration 20261028100000 (itself tested on a real PostgreSQL in
supabase/tests/10_service_flow_test.sql).
"""

import uuid
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from app.core.errors import ConflictError
from app.db.refund_repository import RefundOutcome
from app.schemas.billing import ExtraRequestRecord, ExtrasSummary, RefundRecord
from app.schemas.coupon import CouponRecord


def _now() -> datetime:
    return datetime.now(UTC)


class FakeCoupons:
    def __init__(self) -> None:
        self.rows: dict[UUID, CouponRecord] = {}
        # (coupon_id, customer_id) per live (not cancelled) redemption; tests append here.
        self.redemptions: list[tuple[UUID, UUID]] = []

    def get_by_code(self, code: str) -> CouponRecord | None:
        return next((c for c in self.rows.values() if c.code == code), None)

    def get(self, coupon_id: UUID) -> CouponRecord | None:
        return self.rows.get(coupon_id)

    def list_all(self) -> list[CouponRecord]:
        return sorted(self.rows.values(), key=lambda c: c.created_at, reverse=True)

    def create(self, values: dict[str, Any]) -> CouponRecord:
        if self.get_by_code(values["code"]):
            raise ConflictError("A coupon with this code already exists")
        now = _now()
        record = CouponRecord.model_validate(
            {"id": uuid.uuid4(), "created_at": now, "updated_at": now, **values}
        )
        self.rows[record.id] = record
        return record

    def update(self, coupon_id: UUID, values: dict[str, Any]) -> CouponRecord | None:
        current = self.rows.get(coupon_id)
        if current is None:
            return None
        updated = current.model_copy(update={**values, "updated_at": _now()})
        self.rows[coupon_id] = updated
        return updated

    def usage(self, coupon_id: UUID, customer_id: UUID | None = None) -> int:
        return sum(
            1
            for c, who in self.redemptions
            if c == coupon_id and (customer_id is None or who == customer_id)
        )

    def usage_counts(self) -> dict[UUID, int]:
        return {i: self.usage(i) for i in self.rows}


class FakeExtraRequests:
    def __init__(self) -> None:
        self.rows: dict[UUID, ExtraRequestRecord] = {}

    def create(self, values: dict[str, Any]) -> ExtraRequestRecord:
        record = ExtraRequestRecord.model_validate(
            {
                "id": uuid.uuid4(),
                "status": "proposed",
                "created_at": _now(),
                "decided_at": None,
                **values,
            }
        )
        self.rows[record.id] = record
        return record

    def get(self, extra_id: UUID) -> ExtraRequestRecord | None:
        return self.rows.get(extra_id)

    def list_for_booking(self, booking_id: UUID) -> list[ExtraRequestRecord]:
        return sorted(
            (r for r in self.rows.values() if r.booking_id == booking_id),
            key=lambda r: r.created_at,
        )

    def answer(self, extra_id: UUID, status: str) -> ExtraRequestRecord | None:
        current = self.rows.get(extra_id)
        if current is None or current.status != "proposed":
            return None
        update: dict[str, Any] = {"status": status}
        if status in ("approved", "declined"):
            update["decided_at"] = _now()
        self.rows[extra_id] = current.model_copy(update=update)
        return self.rows[extra_id]

    def withdraw_open(self, booking_id: UUID) -> None:
        """The cancel trigger: open requests of a cancelled booking are withdrawn."""
        for i, r in list(self.rows.items()):
            if r.booking_id == booking_id and r.status == "proposed":
                self.rows[i] = r.model_copy(update={"status": "withdrawn"})

    def summaries(self, booking_ids: list[UUID]) -> dict[UUID, ExtrasSummary]:
        out: dict[UUID, ExtrasSummary] = {}
        for booking_id in booking_ids:
            rows = self.list_for_booking(booking_id)
            approved = sum((r.amount for r in rows if r.status == "approved"), Decimal("0"))
            pending = sum(1 for r in rows if r.status == "proposed")
            if approved or pending:
                out[booking_id] = ExtrasSummary(approved_total=approved, pending_count=pending)
        return out


class FakeRefunds:
    def __init__(self, payments) -> None:
        self.payments = payments
        self.rows: dict[UUID, RefundRecord] = {}

    def record(
        self, payment_id: UUID, amount: Decimal, note: str | None, admin_id: UUID
    ) -> RefundOutcome:
        payment = self.payments.rows.get(payment_id)
        if payment is None:
            return RefundOutcome("payment_not_found", None)
        if payment.status.value != "successful":
            return RefundOutcome("payment_not_successful", None)
        already = sum(
            (r.amount for r in self.rows.values() if r.payment_id == payment_id), Decimal("0")
        )
        if already + amount > payment.amount:
            return RefundOutcome("exceeds_payment", None)
        record = RefundRecord(
            id=uuid.uuid4(),
            payment_id=payment_id,
            booking_id=payment.booking_id,
            amount=amount,
            note=note,
            created_at=_now(),
        )
        self.rows[record.id] = record
        return RefundOutcome("recorded", record.id)

    def get(self, refund_id: UUID) -> RefundRecord | None:
        return self.rows.get(refund_id)

    def list_for_booking(self, booking_id: UUID) -> list[RefundRecord]:
        return [r for r in self.rows.values() if r.booking_id == booking_id]

    def list_for_payment(self, payment_id: UUID) -> list[RefundRecord]:
        return [r for r in self.rows.values() if r.payment_id == payment_id]
