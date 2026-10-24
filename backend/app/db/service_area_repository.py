"""Serviceable PIN codes in Supabase (service-role client)."""

from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.db.postgrest import run
from app.schemas.service_area import ServiceAreaOut

_DUPLICATE = "A service area with this PIN code already exists"


class ServiceAreaRepository(Protocol):
    def list(
        self, *, active_only: bool = False, city: str | None = None
    ) -> list[ServiceAreaOut]: ...

    def get(self, area_id: UUID) -> ServiceAreaOut | None: ...

    def get_by_pincode(self, pincode: str) -> ServiceAreaOut | None: ...

    def create(self, values: dict[str, Any]) -> ServiceAreaOut: ...

    def update(self, area_id: UUID, values: dict[str, Any]) -> ServiceAreaOut | None: ...

    def delete(self, area_id: UUID) -> bool: ...


class SupabaseServiceAreaRepository:
    TABLE = "service_areas"

    def __init__(self, client: Client) -> None:
        self._client = client

    def list(self, *, active_only: bool = False, city: str | None = None) -> list[ServiceAreaOut]:
        query = self._client.table(self.TABLE).select("*")
        if active_only:
            query = query.eq("is_active", True)
        if city is not None:
            escaped = city.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            query = query.ilike("city", escaped)
        rows = run(query.order("pincode"))
        return [ServiceAreaOut.model_validate(row) for row in rows]

    def get(self, area_id: UUID) -> ServiceAreaOut | None:
        rows = run(self._client.table(self.TABLE).select("*").eq("id", str(area_id)).limit(1))
        return ServiceAreaOut.model_validate(rows[0]) if rows else None

    def get_by_pincode(self, pincode: str) -> ServiceAreaOut | None:
        rows = run(self._client.table(self.TABLE).select("*").eq("pincode", pincode).limit(1))
        return ServiceAreaOut.model_validate(rows[0]) if rows else None

    def create(self, values: dict[str, Any]) -> ServiceAreaOut:
        rows = run(self._client.table(self.TABLE).insert(values), conflict=_DUPLICATE)
        return ServiceAreaOut.model_validate(rows[0])

    def update(self, area_id: UUID, values: dict[str, Any]) -> ServiceAreaOut | None:
        rows = run(
            self._client.table(self.TABLE).update(values).eq("id", str(area_id)),
            conflict=_DUPLICATE,
        )
        return ServiceAreaOut.model_validate(rows[0]) if rows else None

    def delete(self, area_id: UUID) -> bool:
        return bool(run(self._client.table(self.TABLE).delete().eq("id", str(area_id))))
