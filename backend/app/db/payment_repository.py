"""Payments in Supabase (service-role client).

Writes that must be atomic and idempotent go through the `apply_payment_event`
function (migration 9): it locks the payment and the booking, checks the amount,
and is the only code that marks a payment successful or a booking confirmed.
"""

import re
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.core.errors import ServiceUnavailableError
from app.db.postgrest import run, run_counted
from app.domain.enums import BookingStatus, PaymentStatus
from app.schemas.payment import PaymentEventOut, PaymentRecord

OPEN_ATTEMPT = "A payment for this booking is already in progress."
_HINTS = {
    "payments_one_pending_per_booking": OPEN_ATTEMPT,
    "payments_provider_order_key": "This payment order already exists.",
}


@dataclass(frozen=True)
class AppliedEvent:
    result: str
    payment_id: UUID | None
    payment_status: PaymentStatus | None
    booking_id: UUID | None
    booking_status: BookingStatus | None


class PaymentRepository(Protocol):
    def create_attempt(self, values: dict[str, Any]) -> PaymentRecord: ...

    def get(self, payment_id: UUID) -> PaymentRecord | None: ...

    def find_open(self, booking_id: UUID) -> PaymentRecord | None: ...

    def list_for_booking(self, booking_id: UUID) -> list[PaymentRecord]: ...

    def for_bookings(self, booking_ids: list[UUID]) -> dict[UUID, list[PaymentRecord]]:
        """Every attempt of each booking (newest first), in one query."""
        ...

    def resolve_review(self, payment_id: UUID) -> PaymentRecord | None:
        """Clears the "needs a decision" flag; None when there is no such payment."""
        ...

    def cancel_open(self, payment_id: UUID) -> PaymentRecord | None:
        """pending -> cancelled; None when the attempt is no longer pending."""
        ...

    def apply_event(
        self,
        *,
        provider: str,
        order_id: str,
        payment_id: str | None,
        outcome: str,
        amount_paise: int | None,
        currency: str | None,
        method: str | None,
        failure: str | None,
        source: str,
        event_id: str | None,
        event_type: str,
        detail: dict[str, Any] | None,
    ) -> AppliedEvent: ...

    def log_event(
        self,
        *,
        provider: str,
        source: str,
        event_type: str,
        outcome: str,
        order_id: str | None,
        payment_id: str | None,
        payment_uuid: UUID | None,
        detail: dict[str, Any] | None,
    ) -> None: ...

    def search(
        self,
        *,
        statuses: list[PaymentStatus] | None,
        booking_id: UUID | None,
        customer_id: UUID | None,
        needs_review: bool | None,
        created_from: datetime | None,
        created_before: datetime | None,
        query: str | None,
        limit: int,
        offset: int,
    ) -> tuple[list[PaymentRecord], int]: ...

    def events_for(self, payment_id: UUID) -> list[PaymentEventOut]: ...


def payment_search_filter(text: str) -> str | None:
    """An exact-match PostgREST `or` filter on gateway ids and the receipt (booking
    code). Anything that could change the filter's meaning is dropped first."""
    cleaned = re.sub(r"[^A-Za-z0-9_-]", "", text).strip()
    if not cleaned:
        return None
    parts = [f"provider_order_id.eq.{cleaned}", f"provider_payment_id.eq.{cleaned}"]
    code = re.fullmatch(r"(?:ff-?)?0*([0-9]{1,9})", cleaned, flags=re.IGNORECASE)
    if code:
        parts.append(f"receipt.eq.FF-{int(code.group(1)):06d}")
    return ",".join(parts)


class SupabasePaymentRepository:
    TABLE = "payments"

    def __init__(self, client: Client) -> None:
        self._client = client

    @staticmethod
    def _record(row: dict[str, Any]) -> PaymentRecord:
        return PaymentRecord.model_validate(row)

    def create_attempt(self, values: dict[str, Any]) -> PaymentRecord:
        rows = run(self._client.table(self.TABLE).insert(values), conflict_hints=_HINTS)
        if not rows:
            raise ServiceUnavailableError("Database returned no payment")
        return self._record(rows[0])

    def get(self, payment_id: UUID) -> PaymentRecord | None:
        rows = run(self._client.table(self.TABLE).select("*").eq("id", str(payment_id)).limit(1))
        return self._record(rows[0]) if rows else None

    def find_open(self, booking_id: UUID) -> PaymentRecord | None:
        rows = run(
            self._client.table(self.TABLE)
            .select("*")
            .eq("booking_id", str(booking_id))
            .eq("status", PaymentStatus.PENDING.value)
            .limit(1)
        )
        return self._record(rows[0]) if rows else None

    def list_for_booking(self, booking_id: UUID) -> list[PaymentRecord]:
        rows = run(
            self._client.table(self.TABLE)
            .select("*")
            .eq("booking_id", str(booking_id))
            .order("created_at", desc=True)
        )
        return [self._record(r) for r in rows]

    def for_bookings(self, booking_ids: list[UUID]) -> dict[UUID, list[PaymentRecord]]:
        if not booking_ids:
            return {}
        rows = run(
            self._client.table(self.TABLE)
            .select("*")
            .in_("booking_id", [str(i) for i in booking_ids])
            .order("created_at", desc=True)
        )
        grouped: dict[UUID, list[PaymentRecord]] = {}
        for row in rows:  # newest first
            record = self._record(row)
            grouped.setdefault(record.booking_id, []).append(record)
        return grouped

    def resolve_review(self, payment_id: UUID) -> PaymentRecord | None:
        rows = run(
            self._client.table(self.TABLE)
            .update({"needs_review": False, "review_reason": None})
            .eq("id", str(payment_id))
        )
        return self._record(rows[0]) if rows else None

    def cancel_open(self, payment_id: UUID) -> PaymentRecord | None:
        rows = run(
            self._client.table(self.TABLE)
            .update({"status": PaymentStatus.CANCELLED.value})
            .eq("id", str(payment_id))
            .eq("status", PaymentStatus.PENDING.value)
        )
        return self._record(rows[0]) if rows else None

    def apply_event(
        self,
        *,
        provider: str,
        order_id: str,
        payment_id: str | None,
        outcome: str,
        amount_paise: int | None,
        currency: str | None,
        method: str | None,
        failure: str | None,
        source: str,
        event_id: str | None,
        event_type: str,
        detail: dict[str, Any] | None,
    ) -> AppliedEvent:
        rows = run(
            self._client.rpc(
                "apply_payment_event",
                {
                    "p_provider": provider,
                    "p_order_id": order_id,
                    "p_payment_id": payment_id,
                    "p_outcome": outcome,
                    "p_amount_paise": amount_paise,
                    "p_currency": currency,
                    "p_method": method,
                    "p_failure": failure,
                    "p_source": source,
                    "p_event_id": event_id,
                    "p_event_type": event_type,
                    "p_detail": detail,
                },
            )
        )
        if not rows:
            raise ServiceUnavailableError("Database returned no payment result")
        row = rows[0]
        return AppliedEvent(
            result=row["result"],
            payment_id=UUID(row["payment_id"]) if row.get("payment_id") else None,
            payment_status=PaymentStatus(row["payment_status"])
            if row.get("payment_status")
            else None,
            booking_id=UUID(row["booking_id"]) if row.get("booking_id") else None,
            booking_status=BookingStatus(row["booking_status"])
            if row.get("booking_status")
            else None,
        )

    def log_event(
        self,
        *,
        provider: str,
        source: str,
        event_type: str,
        outcome: str,
        order_id: str | None,
        payment_id: str | None,
        payment_uuid: UUID | None,
        detail: dict[str, Any] | None,
    ) -> None:
        run(
            self._client.table("payment_events").insert(
                {
                    "provider": provider,
                    "source": source,
                    "event_type": event_type,
                    "outcome": outcome,
                    "provider_order_id": order_id,
                    "provider_payment_id": payment_id,
                    "payment_id": str(payment_uuid) if payment_uuid else None,
                    "detail": detail,
                }
            )
        )

    def search(
        self,
        *,
        statuses: list[PaymentStatus] | None,
        booking_id: UUID | None,
        customer_id: UUID | None,
        needs_review: bool | None,
        created_from: datetime | None,
        created_before: datetime | None,
        query: str | None,
        limit: int,
        offset: int,
    ) -> tuple[list[PaymentRecord], int]:
        q = self._client.table(self.TABLE).select("*", count="exact")
        if statuses:
            q = q.in_("status", [s.value for s in statuses])
        if booking_id is not None:
            q = q.eq("booking_id", str(booking_id))
        if customer_id is not None:
            q = q.eq("customer_id", str(customer_id))
        if needs_review is not None:
            q = q.eq("needs_review", needs_review)
        if created_from is not None:
            q = q.gte("created_at", created_from.isoformat())
        if created_before is not None:
            q = q.lt("created_at", created_before.isoformat())
        if query:
            condition = payment_search_filter(query)
            if condition:
                q = q.or_(condition)
        q = q.order("created_at", desc=True).order("id").range(offset, offset + limit - 1)
        rows, total = run_counted(q)
        return [self._record(r) for r in rows], total

    def events_for(self, payment_id: UUID) -> list[PaymentEventOut]:
        rows = run(
            self._client.table("payment_events")
            .select("*")
            .eq("payment_id", str(payment_id))
            .order("created_at")
        )
        return [PaymentEventOut.model_validate(r) for r in rows]
