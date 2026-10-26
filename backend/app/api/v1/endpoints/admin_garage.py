"""Admin-only garage business details (name, phone, email, address, hours)."""

from fastapi import APIRouter

from app.api.auth import AdminDep
from app.api.deps import GarageSettingsServiceDep
from app.schemas.garage import GarageSettingsOut, GarageSettingsUpdate

router = APIRouter(prefix="/admin/garage-settings", tags=["Admin: Garage settings"])

_ADMIN = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Caller is not an admin"},
}


@router.get("", response_model=GarageSettingsOut, summary="Garage details", responses=_ADMIN)
def read_garage_settings(_admin: AdminDep, service: GarageSettingsServiceDep) -> GarageSettingsOut:
    """What customers see on the support screen: saved details, or the server's defaults."""
    return service.current()


@router.put("", response_model=GarageSettingsOut, summary="Save garage details", responses=_ADMIN)
def save_garage_settings(
    payload: GarageSettingsUpdate, admin: AdminDep, service: GarageSettingsServiceDep
) -> GarageSettingsOut:
    return service.update(admin, payload)
