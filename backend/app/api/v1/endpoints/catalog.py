"""What customers (and every other signed-in user) can browse: services, PIN codes,
availability. Read-only; admins manage the data through the /admin routes."""

from datetime import date
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query

from app.api.auth import CurrentUserDep
from app.api.deps import AvailabilityServiceDep, CatalogServiceDep, ServiceAreaServiceDep
from app.domain.enums import VehicleType
from app.schemas.availability import DayAvailability
from app.schemas.catalog import ServiceDetail
from app.schemas.service_area import PincodeCheck

router = APIRouter(tags=["Catalog"])

_AUTH = {401: {"description": "Missing, invalid or expired access token"}}


@router.get(
    "/catalog/services",
    response_model=list[ServiceDetail],
    summary="Browse active services",
    responses=_AUTH,
)
def browse_services(
    _user: CurrentUserDep,
    service: CatalogServiceDep,
    vehicle_type: VehicleType | None = None,
    category: Annotated[str | None, Query(min_length=1, max_length=60)] = None,
) -> list[ServiceDetail]:
    """Active services with their active packages and the extra charges that may apply."""
    return service.list_active(vehicle_type, category)


@router.get(
    "/catalog/services/{service_id}",
    response_model=ServiceDetail,
    summary="One active service",
    responses=_AUTH,
)
def browse_service(
    service_id: UUID, _user: CurrentUserDep, service: CatalogServiceDep
) -> ServiceDetail:
    return service.get_active(service_id)


@router.get(
    "/service-areas/check",
    response_model=PincodeCheck,
    summary="Is a PIN code serviceable?",
    responses=_AUTH,
)
def check_pincode(
    pincode: Annotated[str, Query(pattern=r"^[1-9][0-9]{5}$")],
    _user: CurrentUserDep,
    service: ServiceAreaServiceDep,
) -> PincodeCheck:
    return service.check_pincode(pincode)


@router.get(
    "/availability",
    response_model=list[DayAvailability],
    summary="Available dates and time slots",
    responses={**_AUTH, 422: {"description": "Invalid or too long a date range"}},
)
def get_availability(
    _user: CurrentUserDep,
    service: AvailabilityServiceDep,
    start_date: date,
    end_date: date | None = None,
) -> list[DayAvailability]:
    """One entry per day (at most 31). `end_date` defaults to `start_date`."""
    return service.get_availability(start_date, end_date)
