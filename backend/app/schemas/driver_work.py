"""What a driver sees of the bookings assigned to them."""

from datetime import date, time
from uuid import UUID

from pydantic import BaseModel

from app.domain.enums import BookingStatus, VehicleType
from app.schemas.booking import BookingChargeOut


class DriverBookingOut(BaseModel):
    """A booking as its driver sees it: what to do, where and when. No prices or payments."""

    id: UUID
    booking_number: int
    booking_code: str
    status: BookingStatus
    vehicle_type: VehicleType
    service_name: str
    package_name: str
    package_inclusions: list[str]
    estimated_duration_minutes: int | None = None
    customer_name: str
    customer_phone: str
    address_line: str
    landmark: str | None = None
    city: str
    state: str | None = None
    pincode: str
    latitude: float | None = None
    longitude: float | None = None
    scheduled_date: date
    slot_start: time
    slot_end: time
    customer_notes: str | None = None
    extra_charges: list[BookingChargeOut]
    # The one step the driver may take now (null when there is none).
    next_status: BookingStatus | None = None


class DriverBookingPage(BaseModel):
    items: list[DriverBookingOut]
    total: int
    limit: int
    offset: int
