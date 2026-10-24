"""Service catalogue: what customers can browse and what admins manage."""

import logging
from collections import defaultdict
from uuid import UUID

from app.core.errors import NotFoundError, UnprocessableError
from app.db.catalog_repository import CatalogRepository
from app.domain.enums import VehicleType
from app.schemas.catalog import (
    ExtraChargeCreate,
    ExtraChargeOut,
    ExtraChargeUpdate,
    PackageCreate,
    PackageDetail,
    PackageOut,
    PackageUpdate,
    ServiceCreate,
    ServiceDetail,
    ServiceOut,
    ServiceUpdate,
)
from app.schemas.profile import ProfileOut

logger = logging.getLogger(__name__)


class CatalogService:
    def __init__(self, catalog: CatalogRepository) -> None:
        self._catalog = catalog

    # ---- Reading (customers see active items only) -------------------------------------
    def list_active(
        self, vehicle_type: VehicleType | None = None, category: str | None = None
    ) -> list[ServiceDetail]:
        """Active services that have at least one active package (otherwise there is
        nothing to book). Packages and charges shown are the active ones."""
        services = self._catalog.list_services(
            vehicle_type=vehicle_type, category=category, active_only=True
        )
        details = self._compose(services, active_only=True)
        return [d for d in details if d.packages]

    def get_active(self, service_id: UUID) -> ServiceDetail:
        service = self._catalog.get_service(service_id, active_only=True)
        if service is not None:
            detail = self._compose([service], active_only=True)[0]
            if detail.packages:
                return detail
        raise NotFoundError("Service not found")

    # ---- Reading (admins see everything) -----------------------------------------------
    def list_all(
        self, vehicle_type: VehicleType | None = None, category: str | None = None
    ) -> list[ServiceDetail]:
        services = self._catalog.list_services(vehicle_type=vehicle_type, category=category)
        return self._compose(services, active_only=False)

    def get(self, service_id: UUID) -> ServiceDetail:
        return self._compose([self._require_service(service_id)], active_only=False)[0]

    # ---- Services ----------------------------------------------------------------------
    def create_service(self, admin: ProfileOut, payload: ServiceCreate) -> ServiceDetail:
        service = self._catalog.create_service(payload.model_dump(mode="json"))
        logger.info("admin %s created service %s", admin.id, service.id)
        return ServiceDetail(**service.model_dump())

    def update_service(
        self, admin: ProfileOut, service_id: UUID, payload: ServiceUpdate
    ) -> ServiceDetail:
        service = self._catalog.update_service(service_id, payload.to_update_values())
        if service is None:
            raise NotFoundError("Service not found")
        logger.info(
            "admin %s updated service %s (%s)",
            admin.id,
            service_id,
            ", ".join(sorted(payload.model_fields_set)),
        )
        return self._compose([service], active_only=False)[0]

    # ---- Packages ----------------------------------------------------------------------
    def create_package(
        self, admin: ProfileOut, service_id: UUID, payload: PackageCreate
    ) -> PackageDetail:
        self._require_service(service_id)
        package = self._catalog.create_package(service_id, payload.model_dump(mode="json"))
        logger.info("admin %s created package %s in service %s", admin.id, package.id, service_id)
        return PackageDetail(**package.model_dump())

    def update_package(
        self, admin: ProfileOut, package_id: UUID, payload: PackageUpdate
    ) -> PackageDetail:
        package = self._catalog.update_package(package_id, payload.to_update_values())
        if package is None:
            raise NotFoundError("Package not found")
        logger.info(
            "admin %s updated package %s (%s)",
            admin.id,
            package_id,
            ", ".join(sorted(payload.model_fields_set)),
        )
        extras = [
            e
            for e in self._catalog.list_extra_charges([package.service_id])
            if e.package_id == package.id
        ]
        return PackageDetail(**package.model_dump(), extra_charges=extras)

    # ---- Extra charges -----------------------------------------------------------------
    def create_extra_charge(
        self, admin: ProfileOut, service_id: UUID, payload: ExtraChargeCreate
    ) -> ExtraChargeOut:
        self._require_service(service_id)
        if payload.package_id is not None:
            package = self._catalog.get_package(payload.package_id)
            if package is None or package.service_id != service_id:
                raise UnprocessableError("That package does not belong to this service")
        charge = self._catalog.create_extra_charge(service_id, payload.model_dump(mode="json"))
        logger.info(
            "admin %s created extra charge %s in service %s", admin.id, charge.id, service_id
        )
        return charge

    def update_extra_charge(
        self, admin: ProfileOut, charge_id: UUID, payload: ExtraChargeUpdate
    ) -> ExtraChargeOut:
        charge = self._catalog.update_extra_charge(charge_id, payload.to_update_values())
        if charge is None:
            raise NotFoundError("Extra charge not found")
        logger.info("admin %s updated extra charge %s", admin.id, charge_id)
        return charge

    def delete_extra_charge(self, admin: ProfileOut, charge_id: UUID) -> None:
        if not self._catalog.delete_extra_charge(charge_id):
            raise NotFoundError("Extra charge not found")
        logger.info("admin %s deleted extra charge %s", admin.id, charge_id)

    # ---- Helpers -----------------------------------------------------------------------
    def _require_service(self, service_id: UUID) -> ServiceOut:
        service = self._catalog.get_service(service_id)
        if service is None:
            raise NotFoundError("Service not found")
        return service

    def _compose(self, services: list[ServiceOut], *, active_only: bool) -> list[ServiceDetail]:
        ids = [s.id for s in services]
        packages = self._catalog.list_packages(ids, active_only=active_only)
        extras = self._catalog.list_extra_charges(ids, active_only=active_only)

        packages_by_service: dict[UUID, list[PackageOut]] = defaultdict(list)
        for package in packages:
            packages_by_service[package.service_id].append(package)
        service_wide: dict[UUID, list[ExtraChargeOut]] = defaultdict(list)
        per_package: dict[UUID, list[ExtraChargeOut]] = defaultdict(list)
        for charge in extras:
            if charge.package_id is None:
                service_wide[charge.service_id].append(charge)
            else:
                per_package[charge.package_id].append(charge)

        return [
            ServiceDetail(
                **service.model_dump(),
                packages=[
                    PackageDetail(**package.model_dump(), extra_charges=per_package[package.id])
                    for package in packages_by_service[service.id]
                ],
                extra_charges=service_wide[service.id],
            )
            for service in services
        ]
