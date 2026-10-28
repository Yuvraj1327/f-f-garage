"""Booking request and response shapes.

Requests never carry a price: the backend reads prices from the catalogue. The
optional `expected_total` is only a safety check ("the price I was shown") and is
never used as the price.
"""

from datetime import date, datetime, time
from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated, Any
from uuid import UUID

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator

from app.domain.enums import BookingStatus, ExtraChargeType, VehicleType
from app.schemas.assignment import AdminAssignment, DriverSummary
from app.schemas.common import Money, PatchModel, optional_text, single_line
from app.schemas.coupon import CouponCode
from app.schemas.payment import PaymentSummary
from app.schemas.service_area import Pincode
from app.schemas.tracking import TimelineEvent

_CENT = Decimal("0.01")


def _two_places(value: Decimal) -> Decimal:
    return value.quantize(_CENT, rounding=ROUND_HALF_UP)


# Amounts read back from the database always show two decimals ("849.00").
Amount = Annotated[Decimal, AfterValidator(_two_places)]

AddressLine = Annotated[str, single_line(5, 250)]
Landmark = Annotated[str | None, optional_text(120)]
Notes = Annotated[str | None, optional_text(500)]
Reason = Annotated[str | None, optional_text(300)]


class _Location(BaseModel):
    @model_validator(mode="after")
    def _both_coordinates(self) -> "_Location":
        lat = getattr(self, "latitude", None)
        lng = getattr(self, "longitude", None)
        if (lat is None) != (lng is None):
            raise ValueError("Send latitude and longitude together")
        return self


class QuoteRequest(BaseModel):
    """What the summary screen asks for: a package and the add-ons the customer ticked."""

    model_config = ConfigDict(extra="forbid")

    package_id: UUID
    extra_charge_ids: list[UUID] = Field(default_factory=list, max_length=20)
    # A coupon the customer typed; the server checks it and works out the discount.
    coupon_code: CouponCode | None = None

    @model_validator(mode="after")
    def _unique(self) -> "QuoteRequest":
        if len(set(self.extra_charge_ids)) != len(self.extra_charge_ids):
            raise ValueError("extra_charge_ids must not repeat")
        return self


class BookingCreate(_Location, QuoteRequest):
    pincode: Pincode
    address_line: AddressLine
    landmark: Landmark = None
    latitude: Annotated[float | None, Field(ge=-90, le=90)] = None
    longitude: Annotated[float | None, Field(ge=-180, le=180)] = None
    scheduled_date: date
    time_slot_id: UUID
    customer_notes: Notes = None
    # One of the customer's saved vehicles (optional); its details are copied onto the booking.
    vehicle_id: UUID | None = None
    # Lets the app retry safely: the same key never creates a second booking.
    client_request_id: UUID | None = None
    # The total the customer was shown; a mismatch is refused (409), never trusted.
    expected_total: Money | None = None


class BookingUpdate(PatchModel, _Location):
    """What a customer may change while the booking is still editable.

    Date and slot move together. The service, package, price and extra charges are
    not editable: cancel and book again instead.
    """

    nullable = frozenset({"landmark", "customer_notes", "latitude", "longitude"})

    pincode: Pincode | None = None
    address_line: AddressLine | None = None
    landmark: Landmark = None
    latitude: Annotated[float | None, Field(ge=-90, le=90)] = None
    longitude: Annotated[float | None, Field(ge=-180, le=180)] = None
    customer_notes: Notes = None
    scheduled_date: date | None = None
    time_slot_id: UUID | None = None

    @model_validator(mode="after")
    def _schedule_together(self) -> "BookingUpdate":
        sent = self.model_fields_set
        if ("scheduled_date" in sent) != ("time_slot_id" in sent):
            raise ValueError("Send scheduled_date and time_slot_id together")
        return self


class BookingCancel(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason: Reason = None


class AdminStatusUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: BookingStatus
    reason: Reason = None


# ---- Responses -------------------------------------------------------------------------


class QuoteCharge(BaseModel):
    extra_charge_id: UUID
    charge_type: ExtraChargeType
    name: str
    amount: Amount | None = None
    # Can the customer add it up front? Only charges with a fixed amount can be.
    selectable: bool
    selected: bool
    included_in_total: bool


class BookingQuote(BaseModel):
    service_id: UUID
    service_name: str
    vehicle_type: VehicleType
    package_id: UUID
    package_name: str
    inclusions: list[str]
    estimated_duration_minutes: int | None = None
    package_price: Amount
    extra_charges: list[QuoteCharge]
    extra_charges_total: Amount
    coupon_code: str | None = None
    discount_amount: Amount = Decimal("0.00")
    # The estimated total: package + chosen add-ons - discount.
    total_amount: Amount
    # Collected now (advance_percent of the total) and the part paid after the service.
    advance_percent: Amount
    advance_amount: Amount
    balance_after_advance: Amount


class BookingChargeOut(BaseModel):
    id: UUID
    extra_charge_id: UUID | None = None
    charge_type: ExtraChargeType
    name: str
    amount: Amount | None = None
    included_in_total: bool


class BookingRecord(BaseModel):
    """A booking row as stored (plus its extra-charge snapshot)."""

    id: UUID
    booking_number: int
    customer_id: UUID
    service_id: UUID
    package_id: UUID
    vehicle_type: VehicleType
    status: BookingStatus
    customer_name: str
    customer_phone: str
    address_line: str
    landmark: str | None = None
    city: str
    state: str | None = None
    pincode: str
    service_area_id: UUID | None = None
    latitude: float | None = None
    longitude: float | None = None
    scheduled_date: date
    slot_start: time
    slot_end: time
    service_name: str
    package_name: str
    package_inclusions: list[str] = Field(default_factory=list)
    estimated_duration_minutes: int | None = None
    package_price: Amount
    extra_charges_total: Amount
    coupon_code: str | None = None
    discount_amount: Amount = Decimal("0.00")
    advance_percent: Amount = Decimal("20.00")
    advance_amount: Amount = Decimal("0.00")
    total_amount: Amount
    vehicle_registration: str | None = None
    vehicle_make: str | None = None
    vehicle_model: str | None = None
    vehicle_nickname: str | None = None
    customer_notes: str | None = None
    cancellation_reason: str | None = None
    cancelled_by: UUID | None = None
    client_request_id: UUID | None = None
    confirmed_at: datetime | None = None
    completed_at: datetime | None = None
    cancelled_at: datetime | None = None
    created_at: datetime
    updated_at: datetime
    extra_charges: list[BookingChargeOut] = Field(default_factory=list)

    @model_validator(mode="before")
    @classmethod
    def _embedded_charges(cls, data: Any) -> Any:
        if isinstance(data, dict) and "booking_extra_charges" in data:
            data = {**data, "extra_charges": data["booking_extra_charges"] or []}
        return data


class BookingOut(BaseModel):
    """What a customer sees about their own booking."""

    id: UUID
    booking_number: int
    booking_code: str
    status: BookingStatus
    vehicle_type: VehicleType
    service_id: UUID
    package_id: UUID
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
    package_price: Amount
    extra_charges_total: Amount
    coupon_code: str | None = None
    discount_amount: Amount = Decimal("0.00")
    # The estimated total (package + add-ons - discount) and what is collected when booking.
    total_amount: Amount
    advance_percent: Amount = Decimal("20.00")
    advance_amount: Amount = Decimal("0.00")
    extra_charges: list[BookingChargeOut]
    vehicle_registration: str | None = None
    vehicle_make: str | None = None
    vehicle_model: str | None = None
    vehicle_nickname: str | None = None
    customer_notes: str | None = None
    cancellation_reason: str | None = None
    confirmed_at: datetime | None = None
    completed_at: datetime | None = None
    cancelled_at: datetime | None = None
    created_at: datetime
    # What the customer may do right now (the app shows or hides buttons from these).
    can_cancel: bool = False
    can_modify: bool = False
    cancel_blocked_reason: str | None = None
    # Payment: the successful payment if there is one, else the latest attempt.
    payment: PaymentSummary | None = None
    is_paid: bool = False
    can_pay: bool = False
    # After the service: the bill so far (estimated total + approved extras), what has been
    # paid and what is left. `can_pay_balance` is true only once the booking is completed.
    approved_extras_total: Amount = Decimal("0.00")
    pending_extras_count: int = 0
    final_total: Amount = Decimal("0.00")
    amount_paid: Amount = Decimal("0.00")
    balance_due: Amount = Decimal("0.00")
    can_pay_balance: bool = False
    # The driver, once one is assigned (a cancelled booking shows none).
    driver: DriverSummary | None = None
    # Every status the booking has been in, oldest first (single-booking views only).
    timeline: list[TimelineEvent] = Field(default_factory=list)


class AdminBookingOut(BookingOut):
    customer_id: UUID
    service_area_id: UUID | None = None
    cancelled_by: UUID | None = None
    updated_at: datetime
    # Manual status changes the admin may make from the current status.
    allowed_status_updates: list[BookingStatus] = Field(default_factory=list)
    # Driver assignment: who has it, and whether a driver can be set or removed now.
    assignment: AdminAssignment | None = None
    can_assign: bool = False
    can_unassign: bool = False


class BookingPage(BaseModel):
    items: list[BookingOut]
    total: int
    limit: int
    offset: int


class AdminBookingPage(BaseModel):
    items: list[AdminBookingOut]
    total: int
    limit: int
    offset: int
