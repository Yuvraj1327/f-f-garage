"""In-memory stand-ins for the Supabase-backed repository and Auth admin gateway."""

import uuid
from datetime import UTC, datetime
from typing import Any

from app.core.errors import ConflictError, NotFoundError
from app.domain.enums import UserRole
from app.schemas.profile import ProfileOut


def make_profile(
    role: UserRole = UserRole.CUSTOMER,
    *,
    user_id: str | None = None,
    is_active: bool = True,
    full_name: str | None = "Test User",
    phone: str | None = "+919876543210",
    driver_login_id: str | None = None,
) -> ProfileOut:
    now = datetime.now(UTC)
    if role == UserRole.DRIVER and driver_login_id is None:
        driver_login_id = f"driver{uuid.uuid4().hex[:6]}"
    return ProfileOut(
        id=uuid.UUID(user_id) if user_id else uuid.uuid4(),
        role=role,
        full_name=full_name,
        phone=phone,
        email=f"{uuid.uuid4().hex[:6]}@example.com",
        driver_login_id=driver_login_id,
        is_active=is_active,
        created_at=now,
        updated_at=now,
    )


class FakeProfileRepository:
    def __init__(self, *profiles: ProfileOut) -> None:
        self.rows: dict[str, ProfileOut] = {str(p.id): p for p in profiles}
        self.update_calls: list[tuple[str, dict[str, Any]]] = []

    def add(self, profile: ProfileOut) -> ProfileOut:
        self.rows[str(profile.id)] = profile
        return profile

    def get(self, user_id: str) -> ProfileOut | None:
        return self.rows.get(user_id)

    def get_many(self, user_ids: list[str]) -> list[ProfileOut]:
        return [self.rows[i] for i in user_ids if i in self.rows]

    def update(self, user_id: str, values: dict[str, Any]) -> ProfileOut | None:
        self.update_calls.append((user_id, dict(values)))
        row = self.rows.get(user_id)
        if row is None:
            return None
        updated = row.model_copy(update={**values, "updated_at": datetime.now(UTC)})
        self.rows[user_id] = updated
        return updated

    def get_driver(self, user_id: str) -> ProfileOut | None:
        row = self.rows.get(user_id)
        return row if row and row.role == UserRole.DRIVER else None

    def list_drivers(self) -> list[ProfileOut]:
        return [r for r in self.rows.values() if r.role == UserRole.DRIVER]

    def driver_login_id_exists(self, driver_login_id: str) -> bool:
        return any(r.driver_login_id == driver_login_id for r in self.rows.values())


class FakeAuthAdminGateway:
    """Records calls. `create_driver_user` mimics the database trigger by adding the
    driver profile to the fake repository (set `skip_profile` to simulate a failure)."""

    def __init__(self, profiles: FakeProfileRepository) -> None:
        self._profiles = profiles
        self.created: list[dict[str, Any]] = []
        self.password_resets: list[tuple[str, str]] = []
        self.ban_calls: list[tuple[str, bool]] = []
        self.deleted: list[str] = []
        self.skip_profile = False
        self.existing_emails: set[str] = set()
        self.known_user_ids: set[str] = set()

    def create_driver_user(
        self,
        *,
        email: str,
        password: str,
        driver_login_id: str,
        full_name: str,
        phone: str | None,
    ) -> str:
        if email in self.existing_emails:
            raise ConflictError("A driver with this ID already exists")
        self.existing_emails.add(email)
        user_id = str(uuid.uuid4())
        self.known_user_ids.add(user_id)
        self.created.append(
            {
                "user_id": user_id,
                "email": email,
                "password": password,
                "driver_login_id": driver_login_id,
                "full_name": full_name,
                "phone": phone,
            }
        )
        if not self.skip_profile:
            self._profiles.add(
                make_profile(
                    UserRole.DRIVER,
                    user_id=user_id,
                    full_name=full_name,
                    phone=phone,
                    driver_login_id=driver_login_id,
                )
            )
        return user_id

    def set_password(self, user_id: str, password: str) -> None:
        if user_id not in self._profiles.rows and user_id not in self.known_user_ids:
            raise NotFoundError("Driver not found")
        self.password_resets.append((user_id, password))

    def set_banned(self, user_id: str, banned: bool) -> None:
        self.ban_calls.append((user_id, banned))

    def delete_user(self, user_id: str) -> None:
        self.deleted.append(user_id)
