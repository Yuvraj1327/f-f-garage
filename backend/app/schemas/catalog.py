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
ShortDescription = Annotated[str | None, optional_text(140)]
AdvancePercent = Annotated[Decimal, Field(ge=1, le=100, max_digits=5, decimal_places=2)]
RepeatDays = Annotated[int, Field(ge=1, le=3650)]


def _clean_urls(items: list[str]) -> list[str]:
    cleaned: list[str] = []
    for raw in items:
        url = _clean_url(raw)
        if url and url not in cleaned:
            cleaned.append(url)
    if len(cleaned) > 8:
        raise ValueError("At most 8 part pictures are allowed")
    return cleaned


def _clean_names(max_items: int):
    """A list of make/model names: trimmed, no blanks or duplicates (any case)."""

    def check(items: list[str]) -> list[str]:
        cleaned: list[str] = []
        seen: set[str] = set()
        for raw in items:
            text = " ".join(raw.split())
            if not text:
                continue
            if len(text) > 60:
                raise ValueError("Each name must be at most 60 characters")
            if text.lower() not in seen:
                seen.add(text.lower())
                cleaned.append(text)
        if len(cleaned) > max_items:
            raise ValueError(f"At most {max_items} entries are allowed")
        return cleaned

    return AfterValidator(check)


PartImages = Annotated[list[str], AfterValidator(_clean_urls)]
Makes = Annotated[list[str], _clean_names(60)]
Models = Annotated[list[str], _clean_names(200)]
IconKey = Annotated[str | None, optional_text(30)]


# ---- Services --------------------------------------------------------------------------


class ServiceCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: ServiceName
    vehicle_type: VehicleType
    category: CategoryName = "General"
    description: Description = None
    short_description: ShortDescription = None
    # The managed category. When given, the tab, repair group and category text are taken
    # from it; when left out they are worked out from the fields below.
    category_id: UUID | None = None
    # Which tab of the customer's service screen it appears in.
    catalog_tab: CatalogTab = "package"
    # Only for the "repair" tab: the filter it is listed under (Brakes, Cables, ...).
    repair_group: RepairGroup = None
    image_url: ImageUrl = None
    banner_url: ImageUrl = None
    thumbnail_url: ImageUrl = None
    part_image_urls: PartImages = Field(default_factory=list)
    # Empty = every vehicle of the type; otherwise only these makes / models.
    supported_makes: Makes = Field(default_factory=list)
    supported_models: Models = Field(default_factory=list)
    badge: Badge = None
    display_order: DisplayOrder = 0
    is_active: bool = True


class ServiceUpdate(PatchModel):
    """The vehicle type is fixed once a service exists (create a new service instead)."""

    nullable = frozenset(
        {
            "description",
            "short_description",
            "repair_group",
            "image_url",
            "banner_url",
            "thumbnail_url",
            "badge",
        }
    )

    name: ServiceName | None = None
    category: CategoryName | None = None
    description: Description = None
    short_description: ShortDescription = None
    category_id: UUID | None = None
    catalog_tab: CatalogTab | None = None
    repair_group: RepairGroup = None
    image_url: ImageUrl = None
    banner_url: ImageUrl = None
    thumbnail_url: ImageUrl = None
    part_image_urls: PartImages | None = None
    supported_makes: Makes | None = None
    supported_models: Models | None = None
    badge: Badge = None
    display_order: DisplayOrder | None = None
    is_active: bool | None = None


class ServiceOut(BaseModel):
    id: UUID
    name: str
    vehicle_type: VehicleType
    category: str
    description: str | None = None
    short_description: str | None = None
    category_id: UUID | None = None
    # Set on the 3 built-in services: they can be edited and switched off, never deleted.
    system_key: str | None = None
    catalog_tab: str = "package"
    repair_group: str | None = None
    image_url: str | None = None
    banner_url: str | None = None
    thumbnail_url: str | None = None
    part_image_urls: list[str] = Field(default_factory=list)
    supported_makes: list[str] = Field(default_factory=list)
    supported_models: list[str] = Field(default_factory=list)
    badge: str | None = None
    display_order: int
    is_active: bool
    created_at: datetime
    updated_at: datetime

    @model_validator(mode="after")
    def _thumbnail_falls_back_to_the_old_picture(self) -> "ServiceOut":
        if self.thumbnail_url is None and self.image_url is not None:
            self.thumbnail_url = self.image_url
        return self


# ---- Categories ------------------------------------------------------------------------


class CategoryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Annotated[str, single_line(2, 40)]
    tab: CatalogTab = "repair"
    icon_key: IconKey = None
    is_active: bool = True


class CategoryUpdate(PatchModel):
    nullable = frozenset({"icon_key"})

    name: Annotated[str, single_line(2, 40)] | None = None
    tab: CatalogTab | None = None
    icon_key: IconKey = None
    is_active: bool | None = None


class CategoryReorder(BaseModel):
    """Every category id, in the order they should appear."""

    model_config = ConfigDict(extra="forbid")

    ids: Annotated[list[UUID], Field(min_length=1, max_length=200)]

    @model_validator(mode="after")
    def _no_duplicates(self) -> "CategoryReorder":
        if len(set(self.ids)) != len(self.ids):
            raise ValueError("Each category may appear only once")
        return self


class CategoryOut(BaseModel):
    id: UUID
    name: str
    tab: str
    icon_key: str | None = None
    display_order: int
    is_active: bool
    system_key: str | None = None
    created_at: datetime
    updated_at: datetime


class ImageUploadOut(BaseModel):
    """Where an uploaded picture can be seen; save it on the service."""

    url: str
    kind: Literal["banner", "thumbnail", "part"]


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
    # Share of the total collected when booking; empty = the garage-wide default (20%).
    advance_percent: AdvancePercent | None = None
    repeat_interval_days: RepeatDays | None = None
    # The labour part of `price`, shown to the customer (price covers labour + service).
    labour_charge: Money | None = None
    included_parts: Inclusions = Field(default_factory=list)
    parts_policy: PartsPolicy = "service_only"
    parts_note: Annotated[str | None, optional_text(300)] = None
    display_order: DisplayOrder = 0
    is_active: bool = True

    @model_validator(mode="after")
    def _prices_make_sense(self) -> "PackageCreate":
        if self.original_price is not None and self.original_price < self.price:
            raise ValueError("The original price cannot be lower than the price")
        if self.labour_charge is not None and self.labour_charge > self.price:
            raise ValueError("The labour charge cannot be higher than the price")
        return self


class PackageUpdate(PatchModel):
    nullable = frozenset(
        {
            "description",
            "estimated_duration_minutes",
            "original_price",
            "warranty_days",
            "parts_note",
            "advance_percent",
            "repeat_interval_days",
            "labour_charge",
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
    advance_percent: AdvancePercent | None = None
    repeat_interval_days: RepeatDays | None = None
    labour_charge: Money | None = None
    included_parts: Inclusions | None = None
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
    advance_percent: Decimal | None = None
    repeat_interval_days: int | None = None
    labour_charge: Decimal | None = None
    included_parts: list[str] = Field(default_factory=list)
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
