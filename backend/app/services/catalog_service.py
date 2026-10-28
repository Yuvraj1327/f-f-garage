"""Service catalogue: what customers can browse and what admins manage."""

import logging
from collections import defaultdict
from uuid import UUID

from app.core.errors import (
    ConflictError,
    NotFoundError,
    ServiceUnavailableError,
    UnprocessableError,
)
from app.db.catalog_repository import CatalogRepository
from app.domain.enums import VehicleType
from app.schemas.catalog import (
    CategoryCreate,
    CategoryOut,
    CategoryReorder,
    CategoryUpdate,
    ExtraChargeCreate,
    ExtraChargeOut,
    ExtraChargeUpdate,
    ImageUploadOut,
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
from app.services.image_storage import ImageKind, ImageStorage, check_image

logger = logging.getLogger(__name__)


# The home category of each tab, for a service that names none.
_TAB_HOME = {
    "mechanic": "tab_mechanic",
    "package": "tab_package",
    "engine": "tab_engine",
    "repair": "other_repairs",
}
_PICTURE_FIELDS = ("image_url", "banner_url", "thumbnail_url")


def _service_pictures(service: ServiceOut) -> set[str]:
    urls = {u for u in (service.image_url, service.banner_url, service.thumbnail_url) if u}
    return urls | set(service.part_image_urls)


class CatalogService:
    def __init__(self, catalog: CatalogRepository, storage: ImageStorage | None = None) -> None:
        self._catalog = catalog
        self._storage = storage

    # ---- Reading (customers see active items only) -------------------------------------
    def list_active(
        self, vehicle_type: VehicleType | None = None, category: str | None = None
    ) -> list[ServiceDetail]:
        """Active services that have at least one active package (otherwise there is
        nothing to book). Packages and charges shown are the active ones."""
        services = self._catalog.list_services(
            vehicle_type=vehicle_type, category=category, active_only=True
        )
        hidden = {c.id for c in self._catalog.list_categories() if not c.is_active}
        services = [s for s in services if s.category_id not in hidden]
        details = self._compose(services, active_only=True)
        return [d for d in details if d.packages]

    def get_active(self, service_id: UUID) -> ServiceDetail:
        service = self._catalog.get_service(service_id, active_only=True)
        hidden = {c.id for c in self._catalog.list_categories() if not c.is_active}
        if service is not None and service.category_id not in hidden:
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

    # ---- Categories --------------------------------------------------------------------
    def list_categories(self, *, active_only: bool = True) -> list[CategoryOut]:
        return self._catalog.list_categories(active_only=active_only)

    def create_category(self, admin: ProfileOut, payload: CategoryCreate) -> CategoryOut:
        existing = self._catalog.list_categories()
        order = max((c.display_order for c in existing), default=0) + 10
        category = self._catalog.create_category(
            {**payload.model_dump(mode="json"), "display_order": min(order, 10000)}
        )
        logger.info("admin %s created category %s", admin.id, category.id)
        return category

    def update_category(
        self, admin: ProfileOut, category_id: UUID, payload: CategoryUpdate
    ) -> CategoryOut:
        current = self._catalog.get_category(category_id)
        if current is None:
            raise NotFoundError("Category not found")
        if payload.tab is not None and payload.tab != current.tab and current.system_key:
            raise UnprocessableError("This built-in category cannot move to another tab")
        category = self._catalog.update_category(category_id, payload.to_update_values())
        if category is None:
            raise NotFoundError("Category not found")
        if category.name != current.name or category.tab != current.tab:
            # Services keep their category's name and tab (what older screens read).
            for service in self._catalog.list_services():
                if service.category_id == category_id:
                    self._catalog.update_service(service.id, self._category_values(category))
        logger.info(
            "admin %s updated category %s (%s)",
            admin.id,
            category_id,
            ", ".join(sorted(payload.model_fields_set)),
        )
        return category

    def reorder_categories(self, admin: ProfileOut, payload: CategoryReorder) -> list[CategoryOut]:
        existing = self._catalog.list_categories()
        if set(payload.ids) != {c.id for c in existing}:
            raise UnprocessableError("Send every category exactly once")
        for position, category_id in enumerate(payload.ids, start=1):
            self._catalog.update_category(category_id, {"display_order": position * 10})
        logger.info("admin %s reordered the categories", admin.id)
        return self._catalog.list_categories()

    @staticmethod
    def _category_values(category: CategoryOut) -> dict:
        return {
            "category_id": str(category.id),
            "category": category.name,
            "catalog_tab": category.tab,
            "repair_group": category.name if category.tab == "repair" else None,
        }

    def _category_for(
        self, category_id: UUID | None, tab: str | None, group: str | None, text: str | None
    ) -> CategoryOut | None:
        """The category a service belongs to: the one named, else the one that matches its
        tab and group/category text, else the home category of its tab."""
        if category_id is not None:
            category = self._catalog.get_category(category_id)
            if category is None:
                raise UnprocessableError("That category does not exist")
            return category
        categories = self._catalog.list_categories()
        wanted = (group or text or "").strip().lower()
        for category in categories:
            if category.tab == (tab or "package") and category.name.lower() == wanted:
                return category
        home = _TAB_HOME.get(tab or "package")
        return next((c for c in categories if c.system_key == home), None)

    # ---- Services ----------------------------------------------------------------------
    def create_service(self, admin: ProfileOut, payload: ServiceCreate) -> ServiceDetail:
        values = payload.model_dump(mode="json")
        category = self._category_for(
            payload.category_id,
            payload.catalog_tab,
            payload.repair_group,
            payload.category,
        )
        if category is not None:
            values.update(self._category_values(category))
        service = self._catalog.create_service(values)
        logger.info("admin %s created service %s", admin.id, service.id)
        return ServiceDetail(**service.model_dump())

    def update_service(
        self, admin: ProfileOut, service_id: UUID, payload: ServiceUpdate
    ) -> ServiceDetail:
        before = self._require_service(service_id)
        values = payload.to_update_values()
        fields = payload.model_fields_set
        if fields & {"category_id", "catalog_tab", "repair_group", "category"}:
            category = self._category_for(
                payload.category_id if "category_id" in fields else None,
                payload.catalog_tab or before.catalog_tab,
                payload.repair_group if "repair_group" in fields else before.repair_group,
                payload.category or before.category,
            )
            if category is not None:
                values.update(self._category_values(category))
        service = self._catalog.update_service(service_id, values)
        if service is None:
            raise NotFoundError("Service not found")
        self._cleanup_pictures(_service_pictures(before) - _service_pictures(service))
        logger.info(
            "admin %s updated service %s (%s)", admin.id, service_id, ", ".join(sorted(fields))
        )
        return self._compose([service], active_only=False)[0]

    def delete_service(self, admin: ProfileOut, service_id: UUID) -> None:
        service = self._require_service(service_id)
        if service.system_key:
            raise ConflictError(
                "This is one of the built-in services. It can be edited or switched off, "
                "but not deleted."
            )
        if not self._catalog.delete_service(service_id):
            raise NotFoundError("Service not found")
        self._cleanup_pictures(_service_pictures(service))
        logger.info("admin %s deleted service %s", admin.id, service_id)

    def duplicate_service(self, admin: ProfileOut, service_id: UUID) -> ServiceDetail:
        """A switched-off copy (packages and extra charges included) to edit and publish."""
        original = self._compose([self._require_service(service_id)], active_only=False)[0]
        values = original.model_dump(
            mode="json",
            include={
                "vehicle_type",
                "category",
                "description",
                "short_description",
                "category_id",
                "catalog_tab",
                "repair_group",
                "image_url",
                "banner_url",
                "thumbnail_url",
                "part_image_urls",
                "supported_makes",
                "supported_models",
                "badge",
                "display_order",
            },
        )
        copy = None
        for attempt in range(1, 20):
            suffix = " (Copy)" if attempt == 1 else f" (Copy {attempt})"
            try:
                copy = self._catalog.create_service(
                    {
                        **values,
                        "name": f"{original.name[: 80 - len(suffix)]}{suffix}",
                        "is_active": False,
                    }
                )
                break
            except ConflictError:
                continue
        if copy is None:
            raise ConflictError("Rename the existing copies first")
        package_ids: dict[UUID, UUID] = {}
        keep = {
            "name", "description", "price", "original_price", "inclusions", "exclusions",
            "estimated_duration_minutes", "warranty_days", "advance_percent",
            "repeat_interval_days", "labour_charge", "included_parts", "parts_policy",
            "parts_note", "display_order", "is_active",
        }  # fmt: skip
        for package in original.packages:
            made = self._catalog.create_package(
                copy.id, package.model_dump(mode="json", include=keep)
            )
            package_ids[package.id] = made.id
        extras = [
            *original.extra_charges,
            *(e for p in original.packages for e in p.extra_charges),
        ]
        for charge in extras:
            data = charge.model_dump(
                mode="json",
                include={"charge_type", "name", "description", "amount", "is_active"},
            )
            if charge.package_id is not None:
                data["package_id"] = str(package_ids[charge.package_id])
            self._catalog.create_extra_charge(copy.id, data)
        logger.info("admin %s duplicated service %s as %s", admin.id, service_id, copy.id)
        return self._compose([copy], active_only=False)[0]

    # ---- Pictures ----------------------------------------------------------------------
    def upload_image(self, admin: ProfileOut, kind: ImageKind, data: bytes) -> ImageUploadOut:
        if self._storage is None:
            raise ServiceUnavailableError(
                "Picture uploads are not available right now",
                log_message="image storage is not configured",
            )
        content_type, extension = check_image(data)
        url = self._storage.upload(kind, data, content_type, extension)
        logger.info("admin %s uploaded a %s picture", admin.id, kind)
        return ImageUploadOut(url=url, kind=kind)

    def discard_image(self, admin: ProfileOut, url: str) -> None:
        """For a picture that was uploaded but never saved on a service (the admin left the
        form). Does nothing when the picture is in use or not ours."""
        self._cleanup_pictures({url})
        logger.info("admin %s discarded an unsaved picture", admin.id)

    def _cleanup_pictures(self, urls: set[str]) -> None:
        """Deletes pictures nobody uses any more (our own storage only)."""
        if not urls or self._storage is None:
            return
        still_used: set[str] = set()
        for service in self._catalog.list_services():
            still_used |= _service_pictures(service)
        for url in urls - still_used:
            if self._storage.owns(url):
                self._storage.delete(url)

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
        current = self._catalog.get_package(package_id)
        if current is None:
            raise NotFoundError("Package not found")
        fields = payload.model_fields_set
        price = payload.price if "price" in fields else current.price
        original = payload.original_price if "original_price" in fields else current.original_price
        labour = payload.labour_charge if "labour_charge" in fields else current.labour_charge
        if original is not None and price is not None and original < price:
            raise UnprocessableError("The original price cannot be lower than the price")
        if labour is not None and price is not None and labour > price:
            raise UnprocessableError("The labour charge cannot be higher than the price")
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
