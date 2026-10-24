import re
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, model_validator

from app.domain.enums import UserRole

_DB_PHONE = re.compile(r"\+?[0-9]{7,15}")
_INDIAN_MOBILE = re.compile(r"[6-9][0-9]{9}")


def normalize_phone(raw: str) -> str:
    """Return the phone in the database format (`+` and 7-15 digits).

    A bare 10-digit Indian mobile number (optionally written with 0, 91 or
    +91 and spaces/dashes) becomes `+91XXXXXXXXXX`. Other international numbers
    must already start with `+`.
    """
    cleaned = re.sub(r"[\s\-().]", "", raw.strip())
    if cleaned.startswith("+91"):
        digits = cleaned[3:]
    elif cleaned.startswith("+"):
        if not re.fullmatch(r"\+[0-9]{7,15}", cleaned):
            raise ValueError("Enter a valid phone number")
        return cleaned
    elif len(cleaned) == 12 and cleaned.startswith("91"):
        digits = cleaned[2:]
    elif len(cleaned) == 11 and cleaned.startswith("0"):
        digits = cleaned[1:]
    else:
        digits = cleaned
    if not _INDIAN_MOBILE.fullmatch(digits):
        raise ValueError("Enter a valid 10-digit mobile number")
    return f"+91{digits}"


def clean_full_name(raw: str) -> str:
    value = " ".join(raw.split())
    if not 2 <= len(value) <= 120:
        raise ValueError("Name must be between 2 and 120 characters")
    return value


class ProfileOut(BaseModel):
    """A user's profile row. Also the authenticated principal inside the API."""

    id: UUID
    role: UserRole
    full_name: str | None = None
    phone: str | None = None
    email: str | None = None
    driver_login_id: str | None = None
    is_active: bool
    created_at: datetime
    updated_at: datetime


class ProfileUpdate(BaseModel):
    """What a customer may change about their own profile.

    Unknown fields (role, is_active, ...) are rejected with a 422 rather than
    silently ignored.
    """

    model_config = ConfigDict(extra="forbid")

    full_name: str | None = None
    phone: str | None = None

    @model_validator(mode="after")
    def _validate(self) -> "ProfileUpdate":
        if not self.model_fields_set:
            raise ValueError("Provide at least one field to update")
        if "full_name" in self.model_fields_set:
            if self.full_name is None:
                raise ValueError("full_name cannot be null")
            self.full_name = clean_full_name(self.full_name)
        if "phone" in self.model_fields_set:
            if self.phone is None:
                raise ValueError("phone cannot be null")
            self.phone = normalize_phone(self.phone)
        return self

    def to_update_values(self) -> dict[str, str]:
        return {name: getattr(self, name) for name in self.model_fields_set}
