"""The garage's business details in Supabase (service-role client)."""

from datetime import UTC, datetime
from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.db.postgrest import run


class GarageSettingsRepository(Protocol):
    def get(self) -> dict[str, Any] | None: ...

    def save(self, values: dict[str, Any], admin_id: UUID) -> dict[str, Any]: ...


class SupabaseGarageSettingsRepository:
    TABLE = "garage_settings"

    def __init__(self, client: Client) -> None:
        self._client = client

    def get(self) -> dict[str, Any] | None:
        rows = run(self._client.table(self.TABLE).select("*").limit(1))
        return rows[0] if rows else None

    def save(self, values: dict[str, Any], admin_id: UUID) -> dict[str, Any]:
        row = {
            **values,
            "id": True,
            "updated_by": str(admin_id),
            "updated_at": datetime.now(UTC).isoformat(),
        }
        return run(self._client.table(self.TABLE).upsert(row, on_conflict="id"))[0]
