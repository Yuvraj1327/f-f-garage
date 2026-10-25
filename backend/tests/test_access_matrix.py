"""Every API route against every kind of caller.

The routes are read from the OpenAPI document, so a new endpoint is picked up
automatically and fails here until it is classified. Anonymous callers get 401
everywhere except the health probes and the signed payment webhook; a signed-in
caller of the wrong role gets 403 (the role check runs before the request body
or path is validated, so the answer does not depend on the dummy ids used here).
"""

import re
import uuid

import pytest

from tests.phase3_support import Ctx, ctx  # noqa: F401

PUBLIC = {"/api/v1/health", "/api/v1/health/ready", "/api/v1/webhooks/razorpay"}

# Any signed-in, active user.
ANY_ROLE = {
    ("GET", "/api/v1/profiles/me"),
    ("GET", "/api/v1/catalog/services"),
    ("GET", "/api/v1/catalog/services/{service_id}"),
    ("GET", "/api/v1/service-areas/check"),
    ("GET", "/api/v1/availability"),
    ("GET", "/api/v1/support/contact"),
}
# Customers only (but not under /admin or /driver).
CUSTOMER_ONLY_PREFIXES = (
    "/api/v1/bookings",
    "/api/v1/payments",
    "/api/v1/notifications",
    "/api/v1/maps",
)


def required_role(method: str, path: str) -> str | None:
    """The only role allowed, 'any' for every signed-in role, None for public."""
    if path in PUBLIC:
        return None
    if (method, path) in ANY_ROLE:
        return "any"
    if path.startswith("/api/v1/admin/"):
        return "admin"
    if path.startswith("/api/v1/driver/"):
        return "driver"
    if path == "/api/v1/profiles/me" or path.startswith(CUSTOMER_ONLY_PREFIXES):
        return "customer"
    raise AssertionError(f"{method} {path} is not classified in the access matrix")


def all_operations(ctx: Ctx) -> list[tuple[str, str]]:
    paths = ctx.client.app.openapi()["paths"]
    return sorted(
        (method.upper(), path)
        for path, item in paths.items()
        for method in item
        if method in {"get", "post", "put", "patch", "delete"}
    )


def fill(path: str) -> str:
    return re.sub(r"\{[^}]+\}", str(uuid.uuid4()), path)


def call(ctx: Ctx, method: str, path: str, headers: dict | None = None):
    return ctx.client.request(method, fill(path), headers=headers or {}, json={})


def test_every_route_is_classified(ctx: Ctx):  # noqa: F811
    for method, path in all_operations(ctx):
        required_role(method, path)


def test_anonymous_callers_are_refused_everywhere_but_public_routes(ctx: Ctx):  # noqa: F811
    for method, path in all_operations(ctx):
        if required_role(method, path) is None:
            continue
        status = call(ctx, method, path).status_code
        assert status == 401, f"{method} {path} answered {status} without a token"


@pytest.mark.parametrize("who", ["customer", "driver", "admin"])
def test_wrong_role_is_forbidden_and_right_role_is_let_in(ctx: Ctx, who):  # noqa: F811
    headers = getattr(ctx, f"as_{who}")
    for method, path in all_operations(ctx):
        need = required_role(method, path)
        if need is None:
            continue
        status = call(ctx, method, path, headers).status_code
        if need in ("any", who):
            assert status not in (401, 403), f"{who} was refused {method} {path} ({status})"
        else:
            assert status == 403, f"{who} got {status} from {method} {path}"


def test_a_disabled_account_is_refused_everywhere(ctx: Ctx):  # noqa: F811
    ctx.profiles.rows[str(ctx.customer.id)] = ctx.customer.model_copy(update={"is_active": False})
    for method, path in all_operations(ctx):
        if required_role(method, path) is None:
            continue
        status = call(ctx, method, path, ctx.as_customer).status_code
        assert status == 403, f"{method} {path} let a disabled account in ({status})"
