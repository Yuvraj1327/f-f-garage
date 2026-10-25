from pathlib import Path

import pytest
from pydantic import ValidationError

from app.core.config import MAPS_KEY_PLACEHOLDER, Settings
from tests.conftest import CONFIGURED_SUPABASE, make_settings

BACKEND_DIR = Path(__file__).resolve().parents[1]


def test_defaults_are_safe_for_local_development() -> None:
    s = make_settings()
    assert s.api_v1_prefix == "/api/v1"
    assert s.enable_docs is True
    assert s.cors_origins == []
    assert s.supabase_configured is False


def test_cors_origins_parse_from_comma_separated_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ORIGINS", "http://localhost:3000/, https://admin.example.com ,")
    s = Settings(_env_file=None, app_env="test")
    assert s.cors_origins == ["http://localhost:3000", "https://admin.example.com"]


def test_empty_cors_origins_env_means_no_origins(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ORIGINS", "")
    assert Settings(_env_file=None, app_env="test").cors_origins == []


def test_supabase_values_come_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SUPABASE_URL", "https://abc.supabase.co/")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "anon")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "service")
    s = Settings(_env_file=None, app_env="test")
    assert s.supabase_url == "https://abc.supabase.co"
    assert s.supabase_configured is True


def test_secrets_are_masked_in_repr_and_str() -> None:
    s = make_settings(**CONFIGURED_SUPABASE, payment_gateway_key_secret="gw-secret-value")
    rendered = repr(s) + str(s)
    for secret in ("anon-key-value", "service-role-key-value", "gw-secret-value"):
        assert secret not in rendered


def test_invalid_supabase_url_is_rejected() -> None:
    with pytest.raises(ValidationError):
        make_settings(supabase_url="example.supabase.co")


@pytest.mark.parametrize("prefix", ["api/v1", "/api/v1/"])
def test_invalid_api_prefix_is_rejected(prefix: str) -> None:
    with pytest.raises(ValidationError):
        make_settings(api_v1_prefix=prefix)


def test_production_rejects_wildcard_cors() -> None:
    with pytest.raises(ValidationError, match="CORS_ORIGINS"):
        make_settings(app_env="production", cors_origins="*", **CONFIGURED_SUPABASE)


def test_production_requires_supabase_configuration() -> None:
    with pytest.raises(ValidationError, match="SUPABASE"):
        make_settings(app_env="production")


def test_production_accepts_complete_configuration() -> None:
    s = make_settings(
        app_env="production",
        cors_origins="https://admin.example.com",
        **CONFIGURED_SUPABASE,
    )
    assert s.is_production


def test_env_example_matches_settings() -> None:
    """`.env.example` documents every setting and parses without errors."""
    example = BACKEND_DIR / ".env.example"
    keys = {
        line.split("=", 1)[0].strip()
        for line in example.read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#") and "=" in line
    }
    expected = {name.upper() for name in Settings.model_fields}
    # app_version is code-defined, not an operator setting.
    assert keys == expected - {"APP_VERSION"}
    Settings(_env_file=example, app_env="test")


def test_env_example_contains_no_real_secrets() -> None:
    example = (BACKEND_DIR / ".env.example").read_text()
    for line in example.splitlines():
        key, _, value = line.partition("=")
        if key.strip().endswith(("_KEY", "_SECRET")):
            # The one allowed non-blank value is the obvious placeholder, which the
            # settings treat as "not configured" (see Settings.maps_enabled).
            allowed = ("", MAPS_KEY_PLACEHOLDER) if key.strip() == "GOOGLE_MAPS_API_KEY" else ("",)
            assert value.strip() in allowed, f"{key} must be blank in .env.example"
