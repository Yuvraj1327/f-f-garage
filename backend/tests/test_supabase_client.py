import pytest

from app.db.supabase import SupabaseNotConfiguredError, get_supabase_admin_client
from tests.conftest import make_settings


def test_admin_client_requires_configuration() -> None:
    with pytest.raises(SupabaseNotConfiguredError):
        get_supabase_admin_client(make_settings())


def test_admin_client_is_built_offline_when_configured() -> None:
    """Creating the client must not touch the network."""
    settings = make_settings(
        supabase_url="https://example-project.supabase.co",
        supabase_anon_key="aaa.bbb.ccc",
        supabase_service_role_key="ddd.eee.fff",
    )
    client = get_supabase_admin_client(settings)
    assert client is get_supabase_admin_client(settings)  # cached
