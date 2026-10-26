import uuid
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from app.core.errors import ConflictError
from app.schemas.vehicle import VehicleOut


class FakeVehicles:
    """In-memory saved vehicles with the database's unique (customer, registration) rule."""

    def __init__(self) -> None:
        self.rows: dict[UUID, tuple[UUID, VehicleOut]] = {}

    def list_for(self, customer_id: UUID) -> list[VehicleOut]:
        return [v for c, v in self.rows.values() if c == customer_id]

    def get(self, customer_id: UUID, vehicle_id: UUID) -> VehicleOut | None:
        row = self.rows.get(vehicle_id)
        return row[1] if row and row[0] == customer_id else None

    def _check_unique(self, customer_id: UUID, registration: str, ignore: UUID | None) -> None:
        for vid, (c, v) in self.rows.items():
            if c == customer_id and vid != ignore and v.registration_number == registration:
                raise ConflictError("You have already saved this vehicle")

    def create(self, customer_id: UUID, values: dict[str, Any]) -> VehicleOut:
        self._check_unique(customer_id, values["registration_number"], None)
        vehicle = VehicleOut(id=uuid.uuid4(), created_at=datetime.now(UTC), **values)
        self.rows[vehicle.id] = (customer_id, vehicle)
        return vehicle

    def update(
        self, customer_id: UUID, vehicle_id: UUID, values: dict[str, Any]
    ) -> VehicleOut | None:
        current = self.get(customer_id, vehicle_id)
        if current is None:
            return None
        if "registration_number" in values:
            self._check_unique(customer_id, values["registration_number"], vehicle_id)
        updated = current.model_copy(update=values)
        self.rows[vehicle_id] = (customer_id, updated)
        return updated

    def delete(self, customer_id: UUID, vehicle_id: UUID) -> bool:
        if self.get(customer_id, vehicle_id) is None:
            return False
        del self.rows[vehicle_id]
        return True
