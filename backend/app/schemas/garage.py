import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator

_EMAIL = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")


def clean_phone(raw: str) -> str:
    """Keep a leading + and the digits, so the app can build tel:/WhatsApp links."""
    raw = raw.strip()
    digits = "".join(ch for ch in raw if ch.isdigit())
    if not digits:
        return ""
    return ("+" if raw.startswith("+") else "") + digits


class GarageSettingsOut(BaseModel):
    name: str
    phone: str
    whatsapp: str
    email: str
    address: str
    hours: str
    # The refund policy the garage configured, shown to customers (empty = none set).
    refund_policy: str = ""
    # Where the values come from: saved by an admin, or the server's .env.
    source: Literal["database", "environment"]
    updated_at: datetime | None = None


class GarageSettingsUpdate(BaseModel):
    """The full set of details (an empty string clears an optional one)."""

    model_config = ConfigDict(extra="forbid")

    name: str
    phone: str = ""
    whatsapp: str = ""
    email: str = ""
    address: str = ""
    hours: str = ""
    refund_policy: str = ""

    @field_validator("name")
    @classmethod
    def _name(cls, value: str) -> str:
        value = " ".join(value.split())
        if not value or len(value) > 120:
            raise ValueError("Garage name must be 1-120 characters")
        return value

    @field_validator("phone", "whatsapp")
    @classmethod
    def _phone(cls, value: str) -> str:
        cleaned = clean_phone(value)
        if cleaned and not 7 <= len(cleaned.lstrip("+")) <= 15:
            raise ValueError("Enter a phone number with 7-15 digits")
        return cleaned

    @field_validator("email")
    @classmethod
    def _email(cls, value: str) -> str:
        value = value.strip()
        if value and (len(value) > 254 or not _EMAIL.fullmatch(value)):
            raise ValueError("Enter a valid email address")
        return value

    @field_validator("address")
    @classmethod
    def _address(cls, value: str) -> str:
        value = value.strip()
        if len(value) > 300:
            raise ValueError("Address must be at most 300 characters")
        return value

    @field_validator("hours")
    @classmethod
    def _hours(cls, value: str) -> str:
        value = value.strip()
        if len(value) > 120:
            raise ValueError("Opening hours must be at most 120 characters")
        return value

    @field_validator("refund_policy")
    @classmethod
    def _refund_policy(cls, value: str) -> str:
        value = value.strip()
        if len(value) > 1000:
            raise ValueError("The refund policy must be at most 1000 characters")
        return value
