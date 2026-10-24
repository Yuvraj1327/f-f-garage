"""Access to the `profiles` table through the service-role Supabase client."""

from typing import Any, Protocol

import httpx
from postgrest.exceptions import APIError
from supabase import Client

from app.core.errors import ServiceUnavailableError
from app.domain.enums import UserRole
from app.schemas.profile import ProfileOut


class ProfileRepository(Protocol):
    def get(self, user_id: str) -> ProfileOut | None: ...

    def get_many(self, user_ids: list[str]) -> list[ProfileOut]: ...

    def update(self, user_id: str, values: dict[str, Any]) -> ProfileOut | None: ...

    def get_driver(self, user_id: str) -> ProfileOut | None: ...

    def list_drivers(self) -> list[ProfileOut]: ...

    def driver_login_id_exists(self, driver_login_id: str) -> bool: ...


class SupabaseProfileRepository:
    TABLE = "profiles"

    def __init__(self, client: Client) -> None:
        self._client = client

    def get(self, user_id: str) -> ProfileOut | None:
        rows = self._rows(self._client.table(self.TABLE).select("*").eq("id", user_id).limit(1))
        return ProfileOut.model_validate(rows[0]) if rows else None

    def get_many(self, user_ids: list[str]) -> list[ProfileOut]:
        if not user_ids:
            return []
        rows = self._rows(self._client.table(self.TABLE).select("*").in_("id", user_ids))
        return [ProfileOut.model_validate(row) for row in rows]

    def update(self, user_id: str, values: dict[str, Any]) -> ProfileOut | None:
        rows = self._rows(self._client.table(self.TABLE).update(values).eq("id", user_id))
        return ProfileOut.model_validate(rows[0]) if rows else None

    def get_driver(self, user_id: str) -> ProfileOut | None:
        rows = self._rows(
            self._client.table(self.TABLE)
            .select("*")
            .eq("id", user_id)
            .eq("role", UserRole.DRIVER.value)
            .limit(1)
        )
        return ProfileOut.model_validate(rows[0]) if rows else None

    def list_drivers(self) -> list[ProfileOut]:
        rows = self._rows(
            self._client.table(self.TABLE)
            .select("*")
            .eq("role", UserRole.DRIVER.value)
            .order("created_at", desc=True)
        )
        return [ProfileOut.model_validate(row) for row in rows]

    def driver_login_id_exists(self, driver_login_id: str) -> bool:
        rows = self._rows(
            self._client.table(self.TABLE)
            .select("id")
            .eq("driver_login_id", driver_login_id)
            .limit(1)
        )
        return bool(rows)

    @staticmethod
    def _rows(query: Any) -> list[dict[str, Any]]:
        try:
            response = query.execute()
        except (APIError, httpx.HTTPError) as exc:
            raise ServiceUnavailableError("Database is unavailable") from exc
        data = response.data
        return data if isinstance(data, list) else []
