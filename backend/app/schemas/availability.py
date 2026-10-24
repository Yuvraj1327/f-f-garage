"""Time slots, date exceptions and the computed availability customers see."""

from datetime import date, datetime, time
from typing import Annotated
from uuid import UUID

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator

from app.schemas.common import PatchModel, optional_text

Capacity = Annotated[int, Field(ge=1, le=50)]
Reason = Annotated[str | None, optional_text(200)]


def _clean_days(days: list[int]) -> list[int]:
    cleaned = sorted(set(days))
    if not cleaned:
        raise ValueError("Choose at least one day of the week")
    if cleaned[0] < 1 or cleaned[-1] > 7:
        raise ValueError("Days of the week are numbered 1 (Monday) to 7 (Sunday)")
    return cleaned


DaysOfWeek = Annotated[list[int], AfterValidator(_clean_days)]


def _whole_minutes(value: time) -> time:
    if value.second or value.microsecond:
        raise ValueError("Use whole minutes (for example 09:30)")
    return value


SlotTime = Annotated[time, AfterValidator(_whole_minutes)]


# ---- Time slots ------------------------------------------------------------------------


class TimeSlotCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    start_time: SlotTime
    end_time: SlotTime
    capacity: Capacity = 1
    days_of_week: DaysOfWeek = Field(default_factory=lambda: [1, 2, 3, 4, 5, 6, 7])
    is_active: bool = True

    @model_validator(mode="after")
    def _end_after_start(self) -> "TimeSlotCreate":
        if self.end_time <= self.start_time:
            raise ValueError("The slot must end after it starts")
        return self


class TimeSlotUpdate(PatchModel):
    start_time: SlotTime | None = None
    end_time: SlotTime | None = None
    capacity: Capacity | None = None
    days_of_week: DaysOfWeek | None = None
    is_active: bool | None = None


class TimeSlotOut(BaseModel):
    id: UUID
    start_time: time
    end_time: time
    capacity: int
    days_of_week: list[int]
    is_active: bool
    created_at: datetime
    updated_at: datetime


# ---- Exceptions ------------------------------------------------------------------------


class ExceptionCreate(BaseModel):
    """A date-specific change to the weekly routine.

    - no `time_slot_id`            -> the whole day is closed
    - `time_slot_id`, is_open=false -> that slot is closed on the date
    - `time_slot_id`, is_open=true  -> that slot runs on the date even if it normally
                                       does not; `capacity` optionally overrides its capacity
    """

    model_config = ConfigDict(extra="forbid")

    exception_date: date
    time_slot_id: UUID | None = None
    is_open: bool = False
    capacity: Capacity | None = None
    reason: Reason = None

    @model_validator(mode="after")
    def _consistent(self) -> "ExceptionCreate":
        if self.time_slot_id is None and self.is_open:
            raise ValueError("A whole day can only be closed, not opened")
        if self.capacity is not None and not self.is_open:
            raise ValueError("Capacity can only be set when the slot is open")
        return self


class ExceptionUpdate(PatchModel):
    """Date and slot are fixed (delete and re-add to move an exception)."""

    nullable = frozenset({"capacity", "reason"})

    is_open: bool | None = None
    capacity: Capacity | None = None
    reason: Reason = None


class ExceptionOut(BaseModel):
    id: UUID
    exception_date: date
    time_slot_id: UUID | None = None
    is_open: bool
    capacity: int | None = None
    reason: str | None = None
    created_at: datetime
    updated_at: datetime


# ---- Computed availability -------------------------------------------------------------


class SlotAvailability(BaseModel):
    slot_id: UUID
    start_time: time
    end_time: time
    available: bool
    # Why it cannot be booked: lead_time_passed | fully_booked
    reason: str | None = None
    spots_left: int


class DayAvailability(BaseModel):
    date: date
    is_open: bool
    # Why the whole day is unavailable: past_date | outside_booking_window | closed | no_slots
    closed_reason: str | None = None
    # Customer-facing note from the admin (e.g. "Closed for Diwali").
    note: str | None = None
    slots: list[SlotAvailability] = Field(default_factory=list)
