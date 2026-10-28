"""Bookings in Supabase (service-role client).

The two things that must be atomic live in the database, not here: `create_booking`
inserts the booking and its extra-charge snapshot in one transaction, and triggers
enforce slot capacity, duplicates and legal status changes.
"""

import re
from datetime import date
from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.core.errors import ServiceUnavailableError
from app.db.postgrest import run, run_counted
from app.domain.enums import BookingStatus, VehicleType
from app.schemas.booking import BookingRecord

SLOT_FULL = "That time slot has just been filled. Please choose another."
ALREADY_BOOKED = "You already have a booking for this time slot."
_HINTS = {
    "slot_full": SLOT_FULL,
    "bookings_one_active_per_customer_slot": ALREADY_BOOKED,
    "bookings_client_request_key": "This request was already submitted.",
    "coupon_unavailable": "This coupon is no longer available. Remove it and try again.",
}
_SELECT = "*, booking_extra_charges(*)"


class BookingRepository(Protocol):
    def create(self, values: dict[str, Any], charges: list[dict[str, Any]]) -> BookingRecord: ...

    def get(self, booking_id: UUID) -> BookingRecord | None: ...

    def get_many(self, booking_ids: list[UUID]) -> list[BookingRecord]:
        """The bookings that exist among `booking_ids`, in the order given."""
        ...

    def find_by_request(self, customer_id: UUID, request_id: UUID) -> BookingRecord | None: ...

    def list_for_customer(
        self,
        customer_id: UUID,
        *,
        statuses: list[BookingStatus] | None,
        limit: int,
        offset: int,
    ) -> tuple[list[BookingRecord], int]: ...

    def search(
        self,
        *,
        statuses: list[BookingStatus] | None = None,
        vehicle_type: VehicleType | None = None,
        date_from: date | None = None,
        date_to: date | None = None,
        pincode: str | None = None,
        customer_id: UUID | None = None,
        query: str | None = None,
        limit: int,
        offset: int,
    ) -> tuple[list[BookingRecord], int]: ...

    def update(
        self,
        booking_id: UUID,
        values: dict[str, Any],
        *,
        only_statuses: list[BookingStatus] | None = None,
    ) -> BookingRecord | None:
        """Updates the booking, but only while it is still in one of `only_statuses`
        (so a status that changed in the meantime is not overwritten). None when
        no row matched."""
        ...


def search_filter(text: str) -> str | None:
    """A PostgREST `or` filter for the admin search box, or None for an empty search.

    Everything that could change the meaning of the filter (commas, parentheses,
    wildcards, LIKE metacharacters) is dropped first.
    """
    cleaned = re.sub(r"[^A-Za-z0-9 .'@-]", "", text).strip()
    if not cleaned:
        return None
    parts: list[str] = []
    compact = cleaned.replace(" ", "").replace("-", "")
    code = re.fullmatch(r"(?:ff)?0*([0-9]{1,9})", compact, flags=re.IGNORECASE)
    if code:
        parts.append(f"booking_number.eq.{int(code.group(1))}")
    if compact.isdigit() and len(compact) >= 4:
        parts.append(f"customer_phone.ilike.*{compact}*")
    parts.append(f"customer_name.ilike.*{cleaned}*")
    return ",".join(parts)


class SupabaseBookingRepository:
    TABLE = "bookings"

    def __init__(self, client: Client) -> None:
        self._client = client

    @staticmethod
    def _record(row: dict[str, Any]) -> BookingRecord:
        return BookingRecord.model_validate(row)

    def create(self, values: dict[str, Any], charges: list[dict[str, Any]]) -> BookingRecord:
        rows = run(
            self._client.rpc("create_booking", {"p_booking": values, "p_charges": charges}),
            conflict_hints=_HINTS,
        )
        if not rows:
            raise ServiceUnavailableError("Database returned no booking")
        # The RPC returns the bare row; read it back with its charges.
        created = self.get(UUID(str(rows[0]["id"])))
        if created is None:
            raise ServiceUnavailableError("Database returned no booking")
        return created

    def get(self, booking_id: UUID) -> BookingRecord | None:
        rows = run(
            self._client.table(self.TABLE).select(_SELECT).eq("id", str(booking_id)).limit(1)
        )
        return self._record(rows[0]) if rows else None

    def get_many(self, booking_ids: list[UUID]) -> list[BookingRecord]:
        if not booking_ids:
            return []
        rows = run(
            self._client.table(self.TABLE).select(_SELECT).in_("id", [str(i) for i in booking_ids])
        )
        found = {r.id: r for r in (self._record(row) for row in rows)}
        return [found[i] for i in booking_ids if i in found]

    def find_by_request(self, customer_id: UUID, request_id: UUID) -> BookingRecord | None:
        rows = run(
            self._client.table(self.TABLE)
            .select(_SELECT)
            .eq("customer_id", str(customer_id))
            .eq("client_request_id", str(request_id))
            .limit(1)
        )
        return self._record(rows[0]) if rows else None

    def list_for_customer(
        self,
        customer_id: UUID,
        *,
        statuses: list[BookingStatus] | None,
        limit: int,
        offset: int,
    ) -> tuple[list[BookingRecord], int]:
        return self.search(statuses=statuses, customer_id=customer_id, limit=limit, offset=offset)

    def search(
        self,
        *,
        statuses: list[BookingStatus] | None = None,
        vehicle_type: VehicleType | None = None,
        date_from: date | None = None,
        date_to: date | None = None,
        pincode: str | None = None,
        customer_id: UUID | None = None,
        query: str | None = None,
        limit: int,
        offset: int,
    ) -> tuple[list[BookingRecord], int]:
        q = self._client.table(self.TABLE).select(_SELECT, count="exact")
        if customer_id is not None:
            q = q.eq("customer_id", str(customer_id))
        if statuses:
            q = q.in_("status", [s.value for s in statuses])
        if vehicle_type is not None:
            q = q.eq("vehicle_type", vehicle_type.value)
        if date_from is not None:
            q = q.gte("scheduled_date", date_from.isoformat())
        if date_to is not None:
            q = q.lte("scheduled_date", date_to.isoformat())
        if pincode is not None:
            q = q.eq("pincode", pincode)
        if query:
            condition = search_filter(query)
            if condition:
                q = q.or_(condition)
        q = (
            q.order("created_at", desc=True)
            .order("booking_number", desc=True)
            .range(offset, offset + limit - 1)
        )
        rows, total = run_counted(q)
        return [self._record(r) for r in rows], total

    def update(
        self,
        booking_id: UUID,
        values: dict[str, Any],
        *,
        only_statuses: list[BookingStatus] | None = None,
    ) -> BookingRecord | None:
        q = self._client.table(self.TABLE).update(values).eq("id", str(booking_id))
        if only_statuses:
            q = q.in_("status", [s.value for s in only_statuses])
        rows = run(q, conflict_hints=_HINTS)
        if not rows:
            return None
        return self.get(booking_id)
