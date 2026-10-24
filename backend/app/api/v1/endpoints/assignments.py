"""Driver assignment (admin) and a driver's own bookings (driver).

Admins decide who does which booking. A driver sees and updates only the bookings
currently assigned to them; the checks run on the server on every request.
"""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Response, status

from app.api.auth import AdminDep, DriverDep
from app.api.deps import AssignmentServiceDep, DriverWorkServiceDep
from app.schemas.assignment import AssignmentHistoryItem, AssignRequest, DriverStatusUpdate
from app.schemas.booking import AdminBookingOut, AdminBookingPage
from app.schemas.driver_work import DriverBookingOut, DriverBookingPage

admin_router = APIRouter(prefix="/admin", tags=["Admin: assignments"])
driver_router = APIRouter(prefix="/driver", tags=["Driver"])

Scope = Literal["open", "history"]

_ADMIN = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Admin access required"},
}
_DRIVER = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Only drivers can use this endpoint"},
}


@admin_router.put(
    "/bookings/{booking_id}/driver",
    response_model=AdminBookingOut,
    summary="Assign a driver to a booking, or change the driver",
    responses={
        **_ADMIN,
        404: {"description": "No such booking or driver"},
        409: {"description": "Not paid, not assignable in this status, driver deactivated or busy"},
    },
)
def assign_driver(
    booking_id: UUID,
    payload: AssignRequest,
    admin: AdminDep,
    service: AssignmentServiceDep,
) -> AdminBookingOut:
    """A paid booking (`confirmed`) becomes `assigned`. An assigned or on-the-way booking keeps
    its status when the driver changes. Sending the current driver again changes nothing."""
    return service.assign(admin, booking_id, payload.driver_id)


@admin_router.delete(
    "/bookings/{booking_id}/driver",
    response_model=AdminBookingOut,
    summary="Take the driver off a booking",
    responses={
        **_ADMIN,
        404: {"description": "No such booking"},
        409: {"description": "The driver is already on the way or the booking is finished"},
    },
)
def unassign_driver(
    booking_id: UUID, admin: AdminDep, service: AssignmentServiceDep
) -> AdminBookingOut:
    """Only while the booking is `assigned`; it goes back to `confirmed`."""
    return service.unassign(admin, booking_id)


@admin_router.get(
    "/bookings/{booking_id}/assignments",
    response_model=list[AssignmentHistoryItem],
    summary="Every driver this booking has had",
    responses={**_ADMIN, 404: {"description": "No such booking"}},
)
def assignment_history(
    booking_id: UUID, _admin: AdminDep, service: AssignmentServiceDep
) -> list[AssignmentHistoryItem]:
    return service.history(booking_id)


@admin_router.get(
    "/drivers/{driver_id}/bookings",
    response_model=AdminBookingPage,
    summary="A driver's bookings",
    responses={**_ADMIN, 404: {"description": "No such driver"}},
)
def driver_bookings(
    driver_id: UUID,
    _admin: AdminDep,
    service: AssignmentServiceDep,
    scope: Scope = "open",
    limit: Annotated[int, Query(ge=1, le=100)] = 25,
    offset: Annotated[int, Query(ge=0, le=100_000)] = 0,
) -> AdminBookingPage:
    return service.driver_bookings(driver_id, scope=scope, limit=limit, offset=offset)


@driver_router.get(
    "/bookings",
    response_model=DriverBookingPage,
    summary="My assigned bookings",
    responses=_DRIVER,
)
def my_bookings(
    driver: DriverDep,
    service: DriverWorkServiceDep,
    scope: Scope = "open",
    limit: Annotated[int, Query(ge=1, le=100)] = 25,
    offset: Annotated[int, Query(ge=0, le=100_000)] = 0,
) -> DriverBookingPage:
    """`open`: assigned, on the way or in progress (soonest first).
    `history`: completed or cancelled (latest first)."""
    return service.list(driver, scope=scope, limit=limit, offset=offset)


@driver_router.get(
    "/bookings/{booking_id}",
    response_model=DriverBookingOut,
    summary="One of my assigned bookings",
    responses={**_DRIVER, 404: {"description": "No such booking (or not assigned to you)"}},
)
def my_booking(
    booking_id: UUID, driver: DriverDep, service: DriverWorkServiceDep
) -> DriverBookingOut:
    return service.get(driver, booking_id)


@driver_router.post(
    "/bookings/{booking_id}/status",
    response_model=DriverBookingOut,
    summary="Move my booking to its next step",
    responses={
        **_DRIVER,
        404: {"description": "No such booking (or not assigned to you)"},
        409: {"description": "That step is not allowed now, or the booking was cancelled"},
        422: {"description": "A driver can only set on_the_way, in_progress or completed"},
    },
)
def update_my_booking_status(
    booking_id: UUID,
    payload: DriverStatusUpdate,
    driver: DriverDep,
    service: DriverWorkServiceDep,
    response: Response,
) -> DriverBookingOut:
    """One step at a time: assigned, then on_the_way, then in_progress, then completed.
    Sending the status the booking already has is accepted and changes nothing."""
    response.status_code = status.HTTP_200_OK
    return service.update_status(driver, booking_id, payload)
