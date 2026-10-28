"""In-memory driver assignments.

`assign`, `unassign` and `driver_update_status` mirror the SQL functions of migration 10,
which are tested against a real PostgreSQL in supabase/tests/06_driver_assignment_test.sql.
The scenarios in tests/test_assignments_api.py are the same ones.
"""

import uuid
from datetime import UTC, datetime
from uuid import UUID

from app.domain import booking as rules
from app.domain.enums import BookingStatus, PaymentStatus, UserRole
from app.schemas.assignment import AssignmentRecord, AssignmentResult
from tests.fakes import FakeProfileRepository
from tests.fakes_booking import FakeBookingRepository
from tests.fakes_payment import FakePaymentRepository

S = BookingStatus
_OPEN = (S.ASSIGNED, S.ON_THE_WAY, S.IN_PROGRESS)


class FakeAssignmentRepository:
    def __init__(
        self,
        bookings: FakeBookingRepository,
        profiles: FakeProfileRepository,
        payments: FakePaymentRepository,
    ) -> None:
        self.bookings = bookings
        self.profiles = profiles
        self.payments = payments
        # Set by the test context: the "cannot complete with an open extra request" guard.
        self.extras = None
        self.rows: list[AssignmentRecord] = []
        self.rpc_calls: list[tuple[str, tuple]] = []
        # Called as (booking_id, driver_id, had_earlier_assignment) for each new active assignment.
        self.on_assigned: list = []

    # ---- helpers -----------------------------------------------------------------------
    def _active(self, booking_id: UUID) -> AssignmentRecord | None:
        return next((a for a in self.rows if a.booking_id == booking_id and a.is_active), None)

    def _close(self, record: AssignmentRecord) -> None:
        now = datetime.now(UTC)
        self.rows[self.rows.index(record)] = record.model_copy(
            update={"is_active": False, "unassigned_at": now}
        )

    def _set_status(self, booking_id: UUID, status: BookingStatus) -> None:
        row = self.bookings.rows[booking_id]
        old = row["status"]
        row["status"] = status
        if status == S.COMPLETED:
            row["completed_at"] = datetime.now(UTC)
        if old != status:
            self.bookings.emit_status(booking_id, old, status)

    def _paid(self, booking_id: UUID) -> bool:
        return any(
            r.booking_id == booking_id and r.status == PaymentStatus.SUCCESSFUL
            for r in self.payments.rows.values()
        )

    # ---- the SQL functions -------------------------------------------------------------
    def assign(self, booking_id: UUID, driver_id: UUID, admin_id: UUID) -> AssignmentResult:
        self.rpc_calls.append(("assign", (booking_id, driver_id, admin_id)))
        booking = self.bookings.rows.get(booking_id)
        if booking is None:
            return AssignmentResult(result="booking_not_found")
        status = booking["status"]
        driver = self.profiles.rows.get(str(driver_id))
        if driver is None or driver.role != UserRole.DRIVER:
            return AssignmentResult(result="driver_not_found", booking_status=status)
        current = self._active(booking_id)
        if (
            current
            and current.driver_id == driver_id
            and status in (S.ASSIGNED, S.ON_THE_WAY, S.IN_PROGRESS, S.COMPLETED)
        ):
            return AssignmentResult(
                result="unchanged", booking_status=status, assignment_id=current.id
            )
        if not driver.is_active:
            return AssignmentResult(result="driver_inactive", booking_status=status)
        if status not in rules.ADMIN_ASSIGNABLE_STATUSES:
            return AssignmentResult(result="not_assignable", booking_status=status)
        if not self._paid(booking_id):
            return AssignmentResult(result="not_paid", booking_status=status)
        for other in self.rows:
            ob = self.bookings.rows[other.booking_id]
            if (
                other.is_active
                and other.driver_id == driver_id
                and other.booking_id != booking_id
                and ob["status"] in _OPEN
                and ob["scheduled_date"] == booking["scheduled_date"]
                and ob["slot_start"] < booking["slot_end"]
                and ob["slot_end"] > booking["slot_start"]
            ):
                return AssignmentResult(result="driver_busy", booking_status=status)
        if current:
            self._close(current)
        record = AssignmentRecord(
            id=uuid.uuid4(),
            booking_id=booking_id,
            driver_id=driver_id,
            assigned_by=admin_id,
            is_active=True,
            assigned_at=datetime.now(UTC),
        )
        earlier = any(a.booking_id == booking_id for a in self.rows)
        self.rows.append(record)
        for hook in self.on_assigned:
            hook(booking_id, driver_id, earlier)
        if status == S.CONFIRMED:
            self._set_status(booking_id, S.ASSIGNED)
            return AssignmentResult(
                result="assigned", booking_status=S.ASSIGNED, assignment_id=record.id
            )
        return AssignmentResult(result="reassigned", booking_status=status, assignment_id=record.id)

    def unassign(self, booking_id: UUID, admin_id: UUID) -> AssignmentResult:
        self.rpc_calls.append(("unassign", (booking_id, admin_id)))
        booking = self.bookings.rows.get(booking_id)
        if booking is None:
            return AssignmentResult(result="booking_not_found")
        current = self._active(booking_id)
        if booking["status"] == S.CONFIRMED and current is None:
            return AssignmentResult(result="unchanged", booking_status=booking["status"])
        if booking["status"] != S.ASSIGNED:
            return AssignmentResult(result="not_unassignable", booking_status=booking["status"])
        if current:
            self._close(current)
        self._set_status(booking_id, S.CONFIRMED)
        return AssignmentResult(result="unassigned", booking_status=S.CONFIRMED)

    def driver_update_status(
        self, booking_id: UUID, driver_id: UUID, status: BookingStatus
    ) -> AssignmentResult:
        self.rpc_calls.append(("driver_update_status", (booking_id, driver_id, status)))
        booking = self.bookings.rows.get(booking_id)
        if booking is None:
            return AssignmentResult(result="booking_not_found")
        if not self.is_assigned(booking_id, driver_id):
            return AssignmentResult(result="not_assigned")
        driver = self.profiles.rows.get(str(driver_id))
        current = booking["status"]
        if driver is None or not driver.is_active:
            return AssignmentResult(result="driver_inactive", booking_status=current)
        if current == status:
            return AssignmentResult(result="unchanged", booking_status=current)
        if current == S.CANCELLED:
            return AssignmentResult(result="booking_cancelled", booking_status=current)
        if rules.DRIVER_STEPS.get(current) != status:
            return AssignmentResult(result="invalid_transition", booking_status=current)
        if (
            status == S.COMPLETED
            and self.extras is not None
            and any(e.status == "proposed" for e in self.extras.list_for_booking(booking_id))
        ):
            return AssignmentResult(result="extras_pending", booking_status=current)
        self._set_status(booking_id, status)
        return AssignmentResult(result="updated", booking_status=status)

    # ---- reads -------------------------------------------------------------------------
    def active_for_bookings(self, booking_ids: list[UUID]) -> dict[UUID, AssignmentRecord]:
        wanted = set(booking_ids)
        return {a.booking_id: a for a in self.rows if a.is_active and a.booking_id in wanted}

    def is_assigned(self, booking_id: UUID, driver_id: UUID) -> bool:
        a = self._active(booking_id)
        return a is not None and a.driver_id == driver_id

    def history(self, booking_id: UUID) -> list[AssignmentRecord]:
        rows = [a for a in self.rows if a.booking_id == booking_id]
        return sorted(rows, key=lambda a: a.assigned_at, reverse=True)

    def driver_booking_ids(
        self, driver_id: UUID, scope: str, limit: int, offset: int
    ) -> tuple[list[UUID], int]:
        statuses = _OPEN if scope == "open" else (S.COMPLETED, S.CANCELLED)
        mine = [
            self.bookings.rows[a.booking_id]
            for a in self.rows
            if a.is_active
            and a.driver_id == driver_id
            and self.bookings.rows[a.booking_id]["status"] in statuses
        ]
        key = lambda r: (r["scheduled_date"], r["slot_start"], r["booking_number"])  # noqa: E731
        if scope == "open":
            mine.sort(key=key)
        else:
            mine.sort(key=lambda r: (r["scheduled_date"], r["slot_start"]), reverse=True)
        return [r["id"] for r in mine[offset : offset + limit]], len(mine)

    def open_counts(self) -> dict[UUID, int]:
        counts: dict[UUID, int] = {}
        for a in self.rows:
            if a.is_active and self.bookings.rows[a.booking_id]["status"] in _OPEN:
                counts[a.driver_id] = counts.get(a.driver_id, 0) + 1
        return counts
