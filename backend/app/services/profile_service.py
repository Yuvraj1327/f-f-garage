from app.core.errors import NotFoundError
from app.db.profile_repository import ProfileRepository
from app.schemas.profile import ProfileOut, ProfileUpdate


class ProfileService:
    def __init__(self, profiles: ProfileRepository) -> None:
        self._profiles = profiles

    def update_own_profile(self, user: ProfileOut, changes: ProfileUpdate) -> ProfileOut:
        """Only the caller's own row, and only the whitelisted fields."""
        updated = self._profiles.update(str(user.id), changes.to_update_values())
        if updated is None:
            raise NotFoundError("Profile not found")
        return updated
