from fastapi import APIRouter

from app.api.auth import CurrentUserDep
from app.api.deps import GarageSettingsServiceDep
from app.schemas.support import SupportContactOut

router = APIRouter(prefix="/support", tags=["Support"])


def _digits_plus(raw: str) -> str:
    """Keep a leading + and digits only, so the app can build tel:/WhatsApp links."""
    raw = raw.strip()
    cleaned = "".join(ch for ch in raw if ch.isdigit())
    if not cleaned:
        return ""
    return ("+" if raw.startswith("+") else "") + cleaned


@router.get(
    "/contact",
    response_model=SupportContactOut,
    summary="Garage contact details",
    responses={
        401: {"description": "Missing, invalid or expired access token"},
        403: {"description": "Account disabled"},
    },
)
def read_contact(user: CurrentUserDep, garage: GarageSettingsServiceDep) -> SupportContactOut:
    """The details an admin saved in the app, or (until they do) the ones configured
    through environment variables. Fields that are not set come back as empty strings."""
    current = garage.current()
    return SupportContactOut(
        name=current.name,
        phone=_digits_plus(current.phone),
        whatsapp=_digits_plus(current.whatsapp),
        email=current.email,
        address=current.address,
        hours=current.hours,
        refund_policy=current.refund_policy,
    )
