import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app

SETTING_ENV_VARS = [name.upper() for name in Settings.model_fields]


@pytest.fixture(autouse=True)
def clean_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    """Tests never see the developer's real environment variables."""
    for name in SETTING_ENV_VARS:
        monkeypatch.delenv(name, raising=False)


def make_settings(**overrides: object) -> Settings:
    """Settings that ignore any local `.env` file."""
    values: dict[str, object] = {"app_env": "test"}
    values.update(overrides)
    return Settings(_env_file=None, **values)  # type: ignore[arg-type]


CONFIGURED_SUPABASE = {
    "supabase_url": "https://example-project.supabase.co",
    "supabase_anon_key": "anon-key-value",
    "supabase_service_role_key": "service-role-key-value",
}


@pytest.fixture
def settings() -> Settings:
    return make_settings()


@pytest.fixture
def client(settings: Settings) -> TestClient:
    return TestClient(create_app(settings))
