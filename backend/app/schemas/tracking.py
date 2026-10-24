"""Booking tracking (status history) and the customer's in-app notifications."""

from datetime import datetime
from enum import StrEnum
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.domain.enums import BookingStatus


class NotificationKind(StrEnum):
    """Must match the `notifications_kind_known` constraint in migration 11
    (tests/test_tracking_rules.py checks)."""

    BOOKING_CONFIRMED = "booking_confirmed"
    PAYMENT_FAILED = "payment_failed"
    DRIVER_ASSIGNED = "driver_assigned"
    DRIVER_CHANGED = "driver_changed"
    DRIVER_REMOVED = "driver_removed"
    DRIVER_ON_THE_WAY = "driver_on_the_way"
    SERVICE_STARTED = "service_started"
    SERVICE_COMPLETED = "service_completed"
    BOOKING_CANCELLED = "booking_cancelled"


class TimelineEvent(BaseModel):
    """The booking entered `status` at `at`. Oldest first in a booking's timeline."""

    model_config = ConfigDict(from_attributes=True)

    status: BookingStatus
    at: datetime

    @model_validator(mode="before")
    @classmethod
    def _from_row(cls, data: Any) -> Any:
        if isinstance(data, dict) and "created_at" in data and "at" not in data:
            return {"status": data["status"], "at": data["created_at"]}
        return data


class NotificationRecord(BaseModel):
    """A notification row (with the booking number when it was read with its booking)."""

    id: UUID
    user_id: UUID
    booking_id: UUID | None = None
    kind: NotificationKind
    title: str
    body: str
    created_at: datetime
    read_at: datetime | None = None
    booking_number: int | None = None

    @model_validator(mode="before")
    @classmethod
    def _embedded_booking(cls, data: Any) -> Any:
        if isinstance(data, dict) and isinstance(data.get("bookings"), dict):
            data = {**data, "booking_number": data["bookings"].get("booking_number")}
        return data


class NotificationOut(BaseModel):
    id: UUID
    booking_id: UUID | None = None
    booking_code: str | None = None
    kind: NotificationKind
    title: str
    body: str
    created_at: datetime
    is_read: bool


class NotificationPage(BaseModel):
    items: list[NotificationOut]
    total: int
    unread: int
    limit: int
    offset: int


class MarkReadRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    # Omit (or null) to mark everything read.
    ids: list[UUID] | None = Field(default=None, max_length=200)


class MarkReadResult(BaseModel):
    updated: int
    unread: int


class UnreadCount(BaseModel):
    unread: int
