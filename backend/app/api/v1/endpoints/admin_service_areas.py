"""Admin-only management of serviceable PIN codes."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, status

from app.api.auth import AdminDep
from app.api.deps import ServiceAreaServiceDep
from app.schemas.service_area import ServiceAreaCreate, ServiceAreaOut, ServiceAreaUpdate

router = APIRouter(prefix="/admin/service-areas", tags=["Admin: Service areas"])

_ADMIN = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Caller is not an admin"},
}
_CONFLICT = {**_ADMIN, 409: {"description": "PIN code already exists"}}


@router.get("", response_model=list[ServiceAreaOut], summary="List service areas", responses=_ADMIN)
def list_areas(
    _admin: AdminDep,
    service: ServiceAreaServiceDep,
    city: Annotated[str | None, Query(min_length=1, max_length=80)] = None,
) -> list[ServiceAreaOut]:
    """Including inactive areas."""
    return service.list_areas(city=city)


@router.post(
    "",
    response_model=ServiceAreaOut,
    status_code=status.HTTP_201_CREATED,
    summary="Add a serviceable PIN code",
    responses=_CONFLICT,
)
def create_area(
    payload: ServiceAreaCreate, admin: AdminDep, service: ServiceAreaServiceDep
) -> ServiceAreaOut:
    return service.create_area(admin, payload)


@router.get(
    "/{area_id}", response_model=ServiceAreaOut, summary="Get a service area", responses=_ADMIN
)
def get_area(area_id: UUID, _admin: AdminDep, service: ServiceAreaServiceDep) -> ServiceAreaOut:
    return service.get_area(area_id)


@router.patch(
    "/{area_id}",
    response_model=ServiceAreaOut,
    summary="Edit, activate or deactivate a service area",
    responses=_CONFLICT,
)
def update_area(
    area_id: UUID,
    payload: ServiceAreaUpdate,
    admin: AdminDep,
    service: ServiceAreaServiceDep,
) -> ServiceAreaOut:
    return service.update_area(admin, area_id, payload)


@router.delete(
    "/{area_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a service area",
    responses=_ADMIN,
)
def delete_area(area_id: UUID, admin: AdminDep, service: ServiceAreaServiceDep) -> None:
    """Existing bookings keep their PIN code. Deactivate instead to pause an area."""
    service.delete_area(admin, area_id)
