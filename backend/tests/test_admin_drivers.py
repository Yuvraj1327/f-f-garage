"""Admin driver management: HTTP behaviour plus the service's ordering/rollback rules."""

import uuid

import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_assignment_repository, get_auth_admin_gateway, get_profile_repository
from app.core.errors import UpstreamError
from app.domain.enums import UserRole
from app.main import create_app
from app.schemas.driver import DriverCreate
from app.services.driver_admin_service import DriverAdminService
from tests.conftest import CONFIGURED_SUPABASE, make_settings
from tests.fakes import FakeAuthAdminGateway, FakeProfileRepository, make_profile
from tests.fakes_assignment import FakeAssignmentRepository
from tests.fakes_booking import FakeBookingRepository
from tests.fakes_catalog import FakeAvailabilityRepository
from tests.fakes_payment import FakePaymentRepository
from tests.jwt_helpers import HS256_SECRET, make_token

SETTINGS = make_settings(**CONFIGURED_SUPABASE, supabase_jwt_secret=HS256_SECRET)
ISSUER = f"{SETTINGS.supabase_url}/auth/v1"
NEW_DRIVER = {
    "driver_id": "Ravi.K",
    "password": "S3cretPass!",
    "full_name": "Ravi Kumar",
    "phone": "98765 43210",
}


def headers_for(profile) -> dict[str, str]:
    token = make_token(HS256_SECRET, algorithm="HS256", issuer=ISSUER, sub=str(profile.id))
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def ctx():
    admin = make_profile(UserRole.ADMIN)
    repo = FakeProfileRepository(admin)
    gateway = FakeAuthAdminGateway(repo)
    bookings = FakeBookingRepository(FakeAvailabilityRepository())
    assignments = FakeAssignmentRepository(bookings, repo, FakePaymentRepository(bookings))
    app = create_app(SETTINGS)
    app.dependency_overrides[get_profile_repository] = lambda: repo
    app.dependency_overrides[get_auth_admin_gateway] = lambda: gateway
    app.dependency_overrides[get_assignment_repository] = lambda: assignments

    class Ctx:
        pass

    c = Ctx()
    c.client, c.repo, c.gateway, c.admin = TestClient(app), repo, gateway, admin
    c.headers = headers_for(admin)
    return c


def create(ctx, body=None):
    return ctx.client.post("/api/v1/admin/drivers", headers=ctx.headers, json=body or NEW_DRIVER)


# ---- Create ------------------------------------------------------------------------


def test_admin_creates_a_driver(ctx) -> None:
    response = create(ctx)
    assert response.status_code == 201
    body = response.json()
    assert body["driver_login_id"] == "ravi.k"  # normalised to lowercase
    assert body["full_name"] == "Ravi Kumar"
    assert body["phone"] == "+919876543210"
    assert body["is_active"] is True


def test_login_email_is_derived_from_the_id_on_the_reserved_domain(ctx) -> None:
    create(ctx)
    created = ctx.gateway.created[0]
    assert created["email"] == "ravi.k@drivers.ffgarage.invalid"
    assert created["driver_login_id"] == "ravi.k"


def test_password_is_never_returned_or_stored_in_the_profile(ctx) -> None:
    response = create(ctx)
    assert "S3cretPass!" not in response.text
    assert "password" not in response.json()
    assert "email" not in response.json()
    assert all("S3cretPass!" not in str(v) for v in ctx.repo.rows.values())


def test_duplicate_driver_id_is_409(ctx) -> None:
    assert create(ctx).status_code == 201
    second = create(ctx, {**NEW_DRIVER, "driver_id": "RAVI.K"})
    assert second.status_code == 409
    assert len(ctx.gateway.created) == 1


def test_duplicate_detected_by_auth_when_profile_lookup_missed_it(ctx) -> None:
    ctx.gateway.existing_emails.add("ravi.k@drivers.ffgarage.invalid")
    assert create(ctx).status_code == 409


@pytest.mark.parametrize(
    "override",
    [
        {"driver_id": "ab"},
        {"driver_id": "has space"},
        {"driver_id": "UPPER#case"},
        {"driver_id": "x" * 33},
        {"driver_id": "-leading"},
        {"password": "short"},
        {"password": "x" * 73},
        {"password": "        "},
        {"password": "ravi.k"},
        {"full_name": "R"},
        {"phone": "123"},
        {"role": "admin"},
        {"is_active": False},
    ],
)
def test_invalid_driver_payloads_are_422(ctx, override) -> None:
    response = create(ctx, {**NEW_DRIVER, **override})
    assert response.status_code == 422
    assert ctx.gateway.created == []


def test_validation_errors_do_not_echo_the_submitted_password(ctx) -> None:
    response = create(ctx, {**NEW_DRIVER, "password": "Zq9!x"})
    assert response.status_code == 422
    assert "Zq9!x" not in response.text
    assert all(set(item) == {"loc", "msg", "type"} for item in response.json()["detail"])


def test_reset_validation_errors_do_not_echo_the_submitted_password(ctx) -> None:
    driver_id = _driver_id(ctx)
    response = ctx.client.post(
        f"/api/v1/admin/drivers/{driver_id}/password",
        headers=ctx.headers,
        json={"new_password": "Zq9!x"},
    )
    assert response.status_code == 422
    assert "Zq9!x" not in response.text


def test_create_without_phone_is_allowed(ctx) -> None:
    body = {k: v for k, v in NEW_DRIVER.items() if k != "phone"}
    assert create(ctx, body).status_code == 201


def test_orphaned_login_is_removed_if_the_profile_was_not_created(ctx) -> None:
    ctx.gateway.skip_profile = True
    response = create(ctx)
    assert response.status_code == 502
    assert ctx.gateway.deleted == [ctx.gateway.created[0]["user_id"]]


# ---- Read ----------------------------------------------------------------------------


def test_list_and_get_only_return_drivers(ctx) -> None:
    create(ctx)
    ctx.repo.add(make_profile(UserRole.CUSTOMER))
    listing = ctx.client.get("/api/v1/admin/drivers", headers=ctx.headers).json()
    assert [d["driver_login_id"] for d in listing] == ["ravi.k"]
    driver_id = listing[0]["id"]
    assert (
        ctx.client.get(f"/api/v1/admin/drivers/{driver_id}", headers=ctx.headers).status_code == 200
    )


def test_admin_cannot_fetch_or_modify_a_non_driver_through_driver_routes(ctx) -> None:
    customer = ctx.repo.add(make_profile(UserRole.CUSTOMER))
    url = f"/api/v1/admin/drivers/{customer.id}"
    assert ctx.client.get(url, headers=ctx.headers).status_code == 404
    assert ctx.client.patch(url, headers=ctx.headers, json={"is_active": False}).status_code == 404
    assert (
        ctx.client.post(
            f"{url}/password", headers=ctx.headers, json={"new_password": "NewPassword123"}
        ).status_code
        == 404
    )
    assert ctx.gateway.ban_calls == [] and ctx.gateway.password_resets == []


def test_unknown_driver_is_404_and_bad_uuid_is_422(ctx) -> None:
    assert (
        ctx.client.get(f"/api/v1/admin/drivers/{uuid.uuid4()}", headers=ctx.headers).status_code
        == 404
    )
    assert (
        ctx.client.get("/api/v1/admin/drivers/not-a-uuid", headers=ctx.headers).status_code == 422
    )


# ---- Update / disable / enable --------------------------------------------------------


def _driver_id(ctx) -> str:
    create(ctx)
    return str(next(iter(ctx.repo.list_drivers())).id)


def test_admin_updates_driver_details(ctx) -> None:
    driver_id = _driver_id(ctx)
    response = ctx.client.patch(
        f"/api/v1/admin/drivers/{driver_id}",
        headers=ctx.headers,
        json={"full_name": "Ravi K. Sharma", "phone": "9123456780"},
    )
    assert response.status_code == 200
    assert response.json()["full_name"] == "Ravi K. Sharma"
    assert response.json()["phone"] == "+919123456780"
    assert ctx.gateway.ban_calls == []


def test_disabling_a_driver_updates_the_profile_then_bans_the_login(ctx) -> None:
    driver_id = _driver_id(ctx)
    response = ctx.client.patch(
        f"/api/v1/admin/drivers/{driver_id}", headers=ctx.headers, json={"is_active": False}
    )
    assert response.status_code == 200
    assert response.json()["is_active"] is False
    assert ctx.repo.rows[driver_id].is_active is False
    assert ctx.gateway.ban_calls == [(driver_id, True)]


def test_enabling_lifts_the_ban_before_reactivating_the_profile(ctx) -> None:
    driver_id = _driver_id(ctx)
    order: list[str] = []
    original_update = ctx.repo.update
    ctx.repo.update = lambda uid, values: (order.append("profile"), original_update(uid, values))[1]
    original_ban = ctx.gateway.set_banned
    ctx.gateway.set_banned = lambda uid, banned: (
        order.append(f"ban={banned}"),
        original_ban(uid, banned),
    )[1]

    ctx.client.patch(
        f"/api/v1/admin/drivers/{driver_id}", headers=ctx.headers, json={"is_active": False}
    )
    ctx.client.patch(
        f"/api/v1/admin/drivers/{driver_id}", headers=ctx.headers, json={"is_active": True}
    )
    assert order == ["profile", "ban=True", "ban=False", "profile"]


def test_a_failed_ban_after_disabling_still_leaves_the_driver_blocked(ctx) -> None:
    driver_id = _driver_id(ctx)

    def failing_ban(_uid, _banned):
        raise UpstreamError("boom")

    ctx.gateway.set_banned = failing_ban
    response = ctx.client.patch(
        f"/api/v1/admin/drivers/{driver_id}", headers=ctx.headers, json={"is_active": False}
    )
    assert response.status_code == 502
    assert ctx.repo.rows[driver_id].is_active is False  # fail closed


def test_disabled_driver_token_stops_working_immediately(ctx) -> None:
    driver_id = _driver_id(ctx)
    driver_headers = headers_for(ctx.repo.rows[driver_id])
    assert ctx.client.get("/api/v1/profiles/me", headers=driver_headers).status_code == 200
    ctx.client.patch(
        f"/api/v1/admin/drivers/{driver_id}", headers=ctx.headers, json={"is_active": False}
    )
    assert ctx.client.get("/api/v1/profiles/me", headers=driver_headers).status_code == 403


@pytest.mark.parametrize("payload", [{}, {"role": "admin"}, {"is_active": None}, {"phone": "x"}])
def test_invalid_driver_updates_are_422(ctx, payload) -> None:
    driver_id = _driver_id(ctx)
    response = ctx.client.patch(
        f"/api/v1/admin/drivers/{driver_id}", headers=ctx.headers, json=payload
    )
    assert response.status_code == 422


# ---- Password reset --------------------------------------------------------------------


def test_admin_resets_a_driver_password(ctx) -> None:
    driver_id = _driver_id(ctx)
    response = ctx.client.post(
        f"/api/v1/admin/drivers/{driver_id}/password",
        headers=ctx.headers,
        json={"new_password": "BrandNewPass9"},
    )
    assert response.status_code == 204
    assert response.content == b""
    assert ctx.gateway.password_resets == [(driver_id, "BrandNewPass9")]


@pytest.mark.parametrize("password", ["short", "x" * 73, "   "])
def test_weak_reset_passwords_are_422(ctx, password) -> None:
    driver_id = _driver_id(ctx)
    response = ctx.client.post(
        f"/api/v1/admin/drivers/{driver_id}/password",
        headers=ctx.headers,
        json={"new_password": password},
    )
    assert response.status_code == 422
    assert ctx.gateway.password_resets == []


# ---- Service-level ------------------------------------------------------------------------


def test_service_builds_email_from_the_configured_domain() -> None:
    admin = make_profile(UserRole.ADMIN)
    repo = FakeProfileRepository(admin)
    gateway = FakeAuthAdminGateway(repo)
    settings = make_settings(driver_email_domain="drivers.example.test")
    service = DriverAdminService(repo, gateway, settings)
    service.create_driver(
        admin,
        DriverCreate(driver_id="d001", password="LongEnough1", full_name="Test Driver"),
    )
    assert gateway.created[0]["email"] == "d001@drivers.example.test"
