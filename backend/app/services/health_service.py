import logging
from collections.abc import Callable
from datetime import UTC, datetime

from app.core.config import Settings
from app.db.supabase import ping_database
from app.schemas.health import ComponentCheck, HealthResponse, ReadinessResponse

logger = logging.getLogger(__name__)


class HealthService:
    def __init__(
        self,
        settings: Settings,
        database_probe: Callable[[Settings], None] = ping_database,
    ) -> None:
        self._settings = settings
        self._database_probe = database_probe

    def liveness(self) -> HealthResponse:
        """The process is up. Touches no external dependency."""
        return HealthResponse(
            service=self._settings.app_name,
            version=self._settings.app_version,
            environment=self._settings.app_env,
            timestamp=datetime.now(UTC),
        )

    def readiness(self) -> ReadinessResponse:
        """The app can serve traffic: its database is configured and reachable."""
        checks = {"database": self._check_database()}
        ready = all(check.status == "ok" for check in checks.values())
        return ReadinessResponse(status="ready" if ready else "not_ready", checks=checks)

    def _check_database(self) -> ComponentCheck:
        if not self._settings.supabase_configured:
            return ComponentCheck(
                status="not_configured",
                detail="Supabase credentials are not set",
            )
        try:
            self._database_probe(self._settings)
        except Exception:
            # Log the details server-side; never echo them to the caller.
            logger.exception("Database readiness probe failed")
            return ComponentCheck(status="unavailable", detail="Database query failed")
        return ComponentCheck(status="ok")
