"""Serviceable PIN codes."""

import logging
from uuid import UUID

from app.core.errors import NotFoundError
from app.db.service_area_repository import ServiceAreaRepository
from app.schemas.profile import ProfileOut
from app.schemas.service_area import (
    PincodeCheck,
    ServiceAreaCreate,
    ServiceAreaOut,
    ServiceAreaUpdate,
)

logger = logging.getLogger(__name__)


class ServiceAreaService:
    def __init__(self, areas: ServiceAreaRepository) -> None:
        self._areas = areas

    def check_pincode(self, pincode: str) -> PincodeCheck:
        """Customer-facing. An inactive area looks exactly like an unknown one."""
        area = self._areas.get_by_pincode(pincode)
        if area is None or not area.is_active:
            return PincodeCheck(pincode=pincode, serviceable=False)
        return PincodeCheck(
            pincode=pincode,
            serviceable=True,
            area_name=area.area_name,
            city=area.city,
            state=area.state,
        )

    def list_areas(self, *, city: str | None = None) -> list[ServiceAreaOut]:
        return self._areas.list(city=city)

    def get_area(self, area_id: UUID) -> ServiceAreaOut:
        area = self._areas.get(area_id)
        if area is None:
            raise NotFoundError("Service area not found")
        return area

    def create_area(self, admin: ProfileOut, payload: ServiceAreaCreate) -> ServiceAreaOut:
        area = self._areas.create(payload.model_dump(mode="json"))
        logger.info("admin %s added service area %s (%s)", admin.id, area.id, area.pincode)
        return area

    def update_area(
        self, admin: ProfileOut, area_id: UUID, payload: ServiceAreaUpdate
    ) -> ServiceAreaOut:
        area = self._areas.update(area_id, payload.to_update_values())
        if area is None:
            raise NotFoundError("Service area not found")
        logger.info(
            "admin %s updated service area %s (%s)",
            admin.id,
            area_id,
            ", ".join(sorted(payload.model_fields_set)),
        )
        return area

    def delete_area(self, admin: ProfileOut, area_id: UUID) -> None:
        """Removes the PIN code. Past bookings keep their own copy of the PIN."""
        if not self._areas.delete(area_id):
            raise NotFoundError("Service area not found")
        logger.info("admin %s removed service area %s", admin.id, area_id)
