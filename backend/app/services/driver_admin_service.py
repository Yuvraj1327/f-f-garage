"""Admin management of driver accounts.

Drivers never register themselves. An admin creates the account here, which
creates the Supabase Auth user (synthetic email + password) and, through the
database trigger, the driver profile in one atomic step.
"""

import logging
from uuid import UUID

from app.core.config import Settings
from app.core.errors import ConflictError, NotFoundError, UpstreamError
from app.db.assignment_repository import AssignmentRepository
from app.db.auth_admin import AuthAdminGateway
from app.db.profile_repository import ProfileRepository
from app.domain.enums import UserRole
from app.schemas.driver import DriverCreate, DriverOut, DriverUpdate
from app.schemas.profile import ProfileOut

logger = logging.getLogger(__name__)


def _to_driver(profile: ProfileOut, open_bookings: int = 0) -> DriverOut:
    if profile.driver_login_id is None:
        raise UpstreamError("Driver profile is missing its login ID")
    return DriverOut(
        id=profile.id,
        driver_login_id=profile.driver_login_id,
        full_name=profile.full_name,
        phone=profile.phone,
        is_active=profile.is_active,
        open_bookings=open_bookings,
        created_at=profile.created_at,
        updated_at=profile.updated_at,
    )


class DriverAdminService:
    def __init__(
        self,
        profiles: ProfileRepository,
        auth_admin: AuthAdminGateway,
        settings: Settings,
        assignments: AssignmentRepository | None = None,
    ) -> None:
        self._assignments = assignments
        self._profiles = profiles
        self._auth_admin = auth_admin
        self._settings = settings

    def _open_counts(self) -> dict[UUID, int]:
        return self._assignments.open_counts() if self._assignments else {}

    def list_drivers(self) -> list[DriverOut]:
        counts = self._open_counts()
        return [_to_driver(p, counts.get(p.id, 0)) for p in self._profiles.list_drivers()]

    def get_driver(self, driver_id: UUID) -> DriverOut:
        driver = self._require_driver(driver_id)
        return _to_driver(driver, self._open_counts().get(driver.id, 0))

    def create_driver(self, admin: ProfileOut, data: DriverCreate) -> DriverOut:
        if self._profiles.driver_login_id_exists(data.driver_id):
            raise ConflictError("A driver with this ID already exists")

        user_id = self._auth_admin.create_driver_user(
            email=f"{data.driver_id}@{self._settings.driver_email_domain}",
            password=data.password.get_secret_value(),
            driver_login_id=data.driver_id,
            full_name=data.full_name,
            phone=data.phone,
        )

        profile = self._profiles.get(user_id)
        if profile is None or profile.role != UserRole.DRIVER:
            # The trigger did not produce a driver profile. Never leave a login
            # without a matching driver profile behind.
            logger.error("Driver profile missing after creating auth user %s", user_id)
            try:
                self._auth_admin.delete_user(user_id)
            except UpstreamError:
                logger.exception("Could not remove orphaned auth user %s", user_id)
            raise UpstreamError("Driver account was not set up correctly")

        logger.info("Admin %s created driver %s (%s)", admin.id, profile.id, data.driver_id)
        return _to_driver(profile)

    def update_driver(self, admin: ProfileOut, driver_id: UUID, data: DriverUpdate) -> DriverOut:
        driver = self._require_driver(driver_id)
        values = data.to_update_values()
        uid = str(driver.id)

        # Order matters so a half-finished change always fails closed:
        # disabling updates the profile (checked on every API call) first and then
        # bans the login; enabling lifts the ban first and then re-enables the profile.
        if data.is_active is True:
            self._auth_admin.set_banned(uid, False)
        updated = self._profiles.update(uid, values)
        if data.is_active is False:
            self._auth_admin.set_banned(uid, True)

        if updated is None:
            raise NotFoundError("Driver not found")
        open_bookings = self._open_counts().get(updated.id, 0)
        if data.is_active is False and open_bookings:
            logger.warning(
                "Admin %s deactivated driver %s who still has %s open booking(s)",
                admin.id,
                uid,
                open_bookings,
            )
        logger.info("Admin %s updated driver %s: %s", admin.id, uid, sorted(values))
        return _to_driver(updated, open_bookings)

    def reset_password(self, admin: ProfileOut, driver_id: UUID, new_password: str) -> None:
        driver = self._require_driver(driver_id)
        self._auth_admin.set_password(str(driver.id), new_password)
        logger.info("Admin %s reset the password of driver %s", admin.id, driver.id)

    def _require_driver(self, driver_id: UUID) -> ProfileOut:
        driver = self._profiles.get_driver(str(driver_id))
        if driver is None:
            raise NotFoundError("Driver not found")
        return driver
