"""Authentication + role-based access through the real HTTP stack.

Tokens are genuinely signed and verified (HS256 test secret); only the database is
faked. The point is the access matrix: who can call what, and what they get.
"""

import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_profile_repository, get_profile_service
from app.core.security import TokenVerifier
from app.domain.enums import UserRole
from app.main import create_app
from app.services.profile_service import ProfileService
from tests.conftest import CONFIGURED_SUPABASE, make_settings
from tests.fakes import FakeProfileRepository, make_profile
from tests.jwt_helpers import HS256_SECRET, make_token

SETTINGS = make_settings(**CONFIGURED_SUPABASE, supabase_jwt_secret=HS256_SECRET)
ISSUER = f"{SETTINGS.supabase_url}/auth/v1"


def token_for(profile_id, **overrides) -> str:
    return make_token(
        HS256_SECRET, algorithm="HS256", issuer=ISSUER, sub=str(profile_id), **overrides
    )


def bearer(profile_id, **overrides) -> dict[str, str]:
    return {"Authorization": f"Bearer {token_for(profile_id, **overrides)}"}


@pytest.fixture
def world():
    """A repository holding one user of each kind, plus a client wired to it."""
    customer = make_profile(UserRole.CUSTOMER, full_name="Alice")
    other_customer = make_profile(UserRole.CUSTOMER, full_name="Bob")
    driver = make_profile(UserRole.DRIVER)
    admin = make_profile(UserRole.ADMIN)
    disabled = make_profile(UserRole.CUSTOMER, is_active=False)
    repo = FakeProfileRepository(customer, other_customer, driver, admin, disabled)

    app = create_app(SETTINGS)
    app.dependency_overrides[get_profile_repository] = lambda: repo
    app.dependency_overrides[get_profile_service] = lambda: ProfileService(repo)

    class World:
        pass

    w = World()
    w.client = TestClient(app)
    w.repo = repo
    w.customer, w.other_customer, w.driver, w.admin, w.disabled = (
        customer,
        other_customer,
        driver,
        admin,
        disabled,
    )
    return w


# ---- Authentication --------------------------------------------------------------


def test_no_token_is_401_with_challenge_header(world) -> None:
    response = world.client.get("/api/v1/profiles/me")
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("header", ["Bearer", "Bearer ", "Basic abc", "Bearer not.a.jwt", "token"])
def test_bad_authorization_headers_are_401(world, header: str) -> None:
    response = world.client.get("/api/v1/profiles/me", headers={"Authorization": header})
    assert response.status_code == 401


def test_expired_token_is_401(world) -> None:
    response = world.client.get(
        "/api/v1/profiles/me", headers=bearer(world.customer.id, expires_in=-3600)
    )
    assert response.status_code == 401
    assert "expired" in response.json()["detail"].lower()


def test_token_signed_with_wrong_secret_is_401(world) -> None:
    forged = make_token(
        "another-secret-of-sufficient-length-for-hs256-use",
        algorithm="HS256",
        issuer=ISSUER,
        sub=str(world.admin.id),
    )
    response = world.client.get(
        "/api/v1/profiles/me", headers={"Authorization": f"Bearer {forged}"}
    )
    assert response.status_code == 401


def test_anon_key_style_token_is_401(world) -> None:
    response = world.client.get(
        "/api/v1/profiles/me", headers=bearer(world.customer.id, role="anon")
    )
    assert response.status_code == 401


def test_valid_token_returns_own_profile(world) -> None:
    response = world.client.get("/api/v1/profiles/me", headers=bearer(world.customer.id))
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == str(world.customer.id)
    assert body["role"] == "customer"
    assert body["full_name"] == "Alice"


def test_each_role_sees_only_their_own_profile(world) -> None:
    for user in (world.customer, world.driver, world.admin):
        body = world.client.get("/api/v1/profiles/me", headers=bearer(user.id)).json()
        assert body["id"] == str(user.id)
        assert body["role"] == user.role.value


# ---- Roles come from the database, never from the token ---------------------------


def test_admin_claims_inside_the_token_grant_nothing(world) -> None:
    sneaky = bearer(
        world.customer.id,
        app_metadata={"role": "admin"},
        user_metadata={"role": "admin"},
        user_role="admin",
    )
    response = world.client.get("/api/v1/admin/drivers", headers=sneaky)
    assert response.status_code == 403


def test_role_changes_apply_immediately_with_the_same_token(world) -> None:
    headers = bearer(world.customer.id)
    assert world.client.get("/api/v1/admin/drivers", headers=headers).status_code == 403
    world.repo.rows[str(world.customer.id)] = world.customer.model_copy(
        update={"role": UserRole.ADMIN}
    )
    assert world.client.get("/api/v1/admin/drivers", headers=headers).status_code != 403


def test_valid_token_without_a_profile_is_403(world) -> None:
    import uuid

    response = world.client.get("/api/v1/profiles/me", headers=bearer(uuid.uuid4()))
    assert response.status_code == 403


def test_disabled_account_is_403_even_with_a_valid_token(world) -> None:
    response = world.client.get("/api/v1/profiles/me", headers=bearer(world.disabled.id))
    assert response.status_code == 403
    assert "disabled" in response.json()["detail"].lower()


def test_disabling_a_user_blocks_their_existing_token(world) -> None:
    headers = bearer(world.driver.id)
    assert world.client.get("/api/v1/profiles/me", headers=headers).status_code == 200
    world.repo.rows[str(world.driver.id)] = world.driver.model_copy(update={"is_active": False})
    assert world.client.get("/api/v1/profiles/me", headers=headers).status_code == 403


# ---- Customer profile updates -----------------------------------------------------


def test_customer_can_update_name_and_phone(world) -> None:
    response = world.client.patch(
        "/api/v1/profiles/me",
        headers=bearer(world.customer.id),
        json={"full_name": "  Alice   Smith ", "phone": "98765 43210"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["full_name"] == "Alice Smith"
    assert body["phone"] == "+919876543210"
    stored = world.repo.rows[str(world.customer.id)]
    assert stored.full_name == "Alice Smith"


def test_update_only_touches_the_callers_own_row(world) -> None:
    world.client.patch(
        "/api/v1/profiles/me", headers=bearer(world.customer.id), json={"full_name": "Changed"}
    )
    assert world.repo.rows[str(world.other_customer.id)].full_name == "Bob"
    assert [uid for uid, _ in world.repo.update_calls] == [str(world.customer.id)]


@pytest.mark.parametrize(
    "payload",
    [
        {"role": "admin"},
        {"full_name": "Alice", "role": "admin"},
        {"is_active": True},
        {"driver_login_id": "driver01"},
        {"email": "evil@example.com"},
        {"id": "00000000-0000-0000-0000-000000000000"},
    ],
)
def test_privileged_fields_are_rejected_not_ignored(world, payload: dict) -> None:
    response = world.client.patch(
        "/api/v1/profiles/me", headers=bearer(world.customer.id), json=payload
    )
    assert response.status_code == 422
    assert world.repo.update_calls == []
    assert world.repo.rows[str(world.customer.id)].role == UserRole.CUSTOMER


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"full_name": None},
        {"phone": None},
        {"full_name": "A"},
        {"full_name": " "},
        {"phone": "12345"},
        {"phone": "abcdefghij"},
        {"phone": "5876543210"},
    ],
)
def test_invalid_profile_updates_are_422(world, payload: dict) -> None:
    response = world.client.patch(
        "/api/v1/profiles/me", headers=bearer(world.customer.id), json=payload
    )
    assert response.status_code == 422
    assert world.repo.update_calls == []


def test_drivers_and_admins_cannot_use_the_customer_update_endpoint(world) -> None:
    for user in (world.driver, world.admin):
        response = world.client.patch(
            "/api/v1/profiles/me", headers=bearer(user.id), json={"full_name": "Hacked Name"}
        )
        assert response.status_code == 403
    assert world.repo.update_calls == []


def test_unauthenticated_update_is_401(world) -> None:
    response = world.client.patch("/api/v1/profiles/me", json={"full_name": "Nobody"})
    assert response.status_code == 401


# ---- Admin endpoints are closed to everyone but admins ----------------------------

ADMIN_CALLS = [
    ("GET", "/api/v1/admin/drivers", None),
    (
        "POST",
        "/api/v1/admin/drivers",
        {"driver_id": "driver01", "password": "Password123", "full_name": "Driver One"},
    ),
    ("GET", "/api/v1/admin/drivers/00000000-0000-0000-0000-000000000001", None),
    ("PATCH", "/api/v1/admin/drivers/00000000-0000-0000-0000-000000000001", {"is_active": False}),
    (
        "POST",
        "/api/v1/admin/drivers/00000000-0000-0000-0000-000000000001/password",
        {"new_password": "NewPassword123"},
    ),
]


@pytest.mark.parametrize(("method", "path", "body"), ADMIN_CALLS)
def test_admin_endpoints_reject_anonymous_callers(world, method, path, body) -> None:
    assert world.client.request(method, path, json=body).status_code == 401


@pytest.mark.parametrize(("method", "path", "body"), ADMIN_CALLS)
@pytest.mark.parametrize("role", ["customer", "other_customer", "driver", "disabled"])
def test_admin_endpoints_reject_non_admins(world, method, path, body, role) -> None:
    user = getattr(world, role)
    response = world.client.request(method, path, headers=bearer(user.id), json=body)
    assert response.status_code == 403
    assert world.repo.update_calls == []


def test_infrastructure_outage_is_503_not_a_false_401() -> None:
    """Supabase not configured at all: authenticated routes report 503."""
    client = TestClient(create_app(make_settings()))
    response = client.get("/api/v1/profiles/me", headers={"Authorization": "Bearer a.b.c"})
    assert response.status_code == 503
    assert response.json() == {"detail": "Authentication is not configured"}


def test_unauthenticated_requests_never_touch_the_database() -> None:
    """A missing token is a 401 even when the database is down/unconfigured."""
    client = TestClient(create_app(make_settings(**CONFIGURED_SUPABASE)))
    response = client.get("/api/v1/profiles/me")
    assert response.status_code == 401


def test_503_does_not_leak_configuration_details() -> None:
    settings = make_settings(
        supabase_url="https://example-project.supabase.co", supabase_jwt_secret=HS256_SECRET
    )  # verifier works (HS256), but the database client is not configured
    client = TestClient(create_app(settings))
    token = make_token(
        HS256_SECRET,
        algorithm="HS256",
        issuer=f"{settings.supabase_url}/auth/v1",
        sub="11111111-1111-1111-1111-111111111111",
    )
    response = client.get("/api/v1/profiles/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 503
    assert response.json() == {"detail": "Service temporarily unavailable"}
    assert "SUPABASE" not in response.text


def test_verifier_can_be_injected() -> None:
    verifier = TokenVerifier(SETTINGS)
    app = create_app(SETTINGS, token_verifier=verifier)
    assert app.state.token_verifier is verifier
