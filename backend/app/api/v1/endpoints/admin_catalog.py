"""Admin-only management of services, packages and extra charges."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, status

from app.api.auth import AdminDep
from app.api.deps import CatalogServiceDep
from app.domain.enums import VehicleType
from app.schemas.catalog import (
    ExtraChargeCreate,
    ExtraChargeOut,
    ExtraChargeUpdate,
    PackageCreate,
    PackageDetail,
    PackageUpdate,
    ServiceCreate,
    ServiceDetail,
    ServiceUpdate,
)

router = APIRouter(prefix="/admin", tags=["Admin: Services"])

_ADMIN = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Caller is not an admin"},
}
_CONFLICT = {**_ADMIN, 409: {"description": "Name already in use"}}


@router.get(
    "/services", response_model=list[ServiceDetail], summary="List all services", responses=_ADMIN
)
def list_services(
    _admin: AdminDep,
    service: CatalogServiceDep,
    vehicle_type: VehicleType | None = None,
    category: Annotated[str | None, Query(min_length=1, max_length=60)] = None,
) -> list[ServiceDetail]:
    """Including inactive services, packages and charges."""
    return service.list_all(vehicle_type, category)


@router.post(
    "/services",
    response_model=ServiceDetail,
    status_code=status.HTTP_201_CREATED,
    summary="Create a service",
    responses=_CONFLICT,
)
def create_service(
    payload: ServiceCreate, admin: AdminDep, service: CatalogServiceDep
) -> ServiceDetail:
    return service.create_service(admin, payload)


@router.get(
    "/services/{service_id}",
    response_model=ServiceDetail,
    summary="Get a service",
    responses=_ADMIN,
)
def get_service(service_id: UUID, _admin: AdminDep, service: CatalogServiceDep) -> ServiceDetail:
    return service.get(service_id)


@router.patch(
    "/services/{service_id}",
    response_model=ServiceDetail,
    summary="Edit, enable or disable a service",
    responses=_CONFLICT,
)
def update_service(
    service_id: UUID,
    payload: ServiceUpdate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> ServiceDetail:
    return service.update_service(admin, service_id, payload)


@router.post(
    "/services/{service_id}/packages",
    response_model=PackageDetail,
    status_code=status.HTTP_201_CREATED,
    summary="Add a package to a service",
    responses=_CONFLICT,
)
def create_package(
    service_id: UUID,
    payload: PackageCreate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> PackageDetail:
    return service.create_package(admin, service_id, payload)


@router.patch(
    "/packages/{package_id}",
    response_model=PackageDetail,
    summary="Edit, enable or disable a package",
    responses=_CONFLICT,
)
def update_package(
    package_id: UUID,
    payload: PackageUpdate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> PackageDetail:
    return service.update_package(admin, package_id, payload)


@router.post(
    "/services/{service_id}/extra-charges",
    response_model=ExtraChargeOut,
    status_code=status.HTTP_201_CREATED,
    summary="Add an extra charge (spare part, engine oil, other)",
    responses=_ADMIN,
)
def create_extra_charge(
    service_id: UUID,
    payload: ExtraChargeCreate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> ExtraChargeOut:
    """Leave `package_id` empty for a charge that applies to every package."""
    return service.create_extra_charge(admin, service_id, payload)


@router.patch(
    "/extra-charges/{charge_id}",
    response_model=ExtraChargeOut,
    summary="Edit, enable or disable an extra charge",
    responses=_ADMIN,
)
def update_extra_charge(
    charge_id: UUID,
    payload: ExtraChargeUpdate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> ExtraChargeOut:
    return service.update_extra_charge(admin, charge_id, payload)


@router.delete(
    "/extra-charges/{charge_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an extra charge",
    responses=_ADMIN,
)
def delete_extra_charge(charge_id: UUID, admin: AdminDep, service: CatalogServiceDep) -> None:
    service.delete_extra_charge(admin, charge_id)
