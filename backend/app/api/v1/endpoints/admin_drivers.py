"""Admin-only management of driver accounts."""

from uuid import UUID

from fastapi import APIRouter, status

from app.api.auth import AdminDep
from app.api.deps import DriverAdminServiceDep
from app.schemas.driver import DriverCreate, DriverOut, DriverPasswordReset, DriverUpdate

router = APIRouter(prefix="/admin/drivers", tags=["Admin: Drivers"])

_ADMIN_RESPONSES = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Caller is not an admin"},
}


@router.get("", response_model=list[DriverOut], summary="List drivers", responses=_ADMIN_RESPONSES)
def list_drivers(_admin: AdminDep, service: DriverAdminServiceDep) -> list[DriverOut]:
    return service.list_drivers()


@router.post(
    "",
    response_model=DriverOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a driver account",
    responses={**_ADMIN_RESPONSES, 409: {"description": "Driver ID already exists"}},
)
def create_driver(
    payload: DriverCreate,
    admin: AdminDep,
    service: DriverAdminServiceDep,
) -> DriverOut:
    """Creates the driver's login (ID + password). Drivers cannot register themselves."""
    return service.create_driver(admin, payload)


@router.get(
    "/{driver_id}",
    response_model=DriverOut,
    summary="Get a driver",
    responses=_ADMIN_RESPONSES,
)
def get_driver(driver_id: UUID, _admin: AdminDep, service: DriverAdminServiceDep) -> DriverOut:
    return service.get_driver(driver_id)


@router.patch(
    "/{driver_id}",
    response_model=DriverOut,
    summary="Update a driver (name, phone, enable/disable)",
    responses=_ADMIN_RESPONSES,
)
def update_driver(
    driver_id: UUID,
    payload: DriverUpdate,
    admin: AdminDep,
    service: DriverAdminServiceDep,
) -> DriverOut:
    """Disabling a driver blocks their API access immediately and bans their login."""
    return service.update_driver(admin, driver_id, payload)


@router.post(
    "/{driver_id}/password",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Reset a driver's password",
    responses=_ADMIN_RESPONSES,
)
def reset_driver_password(
    driver_id: UUID,
    payload: DriverPasswordReset,
    admin: AdminDep,
    service: DriverAdminServiceDep,
) -> None:
    service.reset_password(admin, driver_id, payload.new_password.get_secret_value())
