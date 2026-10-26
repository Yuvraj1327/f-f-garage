"""Admin-editable garage details, and what customers then see."""

import pytest

from tests.phase3_support import Ctx, ctx  # noqa: F401

URL = "/api/v1/admin/garage-settings"
CONTACT = "/api/v1/support/contact"
GOOD = {
    "name": "  F&F   Garage ",
    "phone": "+91 98765-43210",
    "whatsapp": "",
    "email": " help@example.com ",
    "address": "12 Main Road, Pune",
    "hours": "Mon-Sat 9am-7pm",
}


def test_before_anything_is_saved_the_environment_values_are_shown(ctx: Ctx):  # noqa: F811
    body = ctx.client.get(URL, headers=ctx.as_admin).json()
    assert body["source"] == "environment"
    assert body["name"] == "F&F Two Wheeler Garage"
    assert body["updated_at"] is None


def test_admin_saves_and_customers_see_the_new_details(ctx: Ctx):  # noqa: F811
    r = ctx.client.put(URL, headers=ctx.as_admin, json=GOOD)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["source"] == "database"
    assert body["name"] == "F&F Garage"
    assert body["phone"] == "+919876543210"
    assert body["email"] == "help@example.com"
    assert ctx.garage.saved_by == ctx.admin.id

    contact = ctx.client.get(CONTACT, headers=ctx.as_customer).json()
    assert contact["name"] == "F&F Garage"
    assert contact["phone"] == "+919876543210"
    assert contact["hours"] == "Mon-Sat 9am-7pm"
    assert contact["whatsapp"] == ""


def test_clearing_an_optional_field_hides_it(ctx: Ctx):  # noqa: F811
    ctx.client.put(URL, headers=ctx.as_admin, json=GOOD)
    ctx.client.put(URL, headers=ctx.as_admin, json={**GOOD, "phone": "", "address": ""})
    contact = ctx.client.get(CONTACT, headers=ctx.as_customer).json()
    assert contact["phone"] == "" and contact["address"] == ""


@pytest.mark.parametrize("who", ["as_customer", "as_driver"])
def test_only_an_admin_can_read_or_change_it(ctx: Ctx, who):  # noqa: F811
    headers = getattr(ctx, who)
    assert ctx.client.get(URL, headers=headers).status_code == 403
    assert ctx.client.put(URL, headers=headers, json=GOOD).status_code == 403
    assert ctx.garage.row is None


def test_anonymous_is_refused(ctx: Ctx):  # noqa: F811
    assert ctx.client.get(URL).status_code == 401
    assert ctx.client.put(URL, json=GOOD).status_code == 401


@pytest.mark.parametrize(
    "change",
    [
        {"name": "   "},
        {"name": "x" * 121},
        {"phone": "12"},
        {"phone": "1" * 16},
        {"email": "not-an-email"},
        {"address": "x" * 301},
        {"hours": "x" * 121},
        {"unknown": "field"},
    ],
)
def test_invalid_details_are_422_and_nothing_is_saved(ctx: Ctx, change):  # noqa: F811
    r = ctx.client.put(URL, headers=ctx.as_admin, json={**GOOD, **change})
    assert r.status_code == 422
    assert ctx.garage.row is None
