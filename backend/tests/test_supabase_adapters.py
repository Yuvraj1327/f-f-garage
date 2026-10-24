"""The thin adapters over supabase-py, tested against stub clients.

These prove the QUERY SHAPES and error mapping we rely on. They cannot prove the
real Supabase service accepts them; that needs a live project (see README).
"""

from types import SimpleNamespace
from typing import Any

import httpx
import pytest
from postgrest.exceptions import APIError
from supabase_auth.errors import AuthApiError, AuthError

from app.core.errors import ConflictError, NotFoundError, ServiceUnavailableError, UpstreamError
from app.db.auth_admin import BAN_FOREVER, BAN_NONE, SupabaseAuthAdminGateway
from app.db.profile_repository import SupabaseProfileRepository
from tests.fakes import make_profile

# ---- PostgREST stub ------------------------------------------------------------------


class StubQuery:
    def __init__(self, result: Any) -> None:
        self.calls: list[tuple[str, tuple, dict]] = []
        self._result = result

    def __getattr__(self, name: str):
        def record(*args: Any, **kwargs: Any) -> "StubQuery":
            self.calls.append((name, args, kwargs))
            return self

        return record

    def execute(self) -> SimpleNamespace:
        if isinstance(self._result, Exception):
            raise self._result
        return SimpleNamespace(data=self._result)


class StubClient:
    def __init__(self, result: Any) -> None:
        self.query = StubQuery(result)
        self.tables: list[str] = []

    def table(self, name: str) -> StubQuery:
        self.tables.append(name)
        return self.query


def _row(profile) -> dict:
    return profile.model_dump(mode="json")


def test_get_selects_one_profile_by_id() -> None:
    profile = make_profile()
    client = StubClient([_row(profile)])
    assert SupabaseProfileRepository(client).get(str(profile.id)) == profile
    assert client.tables == ["profiles"]
    assert client.query.calls == [
        ("select", ("*",), {}),
        ("eq", ("id", str(profile.id)), {}),
        ("limit", (1,), {}),
    ]


def test_get_returns_none_when_no_row() -> None:
    assert SupabaseProfileRepository(StubClient([])).get("x") is None


def test_update_filters_by_id_and_sends_only_given_values() -> None:
    profile = make_profile(full_name="New")
    client = StubClient([_row(profile)])
    SupabaseProfileRepository(client).update(str(profile.id), {"full_name": "New"})
    assert client.query.calls == [
        ("update", ({"full_name": "New"},), {}),
        ("eq", ("id", str(profile.id)), {}),
    ]


def test_driver_queries_are_restricted_to_the_driver_role() -> None:
    client = StubClient([])
    repo = SupabaseProfileRepository(client)
    repo.get_driver("abc")
    assert ("eq", ("role", "driver"), {}) in client.query.calls
    client.query.calls.clear()
    repo.list_drivers()
    assert ("eq", ("role", "driver"), {}) in client.query.calls
    assert ("order", ("created_at",), {"desc": True}) in client.query.calls


def test_driver_login_id_exists() -> None:
    assert SupabaseProfileRepository(StubClient([{"id": "1"}])).driver_login_id_exists("d1")
    assert not SupabaseProfileRepository(StubClient([])).driver_login_id_exists("d1")


@pytest.mark.parametrize(
    "error",
    [APIError({"message": "boom", "code": "500"}), httpx.ConnectError("down")],
)
def test_database_failures_become_service_unavailable(error: Exception) -> None:
    with pytest.raises(ServiceUnavailableError):
        SupabaseProfileRepository(StubClient(error)).get("x")


# ---- Auth admin stub -------------------------------------------------------------------


class StubAdmin:
    def __init__(self) -> None:
        self.created: list[dict] = []
        self.updated: list[tuple[str, dict]] = []
        self.deleted: list[str] = []
        self.raise_on: dict[str, Exception] = {}
        self.user_id = "11111111-1111-1111-1111-111111111111"

    def create_user(self, attributes: dict) -> SimpleNamespace:
        if "create" in self.raise_on:
            raise self.raise_on["create"]
        self.created.append(attributes)
        return SimpleNamespace(user=SimpleNamespace(id=self.user_id))

    def update_user_by_id(self, uid: str, attributes: dict) -> None:
        if "update" in self.raise_on:
            raise self.raise_on["update"]
        self.updated.append((uid, attributes))

    def delete_user(self, uid: str) -> None:
        if "delete" in self.raise_on:
            raise self.raise_on["delete"]
        self.deleted.append(uid)


def _gateway() -> tuple[SupabaseAuthAdminGateway, StubAdmin]:
    admin = StubAdmin()
    client = SimpleNamespace(auth=SimpleNamespace(admin=admin))
    return SupabaseAuthAdminGateway(client), admin  # type: ignore[arg-type]


def test_create_driver_user_sends_the_expected_attributes() -> None:
    gateway, admin = _gateway()
    user_id = gateway.create_driver_user(
        email="d1@drivers.ffgarage.invalid",
        password="Secret123",
        driver_login_id="d1",
        full_name="Driver One",
        phone="+919800000001",
    )
    assert user_id == admin.user_id
    attrs = admin.created[0]
    assert attrs["email"] == "d1@drivers.ffgarage.invalid"
    assert attrs["password"] == "Secret123"
    assert attrs["email_confirm"] is True
    # These two fields are what the database trigger relies on:
    assert attrs["app_metadata"] == {"managed_driver": True, "driver_login_id": "d1"}
    assert attrs["user_metadata"] == {"full_name": "Driver One", "phone": "+919800000001"}


def test_create_driver_user_omits_phone_when_absent() -> None:
    gateway, admin = _gateway()
    gateway.create_driver_user(
        email="d1@x.invalid",
        password="Secret123",
        driver_login_id="d1",
        full_name="Driver One",
        phone=None,
    )
    assert admin.created[0]["user_metadata"] == {"full_name": "Driver One"}


@pytest.mark.parametrize("code", ["email_exists", "user_already_exists"])
def test_existing_user_is_a_conflict(code: str) -> None:
    gateway, admin = _gateway()
    admin.raise_on["create"] = AuthApiError("exists", 422, code)
    with pytest.raises(ConflictError):
        gateway.create_driver_user(
            email="a@b.invalid", password="x" * 9, driver_login_id="a", full_name="Aa", phone=None
        )


@pytest.mark.parametrize(
    "error",
    [
        AuthApiError("db error", 500, "unexpected_failure"),
        AuthError("x", None),
        httpx.ConnectError("down"),
    ],
)
def test_other_create_failures_are_upstream_errors(error: Exception) -> None:
    gateway, admin = _gateway()
    admin.raise_on["create"] = error
    with pytest.raises(UpstreamError):
        gateway.create_driver_user(
            email="a@b.invalid", password="x" * 9, driver_login_id="a", full_name="Aa", phone=None
        )


def test_set_password_and_ban_payloads() -> None:
    gateway, admin = _gateway()
    gateway.set_password("u1", "NewPass123")
    gateway.set_banned("u1", True)
    gateway.set_banned("u1", False)
    assert admin.updated == [
        ("u1", {"password": "NewPass123"}),
        ("u1", {"ban_duration": BAN_FOREVER}),
        ("u1", {"ban_duration": BAN_NONE}),
    ]
    assert BAN_NONE == "none"


def test_update_of_a_missing_user_is_not_found() -> None:
    gateway, admin = _gateway()
    admin.raise_on["update"] = AuthApiError("User not found", 404, "user_not_found")
    with pytest.raises(NotFoundError):
        gateway.set_password("u1", "NewPass123")


def test_other_update_failures_are_upstream_errors() -> None:
    gateway, admin = _gateway()
    admin.raise_on["update"] = AuthApiError("weak", 422, "weak_password")
    with pytest.raises(UpstreamError):
        gateway.set_password("u1", "NewPass123")


def test_delete_failure_is_an_upstream_error() -> None:
    gateway, admin = _gateway()
    admin.raise_on["delete"] = httpx.ConnectError("down")
    with pytest.raises(UpstreamError):
        gateway.delete_user("u1")
