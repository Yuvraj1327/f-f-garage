from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app


def _preflight(settings: Settings, origin: str):
    client = TestClient(create_app(settings))
    return client.options(
        "/api/v1/profiles/me",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization,content-type",
        },
    )


def test_dev_allows_any_localhost_port():
    s = Settings(_env_file=None, app_env="development")
    for origin in ("http://localhost:54321", "http://127.0.0.1:60000"):
        r = _preflight(s, origin)
        assert r.status_code == 200
        assert r.headers["access-control-allow-origin"] == origin


def test_dev_rejects_other_origins():
    s = Settings(_env_file=None, app_env="development")
    assert "access-control-allow-origin" not in _preflight(s, "http://evil.example").headers


def test_production_does_not_allow_random_localhost_ports():
    s = Settings(
        _env_file=None, app_env="production", supabase_url="https://x.supabase.co",
        supabase_anon_key="a", supabase_service_role_key="b",
        cors_origins=["https://app.example.com"],
    )
    assert "access-control-allow-origin" not in _preflight(s, "http://localhost:54321").headers
    assert _preflight(s, "https://app.example.com").headers["access-control-allow-origin"] == "https://app.example.com"
