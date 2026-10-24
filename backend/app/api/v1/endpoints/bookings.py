"""Customer bookings: price quote, create, history, details, change, cancel.

Customers only. A booking that belongs to someone else is reported as not found.
"""

from datetime import date
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Response, status

from app.api.auth import AdminDep, CustomerDep
from app.api.deps import BookingServiceDep
from app.domain.enums import BookingStatus, VehicleType
from app.schemas.booking import (
    AdminBookingOut,
    AdminBookingPage,
    AdminStatusUpdate,
    BookingCancel,
    BookingCreate,
    BookingOut,
    BookingPage,
    BookingQuote,
    BookingUpdate,
    QuoteRequest,
)

router = APIRouter(tags=["Bookings"])
admin_router = APIRouter(prefix="/admin/bookings", tags=["Admin: bookings"])

_AUTH = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Only customers can use this endpoint"},
}
_ADMIN = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Admin access required"},
}


@router.post(
    "/bookings/quote",
    response_model=BookingQuote,
    summary="Price summary for a package and chosen extra charges",
    responses={**_AUTH, 404: {"description": "Package or service not available"}},
)
def quote_booking(
    payload: QuoteRequest, _customer: CustomerDep, service: BookingServiceDep
) -> BookingQuote:
    return service.quote(payload)


@router.post(
    "/bookings",
    response_model=BookingOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a booking",
    responses={
        **_AUTH,
        200: {"description": "This client_request_id was already used; the first booking"},
        404: {"description": "Package, service or time slot not available"},
        409: {"description": "Slot unavailable or full, duplicate booking, or the price changed"},
        422: {"description": "PIN code not serviceable, or invalid input"},
    },
)
def create_booking(
    payload: BookingCreate,
    response: Response,
    customer: CustomerDep,
    service: BookingServiceDep,
) -> BookingOut:
    booking, created = service.create(customer, payload)
    if not created:
        response.status_code = status.HTTP_200_OK
    return booking


@router.get("/bookings", response_model=BookingPage, summary="My bookings", responses=_AUTH)
def list_my_bookings(
    customer: CustomerDep,
    service: BookingServiceDep,
    booking_status: Annotated[list[BookingStatus] | None, Query(alias="status")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0, le=100_000)] = 0,
) -> BookingPage:
    """Newest first."""
    return service.list_for_customer(customer, statuses=booking_status, limit=limit, offset=offset)


@router.get(
    "/bookings/{booking_id}",
    response_model=BookingOut,
    summary="One of my bookings",
    responses={**_AUTH, 404: {"description": "No such booking (or not yours)"}},
)
def get_my_booking(
    booking_id: UUID, customer: CustomerDep, service: BookingServiceDep
) -> BookingOut:
    return service.get_for_customer(customer, booking_id)


@router.patch(
    "/bookings/{booking_id}",
    response_model=BookingOut,
    summary="Change the address, notes or schedule of my booking",
    responses={
        **_AUTH,
        404: {"description": "No such booking"},
        409: {"description": "Not changeable"},
    },
)
def update_my_booking(
    booking_id: UUID,
    payload: BookingUpdate,
    customer: CustomerDep,
    service: BookingServiceDep,
) -> BookingOut:
    return service.update(customer, booking_id, payload)


@router.post(
    "/bookings/{booking_id}/cancel",
    response_model=BookingOut,
    summary="Cancel my booking",
    responses={
        **_AUTH,
        404: {"description": "No such booking"},
        409: {"description": "Not cancellable"},
    },
)
def cancel_my_booking(
    booking_id: UUID,
    customer: CustomerDep,
    service: BookingServiceDep,
    payload: BookingCancel | None = None,
) -> BookingOut:
    return service.cancel(customer, booking_id, payload.reason if payload else None)


# ---- Admin -----------------------------------------------------------------------------


@admin_router.get(
    "", response_model=AdminBookingPage, summary="Search and filter all bookings", responses=_ADMIN
)
def admin_list_bookings(
    _admin: AdminDep,
    service: BookingServiceDep,
    booking_status: Annotated[list[BookingStatus] | None, Query(alias="status")] = None,
    vehicle_type: VehicleType | None = None,
    date_from: Annotated[date | None, Query(description="Scheduled on or after")] = None,
    date_to: Annotated[date | None, Query(description="Scheduled on or before")] = None,
    pincode: Annotated[str | None, Query(pattern=r"^[1-9][0-9]{5}$")] = None,
    customer_id: UUID | None = None,
    q: Annotated[
        str | None,
        Query(max_length=60, description="Booking number (FF-000123), customer name or phone"),
    ] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 25,
    offset: Annotated[int, Query(ge=0, le=100_000)] = 0,
) -> AdminBookingPage:
    return service.admin_search(
        statuses=booking_status,
        vehicle_type=vehicle_type,
        date_from=date_from,
        date_to=date_to,
        pincode=pincode,
        customer_id=customer_id,
        query=q,
        limit=limit,
        offset=offset,
    )


@admin_router.get(
    "/{booking_id}",
    response_model=AdminBookingOut,
    summary="Booking details",
    responses={**_ADMIN, 404: {"description": "No such booking"}},
)
def admin_get_booking(
    booking_id: UUID, _admin: AdminDep, service: BookingServiceDep
) -> AdminBookingOut:
    return service.admin_get(booking_id)


@admin_router.patch(
    "/{booking_id}/status",
    response_model=AdminBookingOut,
    summary="Confirm or cancel a booking",
    responses={
        **_ADMIN,
        404: {"description": "No such booking"},
        409: {"description": "That change is not allowed from the current status"},
        422: {"description": "That status is not set by hand"},
    },
)
def admin_update_booking_status(
    booking_id: UUID,
    payload: AdminStatusUpdate,
    admin: AdminDep,
    service: BookingServiceDep,
) -> AdminBookingOut:
    return service.admin_update_status(admin, booking_id, payload)
