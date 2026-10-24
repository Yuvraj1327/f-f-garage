"""Services, packages and extra charges in Supabase (service-role client)."""

from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.db.postgrest import run
from app.domain.enums import VehicleType
from app.schemas.catalog import ExtraChargeOut, PackageOut, ServiceOut


class CatalogRepository(Protocol):
    def list_services(
        self,
        *,
        vehicle_type: VehicleType | None = None,
        category: str | None = None,
        active_only: bool = False,
    ) -> list[ServiceOut]: ...

    def get_service(self, service_id: UUID, *, active_only: bool = False) -> ServiceOut | None: ...

    def create_service(self, values: dict[str, Any]) -> ServiceOut: ...

    def update_service(self, service_id: UUID, values: dict[str, Any]) -> ServiceOut | None: ...

    def list_packages(
        self, service_ids: list[UUID], *, active_only: bool = False
    ) -> list[PackageOut]: ...

    def get_package(self, package_id: UUID) -> PackageOut | None: ...

    def create_package(self, service_id: UUID, values: dict[str, Any]) -> PackageOut: ...

    def update_package(self, package_id: UUID, values: dict[str, Any]) -> PackageOut | None: ...

    def list_extra_charges(
        self, service_ids: list[UUID], *, active_only: bool = False
    ) -> list[ExtraChargeOut]: ...

    def get_extra_charge(self, charge_id: UUID) -> ExtraChargeOut | None: ...

    def create_extra_charge(self, service_id: UUID, values: dict[str, Any]) -> ExtraChargeOut: ...

    def update_extra_charge(
        self, charge_id: UUID, values: dict[str, Any]
    ) -> ExtraChargeOut | None: ...

    def delete_extra_charge(self, charge_id: UUID) -> bool: ...


class SupabaseCatalogRepository:
    SERVICES = "services"
    PACKAGES = "service_packages"
    EXTRAS = "extra_charges"

    def __init__(self, client: Client) -> None:
        self._client = client

    # ---- services ----------------------------------------------------------------------
    def list_services(
        self,
        *,
        vehicle_type: VehicleType | None = None,
        category: str | None = None,
        active_only: bool = False,
    ) -> list[ServiceOut]:
        query = self._client.table(self.SERVICES).select("*")
        if vehicle_type is not None:
            query = query.eq("vehicle_type", vehicle_type.value)
        if category is not None:
            query = query.ilike("category", _like_exact(category))
        if active_only:
            query = query.eq("is_active", True)
        rows = run(query.order("vehicle_type").order("display_order").order("name"))
        return [ServiceOut.model_validate(row) for row in rows]

    def get_service(self, service_id: UUID, *, active_only: bool = False) -> ServiceOut | None:
        query = self._client.table(self.SERVICES).select("*").eq("id", str(service_id))
        if active_only:
            query = query.eq("is_active", True)
        rows = run(query.limit(1))
        return ServiceOut.model_validate(rows[0]) if rows else None

    def create_service(self, values: dict[str, Any]) -> ServiceOut:
        rows = run(
            self._client.table(self.SERVICES).insert(values),
            conflict="A service with this name already exists for this vehicle type",
        )
        return ServiceOut.model_validate(rows[0])

    def update_service(self, service_id: UUID, values: dict[str, Any]) -> ServiceOut | None:
        rows = run(
            self._client.table(self.SERVICES).update(values).eq("id", str(service_id)),
            conflict="A service with this name already exists for this vehicle type",
        )
        return ServiceOut.model_validate(rows[0]) if rows else None

    # ---- packages ----------------------------------------------------------------------
    def list_packages(
        self, service_ids: list[UUID], *, active_only: bool = False
    ) -> list[PackageOut]:
        if not service_ids:
            return []
        query = (
            self._client.table(self.PACKAGES)
            .select("*")
            .in_("service_id", [str(i) for i in service_ids])
        )
        if active_only:
            query = query.eq("is_active", True)
        rows = run(query.order("display_order").order("price"))
        return [PackageOut.model_validate(row) for row in rows]

    def get_package(self, package_id: UUID) -> PackageOut | None:
        rows = run(self._client.table(self.PACKAGES).select("*").eq("id", str(package_id)).limit(1))
        return PackageOut.model_validate(rows[0]) if rows else None

    def create_package(self, service_id: UUID, values: dict[str, Any]) -> PackageOut:
        rows = run(
            self._client.table(self.PACKAGES).insert({**values, "service_id": str(service_id)}),
            conflict="This service already has a package with this name",
        )
        return PackageOut.model_validate(rows[0])

    def update_package(self, package_id: UUID, values: dict[str, Any]) -> PackageOut | None:
        rows = run(
            self._client.table(self.PACKAGES).update(values).eq("id", str(package_id)),
            conflict="This service already has a package with this name",
        )
        return PackageOut.model_validate(rows[0]) if rows else None

    # ---- extra charges -----------------------------------------------------------------
    def list_extra_charges(
        self, service_ids: list[UUID], *, active_only: bool = False
    ) -> list[ExtraChargeOut]:
        if not service_ids:
            return []
        query = (
            self._client.table(self.EXTRAS)
            .select("*")
            .in_("service_id", [str(i) for i in service_ids])
        )
        if active_only:
            query = query.eq("is_active", True)
        rows = run(query.order("charge_type").order("name"))
        return [ExtraChargeOut.model_validate(row) for row in rows]

    def get_extra_charge(self, charge_id: UUID) -> ExtraChargeOut | None:
        rows = run(self._client.table(self.EXTRAS).select("*").eq("id", str(charge_id)).limit(1))
        return ExtraChargeOut.model_validate(rows[0]) if rows else None

    def create_extra_charge(self, service_id: UUID, values: dict[str, Any]) -> ExtraChargeOut:
        rows = run(
            self._client.table(self.EXTRAS).insert({**values, "service_id": str(service_id)})
        )
        return ExtraChargeOut.model_validate(rows[0])

    def update_extra_charge(self, charge_id: UUID, values: dict[str, Any]) -> ExtraChargeOut | None:
        rows = run(self._client.table(self.EXTRAS).update(values).eq("id", str(charge_id)))
        return ExtraChargeOut.model_validate(rows[0]) if rows else None

    def delete_extra_charge(self, charge_id: UUID) -> bool:
        return bool(run(self._client.table(self.EXTRAS).delete().eq("id", str(charge_id))))


def _like_exact(value: str) -> str:
    """Case-insensitive exact match for ilike: escape the wildcard characters."""
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
