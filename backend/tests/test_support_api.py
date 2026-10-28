"""The configurable garage contact details endpoint."""

import pytest

from tests.conftest import CONFIGURED_SUPABASE, make_settings
from tests.jwt_helpers import HS256_SECRET
from tests.phase3_support import Ctx, ctx, headers_for  # noqa: F401

URL = "/api/v1/support/contact"


def test_requires_sign_in(ctx: Ctx):  # noqa: F811
    assert ctx.client.get(URL).status_code == 401


@pytest.mark.parametrize("who", ["as_admin", "as_customer", "as_driver"])
def test_every_role_can_read(ctx: Ctx, who):  # noqa: F811
    r = ctx.client.get(URL, headers=getattr(ctx, who))
    assert r.status_code == 200
    assert set(r.json()) == {
        "name",
        "phone",
        "whatsapp",
        "email",
        "address",
        "hours",
        "refund_policy",
    }


def test_unconfigured_fields_are_empty(ctx: Ctx):  # noqa: F811
    body = ctx.client.get(URL, headers=ctx.as_customer).json()
    assert body["name"] == "F&F Two Wheeler Garage"
    assert body["phone"] == body["email"] == body["address"] == body["hours"] == ""
    assert body["whatsapp"] == ""


def test_configured_values_are_returned_and_phones_cleaned():
    settings = make_settings(
        **CONFIGURED_SUPABASE,
        supabase_jwt_secret=HS256_SECRET,
        garage_phone="+91 98765-43210",
        garage_whatsapp="91 98765 43210",
        garage_email=" help@example.com ",
        garage_address="12 Main Road, Pune",
        garage_hours="Mon-Sat 9am-7pm",
    )
    c = Ctx(settings)
    body = c.client.get(URL, headers=c.as_customer).json()
    assert body["phone"] == "+919876543210"
    assert body["whatsapp"] == "919876543210"
    assert body["email"] == "help@example.com"
    assert body["address"] == "12 Main Road, Pune"
    assert body["hours"] == "Mon-Sat 9am-7pm"


def test_disabled_account_is_refused(ctx: Ctx):  # noqa: F811
    ctx.profiles.rows[str(ctx.customer.id)] = ctx.customer.model_copy(update={"is_active": False})
    assert ctx.client.get(URL, headers=ctx.as_customer).status_code == 403
