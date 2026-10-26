"""In-memory bookings that enforce the same rules as migration 8: one active booking per
customer and slot, hard slot capacity, idempotent request keys, legal status changes and
locked snapshot columns. Keeps the fake availability counts in step with the bookings."""

import uuid
from datetime import UTC, date, datetime, time
from decimal import Decimal
from typing import Any
from uuid import UUID

from app.core.errors import ConflictError, UnprocessableError
from app.db.booking_repository import ALREADY_BOOKED, SLOT_FULL
from app.domain import booking as rules
from app.domain.enums import BookingStatus, VehicleType
from app.schemas.booking import BookingChargeOut, BookingRecord
from tests.fakes_catalog import FakeAvailabilityRepository

LOCKED = {
    "customer_id",
    "service_id",
    "package_id",
    "vehicle_type",
    "service_name",
    "package_name",
    "package_inclusions",
    "estimated_duration_minutes",
    "package_price",
    "extra_charges_total",
    "customer_name",
    "customer_phone",
}


class FakeBookingRepository:
    def __init__(self, availability: FakeAvailabilityRepository) -> None:
        self.availability = availability
        self.rows: dict[UUID, dict[str, Any]] = {}
        self.charges: dict[UUID, list[BookingChargeOut]] = {}
        self._next_number = 1
        self.create_calls = 0
        # Called with the booking id whenever a booking becomes cancelled (the database does
        # this with a trigger that closes or flags the booking's payments).
        self.on_cancelled: list = []
        # Called as (booking_id, old_status_or_None, new_status) whenever a booking's status
        # changes (the database records history and notifications with triggers).
        self.on_status: list = []

    # ---- helpers -----------------------------------------------------------------------
    def emit_status(self, booking_id: UUID, old: BookingStatus | None, new: BookingStatus) -> None:
        for hook in self.on_status:
            hook(booking_id, old, new)

    def _record(self, row: dict[str, Any]) -> BookingRecord:
        data = dict(row)
        data["extra_charges"] = self.charges.get(row["id"], [])
        data["total_amount"] = row["package_price"] + row["extra_charges_total"]
        return BookingRecord.model_validate(data)

    def _sync_counts(self) -> None:
        counts: dict[tuple[date, time, time], int] = {}
        for r in self.rows.values():
            if r["status"] != BookingStatus.CANCELLED:
                key = (r["scheduled_date"], r["slot_start"], r["slot_end"])
                counts[key] = counts.get(key, 0) + 1
        self.availability.booked = counts

    def _capacity(self, day: date, start: time, end: time) -> int | None:
        slot = next(
            (
                s
                for s in self.availability.slots.values()
                if (s.start_time, s.end_time) == (start, end)
            ),
            None,
        )
        if slot is None:
            return None
        for e in self.availability.exceptions.values():
            if e.exception_date == day and e.time_slot_id == slot.id and e.is_open and e.capacity:
                return e.capacity
        return slot.capacity

    def _check_capacity(self, row: dict[str, Any], ignore: UUID | None = None) -> None:
        cap = self._capacity(row["scheduled_date"], row["slot_start"], row["slot_end"])
        if cap is None:
            return
        used = sum(
            1
            for r in self.rows.values()
            if r["id"] != ignore
            and r["status"] != BookingStatus.CANCELLED
            and (r["scheduled_date"], r["slot_start"], r["slot_end"])
            == (row["scheduled_date"], row["slot_start"], row["slot_end"])
        )
        if used >= cap:
            raise ConflictError(SLOT_FULL)

    # ---- repository API ----------------------------------------------------------------
    def create(self, values: dict[str, Any], charges: list[dict[str, Any]]) -> BookingRecord:
        self.create_calls += 1
        customer = UUID(values["customer_id"])
        request = values.get("client_request_id")
        if request:
            for r in self.rows.values():
                if r["customer_id"] == customer and str(r.get("client_request_id")) == request:
                    return self._record(r)
        row = {
            "id": uuid.uuid4(),
            "booking_number": self._next_number,
            "customer_id": customer,
            "service_id": UUID(values["service_id"]),
            "package_id": UUID(values["package_id"]),
            "vehicle_type": VehicleType(values["vehicle_type"]),
            "status": BookingStatus.PENDING_PAYMENT,
            "customer_name": values["customer_name"],
            "customer_phone": values["customer_phone"],
            "address_line": values["address_line"],
            "landmark": values.get("landmark"),
            "city": values["city"],
            "state": values.get("state"),
            "pincode": values["pincode"],
            "service_area_id": UUID(values["service_area_id"])
            if values.get("service_area_id")
            else None,
            "latitude": values.get("latitude"),
            "longitude": values.get("longitude"),
            "scheduled_date": date.fromisoformat(values["scheduled_date"]),
            "slot_start": time.fromisoformat(values["slot_start"]),
            "slot_end": time.fromisoformat(values["slot_end"]),
            "service_name": values["service_name"],
            "package_name": values["package_name"],
            "package_inclusions": values["package_inclusions"],
            "estimated_duration_minutes": values.get("estimated_duration_minutes"),
            "package_price": Decimal(values["package_price"]),
            "extra_charges_total": sum(
                (Decimal(c["amount"]) for c in charges if c["included_in_total"]),
                Decimal("0"),
            ),
            "customer_notes": values.get("customer_notes"),
            "vehicle_registration": values.get("vehicle_registration"),
            "vehicle_make": values.get("vehicle_make"),
            "vehicle_model": values.get("vehicle_model"),
            "vehicle_nickname": values.get("vehicle_nickname"),
            "cancellation_reason": None,
            "cancelled_by": None,
            "client_request_id": UUID(request) if request else None,
            "confirmed_at": None,
            "completed_at": None,
            "cancelled_at": None,
            "created_at": datetime.now(UTC),
            "updated_at": datetime.now(UTC),
        }
        self._check_unique(row)
        self._check_capacity(row)
        self._next_number += 1
        self.rows[row["id"]] = row
        self.charges[row["id"]] = [
            BookingChargeOut(
                id=uuid.uuid4(),
                extra_charge_id=UUID(c["extra_charge_id"]) if c.get("extra_charge_id") else None,
                charge_type=c["charge_type"],
                name=c["name"],
                amount=c["amount"],
                included_in_total=c["included_in_total"],
            )
            for c in charges
        ]
        self._sync_counts()
        self.emit_status(row["id"], None, BookingStatus.PENDING_PAYMENT)
        return self._record(row)

    def _check_unique(self, row: dict[str, Any], ignore: UUID | None = None) -> None:
        for r in self.rows.values():
            if (
                r["id"] != ignore
                and r["status"] != BookingStatus.CANCELLED
                and r["customer_id"] == row["customer_id"]
                and (r["scheduled_date"], r["slot_start"], r["slot_end"])
                == (row["scheduled_date"], row["slot_start"], row["slot_end"])
            ):
                raise ConflictError(ALREADY_BOOKED)

    def get(self, booking_id: UUID) -> BookingRecord | None:
        row = self.rows.get(booking_id)
        return self._record(row) if row else None

    def get_many(self, booking_ids: list[UUID]) -> list[BookingRecord]:
        return [self._record(self.rows[i]) for i in booking_ids if i in self.rows]

    def find_by_request(self, customer_id: UUID, request_id: UUID) -> BookingRecord | None:
        for r in self.rows.values():
            if r["customer_id"] == customer_id and r.get("client_request_id") == request_id:
                return self._record(r)
        return None

    def list_for_customer(self, customer_id, *, statuses, limit, offset):
        return self.search(statuses=statuses, customer_id=customer_id, limit=limit, offset=offset)

    def search(
        self,
        *,
        statuses=None,
        vehicle_type=None,
        date_from=None,
        date_to=None,
        pincode=None,
        customer_id=None,
        query=None,
        limit,
        offset,
    ):
        rows = list(self.rows.values())
        if customer_id is not None:
            rows = [r for r in rows if r["customer_id"] == customer_id]
        if statuses:
            rows = [r for r in rows if r["status"] in statuses]
        if vehicle_type is not None:
            rows = [r for r in rows if r["vehicle_type"] == vehicle_type]
        if date_from is not None:
            rows = [r for r in rows if r["scheduled_date"] >= date_from]
        if date_to is not None:
            rows = [r for r in rows if r["scheduled_date"] <= date_to]
        if pincode is not None:
            rows = [r for r in rows if r["pincode"] == pincode]
        if query:
            q = query.strip().lower()
            digits = q.replace(" ", "").replace("-", "").removeprefix("ff")
            rows = [
                r
                for r in rows
                if q in r["customer_name"].lower()
                or (digits.isdigit() and str(int(digits)) == str(r["booking_number"]))
                or (digits.isdigit() and len(digits) >= 4 and digits in r["customer_phone"])
            ]
        rows.sort(key=lambda r: (r["created_at"], r["booking_number"]), reverse=True)
        total = len(rows)
        page = rows[offset : offset + limit]
        return [self._record(r) for r in page], total

    def update(self, booking_id, values, *, only_statuses=None):
        row = self.rows.get(booking_id)
        if row is None or (only_statuses and row["status"] not in only_statuses):
            return None
        if row["status"] in rules.FINAL_STATUSES:
            raise UnprocessableError("A finished booking cannot be changed")
        new = dict(row)
        for key, value in values.items():
            if key in LOCKED:
                raise UnprocessableError("The booked service, price and customer cannot be changed")
            if key in ("scheduled_date",) and isinstance(value, str):
                value = date.fromisoformat(value)
            if key in ("slot_start", "slot_end") and isinstance(value, str):
                value = time.fromisoformat(value)
            if key == "status":
                value = BookingStatus(value)
                if not rules.can_transition(row["status"], value):
                    raise UnprocessableError("Illegal status change")
            if key in ("cancelled_by", "service_area_id") and isinstance(value, str):
                value = UUID(value)
            if key in ("cancelled_at", "confirmed_at") and isinstance(value, str):
                value = datetime.fromisoformat(value)
            new[key] = value
        if (new["scheduled_date"], new["slot_start"], new["slot_end"]) != (
            row["scheduled_date"],
            row["slot_start"],
            row["slot_end"],
        ):
            self._check_unique(new, ignore=booking_id)
            self._check_capacity(new, ignore=booking_id)
        new["updated_at"] = datetime.now(UTC)
        self.rows[booking_id] = new
        self._sync_counts()
        if new["status"] != row["status"]:
            self.emit_status(booking_id, row["status"], new["status"])
        if new["status"] == BookingStatus.CANCELLED and row["status"] != BookingStatus.CANCELLED:
            for hook in self.on_cancelled:
                hook(booking_id)
        return self._record(new)

    def confirm_paid(self, booking_id: UUID) -> None:
        """What `apply_payment_event` does to a booking when a payment is verified."""
        old = self.rows[booking_id]["status"]
        self.rows[booking_id]["status"] = BookingStatus.CONFIRMED
        self.rows[booking_id]["confirmed_at"] = datetime.now(UTC)
        if old != BookingStatus.CONFIRMED:
            self.emit_status(booking_id, old, BookingStatus.CONFIRMED)

    # ---- test helper -------------------------------------------------------------------
    def force_status(self, booking_id: UUID, status: BookingStatus) -> None:
        """Puts a booking into a status the Phase 4 API cannot reach (driver/payment phases)."""
        old = self.rows[booking_id]["status"]
        self.rows[booking_id]["status"] = status
        if status == BookingStatus.COMPLETED:
            self.rows[booking_id]["completed_at"] = datetime.now(UTC)
        self._sync_counts()
        if old != status:
            self.emit_status(booking_id, old, status)
