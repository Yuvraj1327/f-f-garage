"""Driver assignment and driver-side booking shapes."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, field_validator

from app.domain import booking as rules
from app.domain.enums import BookingStatus


class AssignRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    driver_id: UUID


class DriverStatusUpdate(BaseModel):
    """A driver's status step. Drivers can only report these three."""

    model_config = ConfigDict(extra="forbid")

    status: BookingStatus

    @field_validator("status")
    @classmethod
    def _driver_target(cls, value: BookingStatus) -> BookingStatus:
        if value not in rules.DRIVER_TARGETS:
            allowed = ", ".join(sorted(s.value for s in rules.DRIVER_TARGETS))
            raise ValueError(f"A driver can only set: {allowed}")
        return value


class AssignmentRecord(BaseModel):
    """A row of driver_assignments."""

    id: UUID
    booking_id: UUID
    driver_id: UUID
    assigned_by: UUID
    is_active: bool
    assigned_at: datetime
    unassigned_at: datetime | None = None


class AssignmentResult(BaseModel):
    """What assign_driver / unassign_driver / driver_update_status answered."""

    result: str
    booking_status: BookingStatus | None = None
    assignment_id: UUID | None = None


class DriverSummary(BaseModel):
    """What a customer sees about the driver on their booking."""

    name: str | None = None
    phone: str | None = None


class AdminAssignment(BaseModel):
    """Who is assigned, as shown to an admin."""

    driver_id: UUID
    driver_name: str | None = None
    driver_login_id: str | None = None
    driver_phone: str | None = None
    driver_is_active: bool = True
    assigned_at: datetime
    assigned_by: UUID


class AssignmentHistoryItem(BaseModel):
    id: UUID
    driver_id: UUID
    driver_name: str | None = None
    driver_login_id: str | None = None
    assigned_by: UUID
    assigned_by_name: str | None = None
    assigned_at: datetime
    unassigned_at: datetime | None = None
    is_active: bool
