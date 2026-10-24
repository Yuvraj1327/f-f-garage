from fastapi import APIRouter

from app.api.auth import CurrentUserDep
from app.api.deps import SettingsDep
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
def read_contact(user: CurrentUserDep, settings: SettingsDep) -> SupportContactOut:
    """Configured by the operator through environment variables. Fields that are not
    configured come back as empty strings."""
    return SupportContactOut(
        name=settings.garage_name.strip(),
        phone=_digits_plus(settings.garage_phone),
        whatsapp=_digits_plus(settings.garage_whatsapp),
        email=settings.garage_email.strip(),
        address=settings.garage_address.strip(),
        hours=settings.garage_hours.strip(),
    )
