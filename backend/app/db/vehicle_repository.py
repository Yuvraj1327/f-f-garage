"""Customers' saved vehicles in Supabase (service-role client)."""

from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.db.postgrest import run
from app.schemas.vehicle import VehicleOut

_HINTS = {"customer_vehicles_registration_key": "You have already saved this vehicle"}


class VehicleRepository(Protocol):
    def list_for(self, customer_id: UUID) -> list[VehicleOut]: ...

    def get(self, customer_id: UUID, vehicle_id: UUID) -> VehicleOut | None:
        """The vehicle, only if it belongs to `customer_id`."""
        ...

    def create(self, customer_id: UUID, values: dict[str, Any]) -> VehicleOut: ...

    def update(
        self, customer_id: UUID, vehicle_id: UUID, values: dict[str, Any]
    ) -> VehicleOut | None: ...

    def delete(self, customer_id: UUID, vehicle_id: UUID) -> bool: ...


class SupabaseVehicleRepository:
    TABLE = "customer_vehicles"

    def __init__(self, client: Client) -> None:
        self._client = client

    def list_for(self, customer_id: UUID) -> list[VehicleOut]:
        rows = run(
            self._client.table(self.TABLE)
            .select("*")
            .eq("customer_id", str(customer_id))
            .order("created_at")
        )
        return [VehicleOut.model_validate(r) for r in rows]

    def get(self, customer_id: UUID, vehicle_id: UUID) -> VehicleOut | None:
        rows = run(
            self._client.table(self.TABLE)
            .select("*")
            .eq("id", str(vehicle_id))
            .eq("customer_id", str(customer_id))
            .limit(1)
        )
        return VehicleOut.model_validate(rows[0]) if rows else None

    def create(self, customer_id: UUID, values: dict[str, Any]) -> VehicleOut:
        rows = run(
            self._client.table(self.TABLE).insert({**values, "customer_id": str(customer_id)}),
            conflict_hints=_HINTS,
        )
        return VehicleOut.model_validate(rows[0])

    def update(
        self, customer_id: UUID, vehicle_id: UUID, values: dict[str, Any]
    ) -> VehicleOut | None:
        rows = run(
            self._client.table(self.TABLE)
            .update(values)
            .eq("id", str(vehicle_id))
            .eq("customer_id", str(customer_id)),
            conflict_hints=_HINTS,
        )
        return VehicleOut.model_validate(rows[0]) if rows else None

    def delete(self, customer_id: UUID, vehicle_id: UUID) -> bool:
        rows = run(
            self._client.table(self.TABLE)
            .delete()
            .eq("id", str(vehicle_id))
            .eq("customer_id", str(customer_id))
        )
        return bool(rows)
