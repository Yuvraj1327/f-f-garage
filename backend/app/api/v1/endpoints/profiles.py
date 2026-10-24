from fastapi import APIRouter

from app.api.auth import CurrentUserDep, CustomerDep
from app.api.deps import ProfileServiceDep
from app.schemas.profile import ProfileOut, ProfileUpdate

router = APIRouter(prefix="/profiles", tags=["Profiles"])

_AUTH_RESPONSES = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Account disabled, or the role is not allowed"},
}


@router.get(
    "/me",
    response_model=ProfileOut,
    summary="Get my profile",
    responses=_AUTH_RESPONSES,
)
def read_my_profile(user: CurrentUserDep) -> ProfileOut:
    """The caller's own profile. Available to every active role; the mobile app uses the
    returned `role` to decide which area to show."""
    return user


@router.patch(
    "/me",
    response_model=ProfileOut,
    summary="Update my profile (customers only)",
    responses=_AUTH_RESPONSES,
)
def update_my_profile(
    changes: ProfileUpdate,
    user: CustomerDep,
    service: ProfileServiceDep,
) -> ProfileOut:
    """Customers can change their name and phone. Driver details are managed by an admin,
    and role / activation fields can never be changed here."""
    return service.update_own_profile(user, changes)
