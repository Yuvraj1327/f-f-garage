"""Garage business details: saved by an admin, else the server's environment."""

from datetime import datetime

from app.core.config import Settings
from app.db.garage_settings_repository import GarageSettingsRepository
from app.schemas.garage import GarageSettingsOut, GarageSettingsUpdate, clean_phone
from app.schemas.profile import ProfileOut

_FIELDS = ("name", "phone", "whatsapp", "email", "address", "hours", "refund_policy")


class GarageSettingsService:
    def __init__(self, repository: GarageSettingsRepository, settings: Settings) -> None:
        self._repository = repository
        self._settings = settings

    def current(self) -> GarageSettingsOut:
        row = self._repository.get()
        if row is None:
            s = self._settings
            return GarageSettingsOut(
                name=s.garage_name.strip(),
                phone=clean_phone(s.garage_phone),
                whatsapp=clean_phone(s.garage_whatsapp),
                email=s.garage_email.strip(),
                address=s.garage_address.strip(),
                hours=s.garage_hours.strip(),
                source="environment",
            )
        updated = row.get("updated_at")
        return GarageSettingsOut(
            **{field: row.get(field) or "" for field in _FIELDS},
            source="database",
            updated_at=datetime.fromisoformat(updated) if isinstance(updated, str) else updated,
        )

    def update(self, admin: ProfileOut, data: GarageSettingsUpdate) -> GarageSettingsOut:
        self._repository.save(data.model_dump(), admin.id)
        return self.current()
