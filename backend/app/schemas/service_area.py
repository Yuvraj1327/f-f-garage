"""Serviceable PIN codes."""

import re
from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import AfterValidator, BaseModel, ConfigDict

from app.schemas.common import PatchModel, single_line

_PIN = re.compile(r"[1-9][0-9]{5}")


def clean_pincode(raw: str) -> str:
    value = raw.strip().replace(" ", "")
    if not _PIN.fullmatch(value):
        raise ValueError("Enter a valid 6-digit PIN code")
    return value


Pincode = Annotated[str, AfterValidator(clean_pincode)]
PlaceName = Annotated[str, single_line(2, 80)]


class ServiceAreaCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    pincode: Pincode
    area_name: PlaceName
    city: PlaceName
    state: PlaceName
    is_active: bool = True


class ServiceAreaUpdate(PatchModel):
    pincode: Pincode | None = None
    area_name: PlaceName | None = None
    city: PlaceName | None = None
    state: PlaceName | None = None
    is_active: bool | None = None


class ServiceAreaOut(BaseModel):
    id: UUID
    pincode: str
    area_name: str
    city: str
    state: str
    is_active: bool
    created_at: datetime
    updated_at: datetime


class PincodeCheck(BaseModel):
    """What a customer learns about a PIN code. Reveals nothing about inactive areas."""

    pincode: str
    serviceable: bool
    area_name: str | None = None
    city: str | None = None
    state: str | None = None
