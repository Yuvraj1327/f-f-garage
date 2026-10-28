"""Services, packages and extra charges."""

from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator

from app.domain.enums import ExtraChargeType, VehicleType
from app.schemas.common import Money, PatchModel, optional_text, single_line

ServiceName = Annotated[str, single_line(2, 80)]
CategoryName = Annotated[str, single_line(2, 60)]
PackageName = Annotated[str, single_line(2, 80)]
ChargeName = Annotated[str, single_line(2, 80)]
Description = Annotated[str | None, optional_text(1000)]
DisplayOrder = Annotated[int, Field(ge=0, le=10000)]
Duration = Annotated[int, Field(ge=5, le=1440)]  # minutes
WarrantyDays = Annotated[int, Field(ge=1, le=3650)]
CatalogTab = Literal["mechanic", "package", "repair", "engine"]
PartsPolicy = Literal["service_only", "parts_included", "parts_extra"]
RepairGroup = Annotated[str | None, optional_text(30)]
Badge = Annotated[str | None, optional_text(24)]


def _clean_inclusions(items: list[str]) -> list[str]:
    cleaned: list[str] = []
    seen: set[str] = set()
    for raw in items:
        text = " ".join(raw.split())
        if not text:
            continue
        if len(text) > 120:
            raise ValueError("Each inclusion must be at most 120 characters")
        if text.lower() not in seen:
            seen.add(text.lower())
            cleaned.append(text)
    if len(cleaned) > 30:
        raise ValueError("At most 30 inclusions are allowed")
    return cleaned


Inclusions = Annotated[list[str], AfterValidator(_clean_inclusions)]


def _clean_url(value: str | None) -> str | None:
    """A picture address: https only (blank clears it)."""
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    if not text.startswith("https://") or len(text) > 500 or " " in text:
        raise ValueError("Use a picture link that starts with https:// (at most 500 characters)")
    return text


ImageUrl = Annotated[str | None, AfterValidator(_clean_url)]


# ---- Services --------------------------------------------------------------------------


class ServiceCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: ServiceName
    vehicle_type: VehicleType
    category: CategoryName = "General"
    description: Description = None
    # Which tab of the customer's service screen it appears in.
    catalog_tab: CatalogTab = "package"
    # Only for the "repair" tab: the filter it is listed under (Brakes, Cables, ...).
    repair_group: RepairGroup = None
    image_url: ImageUrl = None
    badge: Badge = None
    display_order: DisplayOrder = 0
    is_active: bool = True


class ServiceUpdate(PatchModel):
    """The vehicle type is fixed once a service exists (create a new service instead)."""

    nullable = frozenset({"description", "repair_group", "image_url", "badge"})

    name: ServiceName | None = None
    category: CategoryName | None = None
    description: Description = None
    catalog_tab: CatalogTab | None = None
    repair_group: RepairGroup = None
    image_url: ImageUrl = None
    badge: Badge = None
    display_order: DisplayOrder | None = None
    is_active: bool | None = None


class ServiceOut(BaseModel):
    id: UUID
    name: str
    vehicle_type: VehicleType
    category: str
    description: str | None = None
    catalog_tab: str = "package"
    repair_group: str | None = None
    image_url: str | None = None
    badge: str | None = None
    display_order: int
    is_active: bool
    created_at: datetime
    updated_at: datetime


# ---- Packages --------------------------------------------------------------------------


class PackageCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: PackageName
    description: Description = None
    price: Money
    # The crossed-out price shown next to `price` (must not be lower than it).
    original_price: Money | None = None
    inclusions: Inclusions = Field(default_factory=list)
    exclusions: Inclusions = Field(default_factory=list)
    estimated_duration_minutes: Duration | None = None
    warranty_days: WarrantyDays | None = None
    parts_policy: PartsPolicy = "service_only"
    parts_note: Annotated[str | None, optional_text(300)] = None
    display_order: DisplayOrder = 0
    is_active: bool = True

    @model_validator(mode="after")
    def _original_not_below_price(self) -> "PackageCreate":
        if self.original_price is not None and self.original_price < self.price:
            raise ValueError("The original price cannot be lower than the price")
        return self


class PackageUpdate(PatchModel):
    nullable = frozenset(
        {
            "description",
            "estimated_duration_minutes",
            "original_price",
            "warranty_days",
            "parts_note",
        }
    )

    name: PackageName | None = None
    description: Description = None
    price: Money | None = None
    original_price: Money | None = None
    inclusions: Inclusions | None = None
    exclusions: Inclusions | None = None
    estimated_duration_minutes: Duration | None = None
    warranty_days: WarrantyDays | None = None
    parts_policy: PartsPolicy | None = None
    parts_note: Annotated[str | None, optional_text(300)] = None
    display_order: DisplayOrder | None = None
    is_active: bool | None = None


class PackageOut(BaseModel):
    id: UUID
    service_id: UUID
    name: str
    description: str | None = None
    price: Decimal
    original_price: Decimal | None = None
    inclusions: list[str] = Field(default_factory=list)
    exclusions: list[str] = Field(default_factory=list)
    estimated_duration_minutes: int | None = None
    warranty_days: int | None = None
    parts_policy: str = "service_only"
    parts_note: str | None = None
    display_order: int
    is_active: bool
    created_at: datetime
    updated_at: datetime


# ---- Extra charges ---------------------------------------------------------------------


class ExtraChargeCreate(BaseModel):
    """`package_id` empty = applies to every package of the service."""

    model_config = ConfigDict(extra="forbid")

    charge_type: ExtraChargeType = ExtraChargeType.OTHER
    name: ChargeName
    description: Description = None
    # None = charged at actuals (e.g. a spare part priced on the day).
    amount: Money | None = None
    package_id: UUID | None = None
    is_active: bool = True


class ExtraChargeUpdate(PatchModel):
    """Which service/package a charge belongs to is fixed (delete and re-add to move it)."""

    nullable = frozenset({"description", "amount"})

    charge_type: ExtraChargeType | None = None
    name: ChargeName | None = None
    description: Description = None
    amount: Money | None = None
    is_active: bool | None = None


class ExtraChargeOut(BaseModel):
    id: UUID
    service_id: UUID
    package_id: UUID | None = None
    charge_type: ExtraChargeType
    name: str
    description: str | None = None
    amount: Decimal | None = None
    is_active: bool
    created_at: datetime
    updated_at: datetime


# ---- Composites ------------------------------------------------------------------------


class PackageDetail(PackageOut):
    """A package with the extra charges that apply to it specifically."""

    extra_charges: list[ExtraChargeOut] = Field(default_factory=list)


class ServiceDetail(ServiceOut):
    """A service with its packages and the extra charges that apply to all of them."""

    packages: list[PackageDetail] = Field(default_factory=list)
    extra_charges: list[ExtraChargeOut] = Field(default_factory=list)
