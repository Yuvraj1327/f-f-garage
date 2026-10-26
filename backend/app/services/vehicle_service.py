"""A customer's saved vehicles. Every call is scoped to that customer: someone
else's vehicle is reported as not found, never as forbidden."""

from uuid import UUID

from app.core.errors import ConflictError, NotFoundError
from app.db.vehicle_repository import VehicleRepository
from app.schemas.profile import ProfileOut
from app.schemas.vehicle import VehicleCreate, VehicleOut, VehicleUpdate

MAX_VEHICLES = 10
_NOT_FOUND = "Vehicle not found"


class VehicleService:
    def __init__(self, vehicles: VehicleRepository) -> None:
        self._vehicles = vehicles

    def list(self, customer: ProfileOut) -> list[VehicleOut]:
        return self._vehicles.list_for(customer.id)

    def get(self, customer: ProfileOut, vehicle_id: UUID) -> VehicleOut:
        found = self._vehicles.get(customer.id, vehicle_id)
        if found is None:
            raise NotFoundError(_NOT_FOUND)
        return found

    def create(self, customer: ProfileOut, payload: VehicleCreate) -> VehicleOut:
        if len(self._vehicles.list_for(customer.id)) >= MAX_VEHICLES:
            raise ConflictError(f"You can save up to {MAX_VEHICLES} vehicles")
        return self._vehicles.create(customer.id, payload.model_dump(mode="json"))

    def update(self, customer: ProfileOut, vehicle_id: UUID, payload: VehicleUpdate) -> VehicleOut:
        updated = self._vehicles.update(customer.id, vehicle_id, payload.to_update_values())
        if updated is None:
            raise NotFoundError(_NOT_FOUND)
        return updated

    def delete(self, customer: ProfileOut, vehicle_id: UUID) -> None:
        if not self._vehicles.delete(customer.id, vehicle_id):
            raise NotFoundError(_NOT_FOUND)
