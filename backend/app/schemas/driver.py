import re
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator, model_validator

from app.schemas.profile import clean_full_name, normalize_phone

# Same rule as the profiles.driver_login_id database constraint.
DRIVER_ID_PATTERN = re.compile(r"[a-z0-9][a-z0-9._-]{2,31}")
PASSWORD_MIN_LENGTH = 8
PASSWORD_MAX_LENGTH = 72  # bcrypt ignores everything past 72 bytes


def _check_password(value: SecretStr) -> SecretStr:
    raw = value.get_secret_value()
    if not PASSWORD_MIN_LENGTH <= len(raw) <= PASSWORD_MAX_LENGTH:
        raise ValueError(
            f"Password must be between {PASSWORD_MIN_LENGTH} and {PASSWORD_MAX_LENGTH} characters"
        )
    if not raw.strip():
        raise ValueError("Password cannot be blank")
    return value


class DriverCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    driver_id: str = Field(description="Login ID: 3-32 chars of a-z, 0-9, '.', '_' or '-'")
    password: SecretStr
    full_name: str
    phone: str | None = None

    @field_validator("driver_id")
    @classmethod
    def _driver_id(cls, value: str) -> str:
        value = value.strip().lower()
        if not DRIVER_ID_PATTERN.fullmatch(value):
            raise ValueError(
                "Driver ID must be 3-32 characters: lowercase letters, digits, '.', '_' or '-', "
                "starting with a letter or digit"
            )
        return value

    @field_validator("password")
    @classmethod
    def _password(cls, value: SecretStr) -> SecretStr:
        return _check_password(value)

    @field_validator("full_name")
    @classmethod
    def _full_name(cls, value: str) -> str:
        return clean_full_name(value)

    @field_validator("phone")
    @classmethod
    def _phone(cls, value: str | None) -> str | None:
        return None if value is None else normalize_phone(value)

    @model_validator(mode="after")
    def _password_not_id(self) -> "DriverCreate":
        if self.password.get_secret_value().lower() == self.driver_id:
            raise ValueError("Password must not be the same as the driver ID")
        return self


class DriverUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    full_name: str | None = None
    phone: str | None = None
    is_active: bool | None = None

    @model_validator(mode="after")
    def _validate(self) -> "DriverUpdate":
        if not self.model_fields_set:
            raise ValueError("Provide at least one field to update")
        for name in self.model_fields_set:
            if getattr(self, name) is None:
                raise ValueError(f"{name} cannot be null")
        if "full_name" in self.model_fields_set:
            self.full_name = clean_full_name(self.full_name or "")
        if "phone" in self.model_fields_set:
            self.phone = normalize_phone(self.phone or "")
        return self

    def to_update_values(self) -> dict[str, object]:
        return {name: getattr(self, name) for name in self.model_fields_set}


class DriverPasswordReset(BaseModel):
    model_config = ConfigDict(extra="forbid")

    new_password: SecretStr

    @field_validator("new_password")
    @classmethod
    def _password(cls, value: SecretStr) -> SecretStr:
        return _check_password(value)


class DriverOut(BaseModel):
    """A driver as shown to admins. Never contains a password or auth email."""

    id: UUID
    driver_login_id: str
    full_name: str | None = None
    phone: str | None = None
    is_active: bool
    # Bookings this driver still has to do (assigned, on the way or in progress).
    open_bookings: int = 0
    created_at: datetime
    updated_at: datetime
