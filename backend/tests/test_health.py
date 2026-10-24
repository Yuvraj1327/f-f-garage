import logging

import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_health_service
from app.core.config import Settings
from app.main import create_app
from app.services.health_service import HealthService
from tests.conftest import CONFIGURED_SUPABASE, make_settings


def test_liveness_returns_ok(client: TestClient) -> None:
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["environment"] == "test"
    assert body["service"]
    assert body["version"]
    assert body["timestamp"]


def test_routes_live_under_api_v1_only(client: TestClient) -> None:
    assert client.get("/health").status_code == 404


def test_custom_prefix_is_respected() -> None:
    app = create_app(make_settings(api_v1_prefix="/api/v2"))
    with TestClient(app) as c:
        assert c.get("/api/v2/health").status_code == 200
        assert c.get("/api/v1/health").status_code == 404


def test_readiness_not_ready_when_supabase_not_configured(client: TestClient) -> None:
    response = client.get("/api/v1/health/ready")
    assert response.status_code == 503
    body = response.json()
    assert body["status"] == "not_ready"
    assert body["checks"]["database"]["status"] == "not_configured"


def _client_with_probe(settings: Settings, probe) -> TestClient:
    app = create_app(settings)
    app.dependency_overrides[get_health_service] = lambda: HealthService(
        settings, database_probe=probe
    )
    return TestClient(app)


def test_readiness_ready_when_database_probe_succeeds() -> None:
    c = _client_with_probe(make_settings(**CONFIGURED_SUPABASE), lambda _s: None)
    response = c.get("/api/v1/health/ready")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ready",
        "checks": {"database": {"status": "ok", "detail": None}},
    }


def test_readiness_does_not_leak_error_details(caplog: pytest.LogCaptureFixture) -> None:
    def failing_probe(_settings: Settings) -> None:
        raise RuntimeError("connection to secret-host.internal refused")

    c = _client_with_probe(make_settings(**CONFIGURED_SUPABASE), failing_probe)
    with caplog.at_level(logging.ERROR):
        response = c.get("/api/v1/health/ready")
    assert response.status_code == 503
    assert response.json()["checks"]["database"]["status"] == "unavailable"
    assert "secret-host" not in response.text
    assert "secret-host" in caplog.text  # still available to operators in the logs


def test_swagger_and_openapi_are_served(client: TestClient) -> None:
    docs = client.get("/docs")
    assert docs.status_code == 200
    assert "text/html" in docs.headers["content-type"]
    assert client.get("/redoc").status_code == 200
    schema = client.get("/openapi.json").json()
    assert "/api/v1/health" in schema["paths"]
    assert "/api/v1/health/ready" in schema["paths"]


def test_docs_can_be_disabled() -> None:
    with TestClient(create_app(make_settings(enable_docs=False))) as c:
        assert c.get("/docs").status_code == 404
        assert c.get("/redoc").status_code == 404
        assert c.get("/openapi.json").status_code == 404
        assert c.get("/api/v1/health").status_code == 200


def test_cors_allows_configured_origin() -> None:
    app = create_app(make_settings(cors_origins="http://localhost:3000"))
    with TestClient(app) as c:
        response = c.options(
            "/api/v1/health",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET",
                "Access-Control-Request-Headers": "Authorization",
            },
        )
        assert response.status_code == 200
        assert response.headers["access-control-allow-origin"] == "http://localhost:3000"
        simple = c.get("/api/v1/health", headers={"Origin": "http://localhost:3000"})
        assert simple.headers["access-control-allow-origin"] == "http://localhost:3000"


def test_cors_rejects_unknown_origin() -> None:
    app = create_app(make_settings(cors_origins="http://localhost:3000"))
    with TestClient(app) as c:
        response = c.get("/api/v1/health", headers={"Origin": "https://evil.example"})
        assert "access-control-allow-origin" not in response.headers


def test_cors_sends_no_headers_when_no_origins_configured(client: TestClient) -> None:
    response = client.get("/api/v1/health", headers={"Origin": "http://localhost:3000"})
    assert "access-control-allow-origin" not in response.headers
