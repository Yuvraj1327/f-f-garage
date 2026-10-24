"""Pure rules that decide which slots can be booked on a date.

No database, no clock, no HTTP: everything is passed in, so each rule is unit
tested directly. `AvailabilityService` gathers the inputs and calls this.

A slot on a date is bookable when, in this order of precedence:
  1. the date is today or later, and within the booking window
  2. the whole day is not closed by an exception
  3. the slot runs that weekday (or an exception opens it for that date)
  4. the slot is not closed by an exception
  5. it starts at least `lead_minutes` from now
  6. it still has capacity (capacity - active bookings > 0)
"""

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from uuid import UUID

from app.schemas.availability import DayAvailability, SlotAvailability

# Day-level reasons
PAST_DATE = "past_date"
OUTSIDE_WINDOW = "outside_booking_window"
CLOSED = "closed"
NO_SLOTS = "no_slots"
UNAVAILABLE = "unavailable"
# Slot-level reasons
LEAD_TIME_PASSED = "lead_time_passed"
FULLY_BOOKED = "fully_booked"


@dataclass(frozen=True)
class SlotRule:
    id: UUID
    start_time: time
    end_time: time
    capacity: int
    days_of_week: frozenset[int]


@dataclass(frozen=True)
class ExceptionRule:
    time_slot_id: UUID | None
    is_open: bool
    capacity: int | None
    reason: str | None


def compute_day(
    day: date,
    *,
    now: datetime,
    slots: list[SlotRule],
    exceptions: list[ExceptionRule],
    booked: dict[tuple[time, time], int],
    window_days: int,
    lead_minutes: int,
) -> DayAvailability:
    """`now` must be timezone-aware, in the business time zone. `slots` are the
    ACTIVE slots; `exceptions` those that fall on `day`; `booked` maps
    (start, end) to the number of non-cancelled bookings on `day`."""
    today = now.date()
    if day < today:
        return DayAvailability(date=day, is_open=False, closed_reason=PAST_DATE)
    if day > today + timedelta(days=window_days):
        return DayAvailability(date=day, is_open=False, closed_reason=OUTSIDE_WINDOW)

    whole_day = next((e for e in exceptions if e.time_slot_id is None), None)
    if whole_day is not None:
        return DayAvailability(date=day, is_open=False, closed_reason=CLOSED, note=whole_day.reason)

    by_slot = {e.time_slot_id: e for e in exceptions if e.time_slot_id is not None}
    results: list[SlotAvailability] = []
    note: str | None = None
    for slot in sorted(slots, key=lambda s: (s.start_time, s.end_time)):
        exception = by_slot.get(slot.id)
        runs_today = day.isoweekday() in slot.days_of_week
        force_open = exception is not None and exception.is_open
        if not runs_today and not force_open:
            continue

        capacity = slot.capacity
        if force_open and exception is not None and exception.capacity:
            capacity = exception.capacity
        spots_left = max(capacity - booked.get((slot.start_time, slot.end_time), 0), 0)

        reason: str | None = None
        if exception is not None and not exception.is_open:
            reason = CLOSED
            note = note or exception.reason
            spots_left = 0
        elif datetime.combine(day, slot.start_time, tzinfo=now.tzinfo) - now < timedelta(
            minutes=lead_minutes
        ):
            reason = LEAD_TIME_PASSED
        elif spots_left == 0:
            reason = FULLY_BOOKED

        results.append(
            SlotAvailability(
                slot_id=slot.id,
                start_time=slot.start_time,
                end_time=slot.end_time,
                available=reason is None,
                reason=reason,
                spots_left=spots_left,
            )
        )

    if not results:
        return DayAvailability(date=day, is_open=False, closed_reason=NO_SLOTS)
    is_open = any(slot.available for slot in results)
    return DayAvailability(
        date=day,
        is_open=is_open,
        closed_reason=None if is_open else UNAVAILABLE,
        note=note,
        slots=results,
    )
