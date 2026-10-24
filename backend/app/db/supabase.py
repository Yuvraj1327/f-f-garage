"""Supabase client factory.

The admin client uses the service-role key and therefore bypasses Row Level
Security. Every route that uses it must enforce authorization itself
(role checks arrive with authentication in the next phase).
"""

from functools import lru_cache

from supabase import Client, create_client

from app.core.config import Settings
from app.core.errors import ServiceUnavailableError


class SupabaseNotConfiguredError(ServiceUnavailableError):
    """Raised when Supabase credentials are missing from the environment.

    The client only sees a generic 503; the specifics are logged server-side."""

    def __init__(self) -> None:
        super().__init__(
            log_message=(
                "Supabase is not configured. Set SUPABASE_URL, SUPABASE_ANON_KEY and "
                "SUPABASE_SERVICE_ROLE_KEY."
            )
        )


@lru_cache(maxsize=2)
def _build_admin_client(url: str, service_role_key: str) -> Client:
    return create_client(url, service_role_key)


def get_supabase_admin_client(settings: Settings) -> Client:
    """Return a (cached) service-role client, or raise if not configured."""
    if not settings.supabase_configured:
        raise SupabaseNotConfiguredError()
    return _build_admin_client(
        settings.supabase_url,
        settings.supabase_service_role_key.get_secret_value(),
    )


def ping_database(settings: Settings) -> None:
    """Run a trivial query; raises on any failure."""
    client = get_supabase_admin_client(settings)
    client.table("service_areas").select("id").limit(1).execute()
