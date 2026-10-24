"""Time slots, date exceptions and the availability customers see."""

import logging
from collections.abc import Callable
from datetime import date, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from app.core.config import Settings
from app.core.errors import ConflictError, NotFoundError, UnprocessableError
from app.db.availability_repository import AvailabilityRepository
from app.domain.availability import ExceptionRule, SlotRule, compute_day
from app.schemas.availability import (
    DayAvailability,
    ExceptionCreate,
    ExceptionOut,
    ExceptionUpdate,
    TimeSlotCreate,
    TimeSlotOut,
    TimeSlotUpdate,
)
from app.schemas.profile import ProfileOut

logger = logging.getLogger(__name__)

MAX_RANGE_DAYS = 31


class AvailabilityService:
    def __init__(
        self,
        repo: AvailabilityRepository,
        settings: Settings,
        clock: Callable[[ZoneInfo], datetime] | None = None,
    ) -> None:
        self._repo = repo
        self._settings = settings
        self._tz = ZoneInfo(settings.business_timezone)
        self._clock = clock or (lambda tz: datetime.now(tz))

    def _now(self) -> datetime:
        return self._clock(self._tz)

    # ---- What customers see ------------------------------------------------------------
    def get_availability(self, start: date, end: date | None = None) -> list[DayAvailability]:
        end = end or start
        if end < start:
            raise UnprocessableError("The end date must not be before the start date")
        if (end - start).days + 1 > MAX_RANGE_DAYS:
            raise UnprocessableError(f"Ask for at most {MAX_RANGE_DAYS} days at a time")

        now = self._now()
        slots = [
            SlotRule(s.id, s.start_time, s.end_time, s.capacity, frozenset(s.days_of_week))
            for s in self._repo.list_slots(active_only=True)
        ]
        exceptions: dict[date, list[ExceptionRule]] = {}
        for e in self._repo.list_exceptions(start, end):
            exceptions.setdefault(e.exception_date, []).append(
                ExceptionRule(e.time_slot_id, e.is_open, e.capacity, e.reason)
            )
        counts = self._repo.booked_counts(start, end)

        days: list[DayAvailability] = []
        for offset in range((end - start).days + 1):
            day = start + timedelta(days=offset)
            booked = {(s, e): n for (d, s, e), n in counts.items() if d == day}
            days.append(
                compute_day(
                    day,
                    now=now,
                    slots=slots,
                    exceptions=exceptions.get(day, []),
                    booked=booked,
                    window_days=self._settings.booking_window_days,
                    lead_minutes=self._settings.booking_lead_minutes,
                )
            )
        return days

    def get_active_slot(self, slot_id: UUID) -> TimeSlotOut:
        """The slot, or 404 when it does not exist or is switched off."""
        slot = self._repo.get_slot(slot_id)
        if slot is None or not slot.is_active:
            raise NotFoundError("Time slot not found")
        return slot

    def ensure_bookable(self, day: date, slot_id: UUID) -> TimeSlotOut:
        """For the booking workflow: raises unless `slot_id` can be booked on `day`.

        404 for a slot that does not exist or is inactive, 409 when it exists but
        cannot be booked (past, closed, full, too soon, outside the window).
        """
        slot = self._repo.get_slot(slot_id)
        if slot is None or not slot.is_active:
            raise NotFoundError("Time slot not found")
        availability = self.get_availability(day)[0]
        match = next((s for s in availability.slots if s.slot_id == slot_id), None)
        if match is None or not match.available:
            raise ConflictError("That time slot is not available on the chosen date")
        return slot

    # ---- Admin: time slots -------------------------------------------------------------
    def list_slots(self) -> list[TimeSlotOut]:
        return self._repo.list_slots()

    def create_slot(self, admin: ProfileOut, payload: TimeSlotCreate) -> TimeSlotOut:
        slot = self._repo.create_slot(payload.model_dump(mode="json"))
        logger.info("admin %s created time slot %s", admin.id, slot.id)
        return slot

    def update_slot(self, admin: ProfileOut, slot_id: UUID, payload: TimeSlotUpdate) -> TimeSlotOut:
        current = self._require_slot(slot_id)
        values = payload.to_update_values()

        start = payload.start_time if "start_time" in payload.model_fields_set else None
        end = payload.end_time if "end_time" in payload.model_fields_set else None
        new_start = start or current.start_time
        new_end = end or current.end_time
        if new_end <= new_start:
            raise UnprocessableError("The slot must end after it starts")
        if (new_start, new_end) != (current.start_time, current.end_time):
            self._refuse_if_upcoming_bookings(current, "change the times of")

        updated = self._repo.update_slot(slot_id, values)
        if updated is None:
            raise NotFoundError("Time slot not found")
        logger.info("admin %s updated time slot %s", admin.id, slot_id)
        return updated

    def delete_slot(self, admin: ProfileOut, slot_id: UUID) -> None:
        current = self._require_slot(slot_id)
        self._refuse_if_upcoming_bookings(current, "delete")
        if not self._repo.delete_slot(slot_id):
            raise NotFoundError("Time slot not found")
        logger.info("admin %s deleted time slot %s", admin.id, slot_id)

    # ---- Admin: exceptions -------------------------------------------------------------
    def list_exceptions(self, start: date, end: date) -> list[ExceptionOut]:
        if end < start:
            raise UnprocessableError("The end date must not be before the start date")
        if (end - start).days > 366:
            raise UnprocessableError("Ask for at most a year at a time")
        return self._repo.list_exceptions(start, end)

    def create_exception(self, admin: ProfileOut, payload: ExceptionCreate) -> ExceptionOut:
        if payload.exception_date < self._now().date():
            raise UnprocessableError("The date is in the past")
        if payload.time_slot_id is not None:
            self._require_slot(payload.time_slot_id)
        exception = self._repo.create_exception(payload.model_dump(mode="json"))
        logger.info(
            "admin %s created availability exception %s for %s",
            admin.id,
            exception.id,
            exception.exception_date,
        )
        return exception

    def update_exception(
        self, admin: ProfileOut, exception_id: UUID, payload: ExceptionUpdate
    ) -> ExceptionOut:
        current = self._repo.get_exception(exception_id)
        if current is None:
            raise NotFoundError("Entry not found")
        is_open = payload.is_open if "is_open" in payload.model_fields_set else current.is_open
        capacity = payload.capacity if "capacity" in payload.model_fields_set else current.capacity
        if current.time_slot_id is None and is_open:
            raise UnprocessableError("A whole day can only be closed, not opened")
        values = payload.to_update_values()
        if not is_open:
            # A closure carries no capacity; clear it rather than fail on the constraint.
            if "capacity" in payload.model_fields_set and capacity is not None:
                raise UnprocessableError("Capacity can only be set when the slot is open")
            values["capacity"] = None
        updated = self._repo.update_exception(exception_id, values)
        if updated is None:
            raise NotFoundError("Entry not found")
        logger.info("admin %s updated availability exception %s", admin.id, exception_id)
        return updated

    def delete_exception(self, admin: ProfileOut, exception_id: UUID) -> None:
        if not self._repo.delete_exception(exception_id):
            raise NotFoundError("Entry not found")
        logger.info("admin %s deleted availability exception %s", admin.id, exception_id)

    # ---- Helpers -----------------------------------------------------------------------
    def _require_slot(self, slot_id: UUID) -> TimeSlotOut:
        slot = self._repo.get_slot(slot_id)
        if slot is None:
            raise NotFoundError("Time slot not found")
        return slot

    def _refuse_if_upcoming_bookings(self, slot: TimeSlotOut, verb: str) -> None:
        """Bookings identify their slot by its start/end time, so a slot that upcoming
        bookings use must keep those times (deactivate it instead)."""
        today = self._now().date()
        counts = self._repo.booked_counts(today, today + timedelta(days=366))
        used = sum(
            n
            for (_day, start, end), n in counts.items()
            if (start, end) == (slot.start_time, slot.end_time)
        )
        if used:
            raise ConflictError(
                f"{used} upcoming booking(s) use this slot, so you cannot {verb} it. "
                "Deactivate it instead."
            )
