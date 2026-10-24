"""In-memory repositories for the Phase 3 tests. They enforce the same uniqueness and
overlap rules as the database so the services are exercised against realistic failures."""

import uuid
from datetime import UTC, date, datetime, time
from typing import Any
from uuid import UUID

from app.core.errors import ConflictError
from app.domain.enums import VehicleType
from app.schemas.availability import ExceptionOut, TimeSlotOut
from app.schemas.catalog import ExtraChargeOut, PackageOut, ServiceOut
from app.schemas.service_area import ServiceAreaOut


def _now() -> datetime:
    return datetime.now(UTC)


def _stamp(values: dict[str, Any]) -> dict[str, Any]:
    return {"id": uuid.uuid4(), "created_at": _now(), "updated_at": _now(), **values}


class FakeCatalogRepository:
    def __init__(self) -> None:
        self.services: dict[UUID, ServiceOut] = {}
        self.packages: dict[UUID, PackageOut] = {}
        self.extras: dict[UUID, ExtraChargeOut] = {}

    # services
    def list_services(self, *, vehicle_type=None, category=None, active_only=False):
        rows = list(self.services.values())
        if vehicle_type is not None:
            rows = [s for s in rows if s.vehicle_type == vehicle_type]
        if category is not None:
            rows = [s for s in rows if s.category.lower() == category.lower()]
        if active_only:
            rows = [s for s in rows if s.is_active]
        return sorted(rows, key=lambda s: (s.vehicle_type, s.display_order, s.name))

    def get_service(self, service_id, *, active_only=False):
        s = self.services.get(service_id)
        return s if s and (s.is_active or not active_only) else None

    def _check_service_name(self, vehicle_type, name, ignore=None):
        for s in self.services.values():
            if s.id != ignore and s.vehicle_type == vehicle_type and s.name.lower() == name.lower():
                raise ConflictError("A service with this name already exists")

    def create_service(self, values):
        self._check_service_name(VehicleType(values["vehicle_type"]), values["name"])
        s = ServiceOut(**_stamp(values))
        self.services[s.id] = s
        return s

    def update_service(self, service_id, values):
        s = self.services.get(service_id)
        if s is None:
            return None
        if "name" in values:
            self._check_service_name(s.vehicle_type, values["name"], ignore=s.id)
        s = s.model_copy(update={**values, "updated_at": _now()})
        self.services[service_id] = ServiceOut.model_validate(s.model_dump())
        return self.services[service_id]

    # packages
    def list_packages(self, service_ids, *, active_only=False):
        rows = [p for p in self.packages.values() if p.service_id in service_ids]
        if active_only:
            rows = [p for p in rows if p.is_active]
        return sorted(rows, key=lambda p: (p.display_order, p.price))

    def get_package(self, package_id):
        return self.packages.get(package_id)

    def create_package(self, service_id, values):
        for p in self.packages.values():
            if p.service_id == service_id and p.name.lower() == values["name"].lower():
                raise ConflictError("This service already has a package with this name")
        p = PackageOut(**_stamp({**values, "service_id": service_id}))
        self.packages[p.id] = p
        return p

    def update_package(self, package_id, values):
        p = self.packages.get(package_id)
        if p is None:
            return None
        self.packages[package_id] = PackageOut.model_validate(
            p.model_copy(update={**values, "updated_at": _now()}).model_dump()
        )
        return self.packages[package_id]

    # extras
    def list_extra_charges(self, service_ids, *, active_only=False):
        rows = [e for e in self.extras.values() if e.service_id in service_ids]
        if active_only:
            rows = [e for e in rows if e.is_active]
        return sorted(rows, key=lambda e: (e.charge_type, e.name))

    def get_extra_charge(self, charge_id):
        return self.extras.get(charge_id)

    def create_extra_charge(self, service_id, values):
        e = ExtraChargeOut(**_stamp({**values, "service_id": service_id}))
        self.extras[e.id] = e
        return e

    def update_extra_charge(self, charge_id, values):
        e = self.extras.get(charge_id)
        if e is None:
            return None
        self.extras[charge_id] = ExtraChargeOut.model_validate(
            e.model_copy(update={**values, "updated_at": _now()}).model_dump()
        )
        return self.extras[charge_id]

    def delete_extra_charge(self, charge_id):
        return self.extras.pop(charge_id, None) is not None


class FakeServiceAreaRepository:
    def __init__(self) -> None:
        self.rows: dict[UUID, ServiceAreaOut] = {}

    def add(self, pincode="462001", *, is_active=True, city="Bhopal") -> ServiceAreaOut:
        area = ServiceAreaOut(
            **_stamp(
                {
                    "pincode": pincode,
                    "area_name": "New Market",
                    "city": city,
                    "state": "Madhya Pradesh",
                    "is_active": is_active,
                }
            )
        )
        self.rows[area.id] = area
        return area

    def list(self, *, active_only=False, city=None):
        rows = list(self.rows.values())
        if active_only:
            rows = [a for a in rows if a.is_active]
        if city:
            rows = [a for a in rows if a.city.lower() == city.lower()]
        return sorted(rows, key=lambda a: a.pincode)

    def get(self, area_id):
        return self.rows.get(area_id)

    def get_by_pincode(self, pincode):
        return next((a for a in self.rows.values() if a.pincode == pincode), None)

    def create(self, values):
        if self.get_by_pincode(values["pincode"]):
            raise ConflictError("A service area with this PIN code already exists")
        area = ServiceAreaOut(**_stamp(values))
        self.rows[area.id] = area
        return area

    def update(self, area_id, values):
        a = self.rows.get(area_id)
        if a is None:
            return None
        other = self.get_by_pincode(values.get("pincode", a.pincode))
        if other and other.id != area_id:
            raise ConflictError("A service area with this PIN code already exists")
        self.rows[area_id] = a.model_copy(update={**values, "updated_at": _now()})
        return self.rows[area_id]

    def delete(self, area_id):
        return self.rows.pop(area_id, None) is not None


class FakeAvailabilityRepository:
    def __init__(self) -> None:
        self.slots: dict[UUID, TimeSlotOut] = {}
        self.exceptions: dict[UUID, ExceptionOut] = {}
        self.booked: dict[tuple[date, time, time], int] = {}

    def add_slot(self, start="09:00", end="11:00", capacity=1, days=None, is_active=True):
        slot = TimeSlotOut(
            **_stamp(
                {
                    "start_time": time.fromisoformat(start),
                    "end_time": time.fromisoformat(end),
                    "capacity": capacity,
                    "days_of_week": days or [1, 2, 3, 4, 5, 6, 7],
                    "is_active": is_active,
                }
            )
        )
        self.slots[slot.id] = slot
        return slot

    def _check_overlap(self, candidate: dict[str, Any], ignore: UUID | None = None) -> None:
        if not candidate["is_active"]:
            return
        for s in self.slots.values():
            if (
                s.id != ignore
                and s.is_active
                and set(s.days_of_week) & set(candidate["days_of_week"])
                and s.start_time < candidate["end_time"]
                and candidate["start_time"] < s.end_time
            ):
                raise ConflictError("This time slot overlaps another active slot")

    def list_slots(self, *, active_only=False):
        rows = [s for s in self.slots.values() if s.is_active or not active_only]
        return sorted(rows, key=lambda s: (s.start_time, s.end_time))

    def get_slot(self, slot_id):
        return self.slots.get(slot_id)

    def create_slot(self, values):
        data = {
            "capacity": 1,
            "days_of_week": [1, 2, 3, 4, 5, 6, 7],
            "is_active": True,
            **values,
        }
        data["start_time"] = time.fromisoformat(data["start_time"])
        data["end_time"] = time.fromisoformat(data["end_time"])
        self._check_overlap(data)
        slot = TimeSlotOut(**_stamp(data))
        self.slots[slot.id] = slot
        return slot

    def update_slot(self, slot_id, values):
        s = self.slots.get(slot_id)
        if s is None:
            return None
        data = s.model_dump()
        data.update(values)
        for key in ("start_time", "end_time"):
            if isinstance(data[key], str):
                data[key] = time.fromisoformat(data[key])
        self._check_overlap(data, ignore=slot_id)
        self.slots[slot_id] = TimeSlotOut.model_validate({**data, "updated_at": _now()})
        return self.slots[slot_id]

    def delete_slot(self, slot_id):
        existed = self.slots.pop(slot_id, None) is not None
        self.exceptions = {k: v for k, v in self.exceptions.items() if v.time_slot_id != slot_id}
        return existed

    def list_exceptions(self, start, end):
        rows = [e for e in self.exceptions.values() if start <= e.exception_date <= end]
        return sorted(rows, key=lambda e: e.exception_date)

    def get_exception(self, exception_id):
        return self.exceptions.get(exception_id)

    def create_exception(self, values):
        data = {"is_open": False, "capacity": None, "reason": None, "time_slot_id": None, **values}
        data["exception_date"] = date.fromisoformat(data["exception_date"])
        if data["time_slot_id"] is not None:
            data["time_slot_id"] = UUID(str(data["time_slot_id"]))
        for e in self.exceptions.values():
            if (e.exception_date, e.time_slot_id) == (data["exception_date"], data["time_slot_id"]):
                raise ConflictError("There is already an entry for this date and slot")
        e = ExceptionOut(**_stamp(data))
        self.exceptions[e.id] = e
        return e

    def update_exception(self, exception_id, values):
        e = self.exceptions.get(exception_id)
        if e is None:
            return None
        self.exceptions[exception_id] = e.model_copy(update={**values, "updated_at": _now()})
        return self.exceptions[exception_id]

    def delete_exception(self, exception_id):
        return self.exceptions.pop(exception_id, None) is not None

    def booked_counts(self, start, end):
        return {k: v for k, v in self.booked.items() if start <= k[0] <= end}
