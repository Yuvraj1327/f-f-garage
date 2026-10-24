"""Admin-only management of time slots and date exceptions."""

from datetime import date
from uuid import UUID

from fastapi import APIRouter, status

from app.api.auth import AdminDep
from app.api.deps import AvailabilityServiceDep
from app.schemas.availability import (
    ExceptionCreate,
    ExceptionOut,
    ExceptionUpdate,
    TimeSlotCreate,
    TimeSlotOut,
    TimeSlotUpdate,
)

router = APIRouter(prefix="/admin/availability", tags=["Admin: Availability"])

_ADMIN = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Caller is not an admin"},
}
_CONFLICT = {**_ADMIN, 409: {"description": "Overlap, duplicate, or slot in use"}}


@router.get("/slots", response_model=list[TimeSlotOut], summary="List time slots", responses=_ADMIN)
def list_slots(_admin: AdminDep, service: AvailabilityServiceDep) -> list[TimeSlotOut]:
    """Including inactive slots."""
    return service.list_slots()


@router.post(
    "/slots",
    response_model=TimeSlotOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a time slot",
    responses=_CONFLICT,
)
def create_slot(
    payload: TimeSlotCreate, admin: AdminDep, service: AvailabilityServiceDep
) -> TimeSlotOut:
    """Active slots may not overlap on a shared weekday (1 = Monday ... 7 = Sunday)."""
    return service.create_slot(admin, payload)


@router.patch(
    "/slots/{slot_id}",
    response_model=TimeSlotOut,
    summary="Edit, activate or deactivate a time slot",
    responses=_CONFLICT,
)
def update_slot(
    slot_id: UUID,
    payload: TimeSlotUpdate,
    admin: AdminDep,
    service: AvailabilityServiceDep,
) -> TimeSlotOut:
    return service.update_slot(admin, slot_id, payload)


@router.delete(
    "/slots/{slot_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a time slot",
    responses=_CONFLICT,
)
def delete_slot(slot_id: UUID, admin: AdminDep, service: AvailabilityServiceDep) -> None:
    service.delete_slot(admin, slot_id)


@router.get(
    "/exceptions",
    response_model=list[ExceptionOut],
    summary="List closures and special openings",
    responses=_ADMIN,
)
def list_exceptions(
    _admin: AdminDep,
    service: AvailabilityServiceDep,
    start_date: date,
    end_date: date,
) -> list[ExceptionOut]:
    return service.list_exceptions(start_date, end_date)


@router.post(
    "/exceptions",
    response_model=ExceptionOut,
    status_code=status.HTTP_201_CREATED,
    summary="Close a day or slot, or open a slot on a day it normally does not run",
    responses=_CONFLICT,
)
def create_exception(
    payload: ExceptionCreate, admin: AdminDep, service: AvailabilityServiceDep
) -> ExceptionOut:
    return service.create_exception(admin, payload)


@router.patch(
    "/exceptions/{exception_id}",
    response_model=ExceptionOut,
    summary="Edit a closure or special opening",
    responses=_ADMIN,
)
def update_exception(
    exception_id: UUID,
    payload: ExceptionUpdate,
    admin: AdminDep,
    service: AvailabilityServiceDep,
) -> ExceptionOut:
    return service.update_exception(admin, exception_id, payload)


@router.delete(
    "/exceptions/{exception_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a closure or special opening",
    responses=_ADMIN,
)
def delete_exception(exception_id: UUID, admin: AdminDep, service: AvailabilityServiceDep) -> None:
    service.delete_exception(admin, exception_id)
