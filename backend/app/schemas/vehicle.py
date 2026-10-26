"""Saved vehicles: two-wheelers only (a bike or a scooter)."""

import re
from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import AfterValidator, BaseModel, ConfigDict

from app.domain.enums import VehicleType
from app.schemas.common import PatchModel, optional_text, single_line

# Standard Indian plates (MH12AB1234, DL1CAB1234) and the Bharat series (22BH1234AA).
_PLATE = re.compile(r"[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{4}|[0-9]{2}BH[0-9]{4}[A-Z]{1,2}")


def normalize_registration(raw: str) -> str:
    """Upper-case, with spaces and hyphens removed, then checked against the plate shapes."""
    value = re.sub(r"[\s-]+", "", raw).upper()
    if not _PLATE.fullmatch(value):
        raise ValueError("Enter a valid registration number, e.g. MH12AB1234")
    return value


Registration = Annotated[str, AfterValidator(normalize_registration)]
Make = Annotated[str, single_line(2, 40)]
Model = Annotated[str, single_line(1, 40)]
Nickname = Annotated[str | None, optional_text(30)]


def _one_line_nickname(value: str | None) -> str | None:
    return " ".join(value.split()) if value else None


class VehicleCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    vehicle_type: VehicleType
    registration_number: Registration
    make: Make
    model: Model
    nickname: Annotated[Nickname, AfterValidator(_one_line_nickname)] = None


class VehicleUpdate(PatchModel):
    nullable = frozenset({"nickname"})

    vehicle_type: VehicleType | None = None
    registration_number: Registration | None = None
    make: Make | None = None
    model: Model | None = None
    nickname: Annotated[Nickname, AfterValidator(_one_line_nickname)] = None


class VehicleOut(BaseModel):
    id: UUID
    vehicle_type: VehicleType
    registration_number: str
    make: str
    model: str
    nickname: str | None = None
    created_at: datetime
