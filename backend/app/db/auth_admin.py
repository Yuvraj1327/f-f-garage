"""Supabase Auth admin operations (service-role only) used to manage drivers."""

from typing import Protocol

import httpx
from supabase import Client
from supabase_auth.errors import AuthApiError, AuthError

from app.core.errors import ConflictError, NotFoundError, UpstreamError

# Supabase has no "disable user" flag; a very long ban is the documented way.
BAN_FOREVER = "876000h"  # about 100 years
BAN_NONE = "none"

_ALREADY_EXISTS_CODES = {"email_exists", "user_already_exists"}


class AuthAdminGateway(Protocol):
    def create_driver_user(
        self,
        *,
        email: str,
        password: str,
        driver_login_id: str,
        full_name: str,
        phone: str | None,
    ) -> str: ...

    def set_password(self, user_id: str, password: str) -> None: ...

    def set_banned(self, user_id: str, banned: bool) -> None: ...

    def delete_user(self, user_id: str) -> None: ...


class SupabaseAuthAdminGateway:
    def __init__(self, client: Client) -> None:
        self._admin = client.auth.admin

    def create_driver_user(
        self,
        *,
        email: str,
        password: str,
        driver_login_id: str,
        full_name: str,
        phone: str | None,
    ) -> str:
        user_metadata: dict[str, str] = {"full_name": full_name}
        if phone:
            user_metadata["phone"] = phone
        try:
            response = self._admin.create_user(
                {
                    "email": email,
                    "password": password,
                    "email_confirm": True,
                    # app_metadata can only be written by this admin API. A database
                    # trigger reads it to create the driver profile atomically and to
                    # let this email on the reserved driver domain through.
                    "app_metadata": {"managed_driver": True, "driver_login_id": driver_login_id},
                    "user_metadata": user_metadata,
                }
            )
        except AuthApiError as exc:
            if exc.code in _ALREADY_EXISTS_CODES:
                raise ConflictError("A driver with this ID already exists") from exc
            raise UpstreamError("Could not create the driver account") from exc
        except (AuthError, httpx.HTTPError) as exc:
            raise UpstreamError("Could not create the driver account") from exc
        if response.user is None:
            raise UpstreamError("Could not create the driver account")
        return str(response.user.id)

    def set_password(self, user_id: str, password: str) -> None:
        self._update(user_id, {"password": password}, "Could not reset the password")

    def set_banned(self, user_id: str, banned: bool) -> None:
        self._update(
            user_id,
            {"ban_duration": BAN_FOREVER if banned else BAN_NONE},
            "Could not update the driver account",
        )

    def delete_user(self, user_id: str) -> None:
        try:
            self._admin.delete_user(user_id)
        except (AuthError, httpx.HTTPError) as exc:
            raise UpstreamError("Could not remove the account") from exc

    def _update(self, user_id: str, attributes: dict, failure_detail: str) -> None:
        try:
            self._admin.update_user_by_id(user_id, attributes)
        except AuthApiError as exc:
            if exc.status == 404 or exc.code == "user_not_found":
                raise NotFoundError("Driver not found") from exc
            raise UpstreamError(failure_detail) from exc
        except (AuthError, httpx.HTTPError) as exc:
            raise UpstreamError(failure_detail) from exc
