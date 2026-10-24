"""Authentication and role-based access dependencies.

    get_current_user    verifies the bearer token, then loads the caller's profile
    require_roles(...)  additionally restricts an endpoint to the given roles

Roles are ALWAYS read from the `profiles` table on every request, never from the
token, so promoting, demoting or disabling a user takes effect immediately even
though their access token stays cryptographically valid until it expires.

    401  missing / invalid / expired token          (client should refresh or sign in)
    403  valid token, but no profile, account disabled, or role not allowed
"""

from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.api.deps import ProfileRepositoryDep, TokenVerifierDep
from app.core.security import TokenClaims, TokenError
from app.domain.enums import UserRole
from app.schemas.profile import ProfileOut

bearer_scheme = HTTPBearer(
    auto_error=False,
    scheme_name="SupabaseAccessToken",
    description="The Supabase access token of the signed-in user.",
)

_UNAUTHENTICATED_HEADERS = {"WWW-Authenticate": "Bearer"}


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers=_UNAUTHENTICATED_HEADERS,
    )


def get_token_claims(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    verifier: TokenVerifierDep,
) -> TokenClaims:
    """Step 1: who is calling? Pure token check; touches no database, so
    unauthenticated requests are rejected before any data access."""
    if credentials is None or not credentials.credentials:
        raise _unauthorized("Not authenticated")
    try:
        return verifier.verify(credentials.credentials)
    except TokenError as exc:
        raise _unauthorized(str(exc)) from exc


def get_current_user(
    claims: Annotated[TokenClaims, Depends(get_token_claims)],
    profiles: ProfileRepositoryDep,
) -> ProfileOut:
    """Step 2: what may they do? Loads the profile (and its role) from the database."""
    profile = profiles.get(claims.user_id)
    if profile is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "No profile exists for this account")
    if not profile.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This account has been disabled")
    return profile


CurrentUserDep = Annotated[ProfileOut, Depends(get_current_user)]


def require_roles(*allowed: UserRole):
    """Dependency factory: the caller must be signed in AND hold one of `allowed`."""

    def dependency(user: CurrentUserDep) -> ProfileOut:
        if user.role not in allowed:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                "You do not have permission to perform this action",
            )
        return user

    return dependency


CustomerDep = Annotated[ProfileOut, Depends(require_roles(UserRole.CUSTOMER))]
DriverDep = Annotated[ProfileOut, Depends(require_roles(UserRole.DRIVER))]
AdminDep = Annotated[ProfileOut, Depends(require_roles(UserRole.ADMIN))]
