"""In-memory booking history and notifications.

The database writes these with triggers (migration 11, tested on a real PostgreSQL in
supabase/tests/07_tracking_and_notifications_test.sql). Here the other fakes call hooks at
the same moments, and this class records what the triggers would: the same events and the
same notification kinds and wording.
"""

import uuid
from datetime import UTC, datetime
from uuid import UUID

from app.domain import booking as rules
from app.domain.enums import BookingStatus
from app.schemas.tracking import NotificationKind, NotificationRecord, TimelineEvent
from tests.fakes import FakeProfileRepository
from tests.fakes_assignment import FakeAssignmentRepository
from tests.fakes_booking import FakeBookingRepository
from tests.fakes_payment import FakePaymentRepository

S = BookingStatus
K = NotificationKind


class FakeTracking:
    """Implements both TrackingRepository and NotificationRepository."""

    def __init__(
        self,
        bookings: FakeBookingRepository,
        assignments: FakeAssignmentRepository,
        payments: FakePaymentRepository,
        profiles: FakeProfileRepository,
    ) -> None:
        self.bookings = bookings
        self.profiles = profiles
        self.events: list[tuple[UUID, BookingStatus, datetime]] = []
        self.notes: list[NotificationRecord] = []
        self.calls: list[tuple] = []
        bookings.on_status.append(self._status)
        assignments.on_assigned.append(self._assigned)
        payments.on_failed.append(self._payment_failed)

    # ---- the triggers ------------------------------------------------------------------
    def _label(self, booking_id: UUID) -> str:
        row = self.bookings.rows[booking_id]
        return f"{rules.booking_code(row['booking_number'])} ({row['service_name']})"

    def _notify(self, booking_id: UUID, kind: K, title: str, body: str) -> None:
        row = self.bookings.rows[booking_id]
        self.notes.append(
            NotificationRecord(
                id=uuid.uuid4(),
                user_id=row["customer_id"],
                booking_id=booking_id,
                kind=kind,
                title=title,
                body=body,
                created_at=datetime.now(UTC),
                booking_number=row["booking_number"],
            )
        )

    def _status(self, booking_id: UUID, old: BookingStatus | None, new: BookingStatus) -> None:
        self.events.append((booking_id, new, datetime.now(UTC)))
        if old is None:
            return
        label = self._label(booking_id)
        if new == S.CONFIRMED and old == S.PENDING_PAYMENT:
            self._notify(
                booking_id,
                K.BOOKING_CONFIRMED,
                "Booking confirmed",
                f"Payment received for {label}. We will assign a driver soon.",
            )
        elif new == S.CONFIRMED and old == S.ASSIGNED:
            self._notify(
                booking_id,
                K.DRIVER_REMOVED,
                "Driver being arranged",
                f"The driver for {label} was removed. We are arranging another driver.",
            )
        elif new == S.ON_THE_WAY:
            self._notify(
                booking_id,
                K.DRIVER_ON_THE_WAY,
                "Your driver is on the way",
                f"Your driver is on the way for {label}.",
            )
        elif new == S.IN_PROGRESS:
            self._notify(
                booking_id,
                K.SERVICE_STARTED,
                "Service started",
                f"The service for {label} has started.",
            )
        elif new == S.COMPLETED:
            self._notify(
                booking_id,
                K.SERVICE_COMPLETED,
                "Service completed",
                f"The service for {label} is complete. Thank you for choosing F&F Garage.",
            )
        elif new == S.CANCELLED:
            self._notify(
                booking_id, K.BOOKING_CANCELLED, "Booking cancelled", f"{label} was cancelled."
            )

    def _assigned(self, booking_id: UUID, driver_id: UUID, earlier: bool) -> None:
        driver = self.profiles.rows.get(str(driver_id))
        name = (driver.full_name or "").strip() if driver else ""
        name = name or "A driver"
        label = self._label(booking_id)
        if earlier:
            self._notify(
                booking_id, K.DRIVER_CHANGED, "Driver changed", f"{name} will now do {label}."
            )
        else:
            self._notify(
                booking_id, K.DRIVER_ASSIGNED, "Driver assigned", f"{name} is assigned to {label}."
            )

    def _payment_failed(self, booking_id: UUID) -> None:
        if self.bookings.rows[booking_id]["status"] == S.PENDING_PAYMENT:
            self._notify(
                booking_id,
                K.PAYMENT_FAILED,
                "Payment failed",
                f"Your payment for {self._label(booking_id)} did not go through. "
                "You can try again from the booking.",
            )

    # ---- TrackingRepository ------------------------------------------------------------
    def timeline(self, booking_id: UUID) -> list[TimelineEvent]:
        return [TimelineEvent(status=s, at=at) for b, s, at in self.events if b == booking_id]

    # ---- NotificationRepository --------------------------------------------------------
    def list_for_user(self, user_id: UUID, *, unread_only: bool, limit: int, offset: int):
        self.calls.append(("list", user_id, unread_only))
        mine = [n for n in reversed(self.notes) if n.user_id == user_id]
        if unread_only:
            mine = [n for n in mine if n.read_at is None]
        return mine[offset : offset + limit], len(mine)

    def unread_count(self, user_id: UUID) -> int:
        return sum(1 for n in self.notes if n.user_id == user_id and n.read_at is None)

    def mark_read(self, user_id: UUID, ids: list[UUID] | None) -> int:
        self.calls.append(("mark_read", user_id, ids))
        count = 0
        for i, n in enumerate(self.notes):
            if n.user_id == user_id and n.read_at is None and (ids is None or n.id in ids):
                self.notes[i] = n.model_copy(update={"read_at": datetime.now(UTC)})
                count += 1
        return count
