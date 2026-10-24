"""In-memory payments and gateway for the tests.

`FakePaymentRepository.apply_event` mirrors the SQL function `apply_payment_event`
(migration 9), which is itself tested against a real PostgreSQL in
supabase/tests/05_payment_workflow_test.sql. The scenarios below are the same ones.
"""

import uuid
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from app.core.errors import ConflictError
from app.db.payment_repository import OPEN_ATTEMPT, AppliedEvent, payment_search_filter
from app.domain import payment as rules
from app.domain.enums import BookingStatus, PaymentStatus
from app.schemas.payment import PaymentEventOut, PaymentRecord
from app.services.payment_gateway import GatewayOrder, GatewayPayment
from tests.fakes_booking import FakeBookingRepository

S = PaymentStatus


class FakeGateway:
    """Razorpay stand-in. `payments` holds what the gateway would answer for each id."""

    def __init__(self) -> None:
        self.orders: list[dict[str, Any]] = []
        self.payments: dict[str, GatewayPayment] = {}
        self.fetch_calls: list[str] = []
        self.fail_with: Exception | None = None
        self._n = 0

    def create_order(self, *, amount_paise, currency, receipt, notes) -> GatewayOrder:
        if self.fail_with:
            raise self.fail_with
        self._n += 1
        order = GatewayOrder(f"order_T{self._n:04d}", amount_paise, currency)
        self.orders.append(
            {
                "id": order.id,
                "amount": amount_paise,
                "currency": currency,
                "receipt": receipt,
                "notes": notes,
            }
        )
        return order

    def fetch_payment(self, payment_id: str) -> GatewayPayment | None:
        self.fetch_calls.append(payment_id)
        if self.fail_with:
            raise self.fail_with
        return self.payments.get(payment_id)

    def will_report(self, payment_id, order_id, amount_paise, status="captured", **over):
        self.payments[payment_id] = GatewayPayment(
            id=payment_id,
            order_id=order_id,
            amount_paise=amount_paise,
            currency=over.pop("currency", "INR"),
            status=status,
            method=over.pop("method", "upi"),
            error_description=over.pop("error_description", None),
        )


class FakePaymentRepository:
    def __init__(self, bookings: FakeBookingRepository) -> None:
        self.bookings = bookings
        self.rows: dict[UUID, PaymentRecord] = {}
        self.events: list[dict[str, Any]] = []
        bookings.on_cancelled.append(self._booking_cancelled)
        # Called with the booking id when a payment attempt becomes failed (a database trigger).
        self.on_failed: list = []

    # ---- the booking-cancel trigger ----------------------------------------------------
    def _booking_cancelled(self, booking_id: UUID) -> None:
        for r in self.rows.values():
            if r.booking_id != booking_id:
                continue
            if r.status == S.PENDING:
                self._set(r, status=S.CANCELLED)
            elif r.status == S.SUCCESSFUL and not r.needs_review:
                self._set(
                    r,
                    needs_review=True,
                    review_reason="The booking was cancelled after it was paid. Decide on a refund.",  # noqa: E501
                )

    def _set(self, record: PaymentRecord, **changes: Any) -> PaymentRecord:
        updated = record.model_copy(update={**changes, "updated_at": datetime.now(UTC)})
        self.rows[record.id] = updated
        if updated.status == S.FAILED and record.status != S.FAILED:
            for hook in self.on_failed:
                hook(record.booking_id)
        return updated

    def _booking_status(self, booking_id: UUID) -> BookingStatus | None:
        row = self.bookings.rows.get(booking_id)
        return row["status"] if row else None

    # ---- repository API --------------------------------------------------------------
    def create_attempt(self, values: dict[str, Any]) -> PaymentRecord:
        booking_id = UUID(values["booking_id"])
        if any(r.booking_id == booking_id and r.status == S.PENDING for r in self.rows.values()):
            raise ConflictError(OPEN_ATTEMPT)
        order = values.get("provider_order_id")
        if order and any(r.provider_order_id == order for r in self.rows.values()):
            raise ConflictError("This payment order already exists.")
        now = datetime.now(UTC)
        record = PaymentRecord(
            id=uuid.uuid4(),
            booking_id=booking_id,
            customer_id=UUID(values["customer_id"]),
            provider=values["provider"],
            provider_order_id=order,
            amount=Decimal(values["amount"]),
            currency=values.get("currency", "INR"),
            status=S.PENDING,
            receipt=values.get("receipt"),
            livemode=values.get("livemode", False),
            created_at=now,
            updated_at=now,
        )
        self.rows[record.id] = record
        return record

    def get(self, payment_id: UUID) -> PaymentRecord | None:
        return self.rows.get(payment_id)

    def find_open(self, booking_id: UUID) -> PaymentRecord | None:
        return next(
            (r for r in self.rows.values() if r.booking_id == booking_id and r.status == S.PENDING),
            None,
        )

    def list_for_booking(self, booking_id: UUID) -> list[PaymentRecord]:
        rows = [r for r in self.rows.values() if r.booking_id == booking_id]
        return sorted(rows, key=lambda r: r.created_at, reverse=True)

    def summaries_for(self, booking_ids: list[UUID]) -> dict[UUID, PaymentRecord]:
        out: dict[UUID, PaymentRecord] = {}
        for bid in booking_ids:
            rows = self.list_for_booking(bid)
            paid = next((r for r in rows if r.status == S.SUCCESSFUL), None)
            if paid or rows:
                out[bid] = paid or rows[0]
        return out

    def cancel_open(self, payment_id: UUID) -> PaymentRecord | None:
        record = self.rows.get(payment_id)
        if record is None or record.status != S.PENDING:
            return None
        return self._set(record, status=S.CANCELLED)

    def log_event(
        self, *, provider, source, event_type, outcome, order_id, payment_id, payment_uuid, detail
    ) -> None:
        self.events.append(
            {
                "id": uuid.uuid4(),
                "provider": provider,
                "source": source,
                "event_id": None,
                "event_type": event_type,
                "outcome": outcome,
                "provider_order_id": order_id,
                "provider_payment_id": payment_id,
                "payment_id": payment_uuid,
                "detail": detail,
                "created_at": datetime.now(UTC),
            }
        )

    def events_for(self, payment_id: UUID) -> list[PaymentEventOut]:
        return [
            PaymentEventOut.model_validate(e) for e in self.events if e["payment_id"] == payment_id
        ]

    def search(
        self,
        *,
        statuses,
        booking_id,
        customer_id,
        needs_review,
        created_from,
        created_before,
        query,
        limit,
        offset,
    ):
        rows = list(self.rows.values())
        if statuses:
            rows = [r for r in rows if r.status in statuses]
        if booking_id:
            rows = [r for r in rows if r.booking_id == booking_id]
        if customer_id:
            rows = [r for r in rows if r.customer_id == customer_id]
        if needs_review is not None:
            rows = [r for r in rows if r.needs_review == needs_review]
        if created_from:
            rows = [r for r in rows if r.created_at >= created_from]
        if created_before:
            rows = [r for r in rows if r.created_at < created_before]
        if query and payment_search_filter(query):
            cond = payment_search_filter(query).split(",")
            wanted = {c.split(".eq.")[0]: c.split(".eq.")[1] for c in cond}
            rows = [
                r
                for r in rows
                if r.provider_order_id == wanted["provider_order_id"]
                or r.provider_payment_id == wanted["provider_payment_id"]
                or ("receipt" in wanted and r.receipt == wanted["receipt"])
            ]
        rows.sort(key=lambda r: r.created_at, reverse=True)
        return rows[offset : offset + limit], len(rows)

    # ---- mirror of apply_payment_event ---------------------------------------------------
    def apply_event(
        self,
        *,
        provider,
        order_id,
        payment_id,
        outcome,
        amount_paise,
        currency,
        method,
        failure,
        source,
        event_id,
        event_type,
        detail,
    ) -> AppliedEvent:
        def summary(result: str, record: PaymentRecord | None) -> AppliedEvent:
            if record is None:
                return AppliedEvent(result, None, None, None, None)
            return AppliedEvent(
                result,
                record.id,
                record.status,
                record.booking_id,
                self._booking_status(record.booking_id),
            )

        if event_id is not None:
            earlier = next(
                (e for e in self.events if e["provider"] == provider and e["event_id"] == event_id),
                None,
            )
            if earlier is not None:
                return summary("duplicate_event", self.rows.get(earlier["payment_id"]))
        event = {
            "id": uuid.uuid4(),
            "provider": provider,
            "source": source,
            "event_id": event_id,
            "event_type": event_type,
            "provider_order_id": order_id,
            "provider_payment_id": payment_id,
            "payment_id": None,
            "outcome": "received",
            "detail": detail,
            "created_at": datetime.now(UTC),
        }
        self.events.append(event)

        record = next(
            (
                r
                for r in self.rows.values()
                if r.provider == provider and r.provider_order_id == order_id
            ),
            None,
        )
        if record is None:
            event["outcome"] = "unknown_order"
            return summary("unknown_order", None)

        if outcome == "captured":
            if amount_paise != rules.to_paise(record.amount) or currency != record.currency:
                if record.status == S.SUCCESSFUL:
                    self._set(
                        record,
                        needs_review=True,
                        review_reason="Gateway reported a different amount for a second payment",
                    )
                else:
                    self._set(
                        record,
                        status=S.FAILED,
                        failure_reason="Amount mismatch",
                        provider_payment_id=payment_id or record.provider_payment_id,
                        needs_review=True,
                        review_reason="The gateway reported money taken in a different amount "
                        "than the order. Check and refund if needed.",
                    )
                result = "amount_mismatch"
            elif record.status == S.SUCCESSFUL:
                if record.provider_payment_id == payment_id:
                    result = "already_processed"
                else:
                    self._set(
                        record,
                        needs_review=True,
                        review_reason="A second payment was captured for this order. "
                        "Refund the extra payment.",
                    )
                    result = "duplicate_payment"
            else:
                booking_status = self._booking_status(record.booking_id)
                other = any(
                    r.booking_id == record.booking_id
                    and r.status == S.SUCCESSFUL
                    and r.id != record.id
                    for r in self.rows.values()
                )
                if other:
                    self._set(
                        record,
                        status=S.FAILED,
                        failure_reason="The booking was already paid by another payment",
                        provider_payment_id=payment_id or record.provider_payment_id,
                        method=method or record.method,
                        needs_review=True,
                        review_reason="Money was captured for a booking that is already paid. "
                        "Refund this payment.",
                    )
                    result = "duplicate_payment"
                else:
                    record = self._set(
                        record,
                        status=S.SUCCESSFUL,
                        provider_payment_id=payment_id,
                        method=method or record.method,
                        paid_at=datetime.now(UTC),
                        failure_reason=None,
                    )
                    if booking_status == BookingStatus.PENDING_PAYMENT:
                        self.bookings.confirm_paid(record.booking_id)
                        result = "paid"
                    elif booking_status == BookingStatus.CANCELLED:
                        self._set(
                            record,
                            needs_review=True,
                            review_reason="Payment received for a booking that was "
                            "cancelled. Refund this payment.",
                        )
                        result = "paid_review"
                    else:
                        result = "paid"
        elif outcome == "failed":
            if record.status in (S.SUCCESSFUL, S.CANCELLED):
                result = "ignored"
            else:
                self._set(
                    record,
                    status=S.FAILED,
                    failure_reason=(failure or "The payment failed")[:500],
                    provider_payment_id=payment_id or record.provider_payment_id,
                    method=method or record.method,
                )
                result = "failed"
        else:
            result = "pending"

        event["outcome"] = result
        event["payment_id"] = record.id
        return summary(result, self.rows[record.id])
