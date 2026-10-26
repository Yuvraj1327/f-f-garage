"""Saved vehicles, and the vehicle snapshot on a booking."""

import pytest

from app.domain.enums import UserRole
from tests.fakes import make_profile
from tests.phase3_support import Ctx, ctx, headers_for  # noqa: F401
from tests.test_bookings_api import World, w  # noqa: F401

URL = "/api/v1/vehicles"
GOOD = {
    "vehicle_type": "scooter",
    "registration_number": "mh 12-ab 1234",
    "make": "  TVS ",
    "model": "Jupiter",
    "nickname": "  Daily   ride ",
}


def add(ctx: Ctx, headers=None, **over):  # noqa: F811
    return ctx.client.post(URL, headers=headers or ctx.as_customer, json={**GOOD, **over})


def test_add_normalises_and_lists(ctx: Ctx):  # noqa: F811
    r = add(ctx)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["registration_number"] == "MH12AB1234"
    assert body["make"] == "TVS"
    assert body["nickname"] == "Daily ride"
    listed = ctx.client.get(URL, headers=ctx.as_customer).json()
    assert [v["id"] for v in listed] == [body["id"]]


@pytest.mark.parametrize("plate", ["MH12", "1234", "MH12AB12345", "abc", "MH12AB123!", "XX00"])
def test_bad_registration_is_refused(ctx: Ctx, plate):  # noqa: F811
    assert add(ctx, registration_number=plate).status_code == 422


@pytest.mark.parametrize("plate", ["MH12AB1234", "DL1CAB1234", "KA01X1234", "22BH1234AA"])
def test_real_plate_shapes_are_accepted(ctx: Ctx, plate):  # noqa: F811
    assert add(ctx, registration_number=plate).status_code == 201


@pytest.mark.parametrize(
    "over",
    [
        {"make": "A"},
        {"model": ""},
        {"vehicle_type": "car"},
        {"nickname": "x" * 31},
        {"role": "admin"},
    ],
)
def test_invalid_fields_are_refused(ctx: Ctx, over):  # noqa: F811
    assert add(ctx, **over).status_code == 422


def test_blank_nickname_is_optional(ctx: Ctx):  # noqa: F811
    assert add(ctx, nickname="   ").json()["nickname"] is None
    body = {k: v for k, v in GOOD.items() if k != "nickname"}
    body["registration_number"] = "MH14CD5678"
    assert ctx.client.post(URL, headers=ctx.as_customer, json=body).status_code == 201


def test_same_registration_twice_is_a_conflict_but_another_customer_may(ctx: Ctx):  # noqa: F811
    assert add(ctx).status_code == 201
    assert add(ctx, registration_number="MH12AB1234").status_code == 409
    other = ctx.profiles.add(make_profile(UserRole.CUSTOMER))
    assert add(ctx, headers=headers_for(other)).status_code == 201


def test_at_most_ten_vehicles(ctx: Ctx):  # noqa: F811
    for i in range(10):
        assert add(ctx, registration_number=f"MH12AB{1000 + i}").status_code == 201
    assert add(ctx, registration_number="MH12AB2000").status_code == 409


def test_edit_changes_only_what_was_sent(ctx: Ctx):  # noqa: F811
    vid = add(ctx).json()["id"]
    r = ctx.client.patch(f"{URL}/{vid}", headers=ctx.as_customer, json={"model": "Ntorq"})
    assert r.status_code == 200
    assert r.json()["model"] == "Ntorq" and r.json()["make"] == "TVS"
    r = ctx.client.patch(f"{URL}/{vid}", headers=ctx.as_customer, json={"nickname": None})
    assert r.json()["nickname"] is None
    assert ctx.client.patch(f"{URL}/{vid}", headers=ctx.as_customer, json={}).status_code == 422
    assert (
        ctx.client.patch(f"{URL}/{vid}", headers=ctx.as_customer, json={"make": None}).status_code
        == 422
    )


def test_editing_into_a_duplicate_registration_is_refused(ctx: Ctx):  # noqa: F811
    add(ctx)
    other = add(ctx, registration_number="MH14CD5678").json()["id"]
    r = ctx.client.patch(
        f"{URL}/{other}", headers=ctx.as_customer, json={"registration_number": "MH12AB1234"}
    )
    assert r.status_code == 409


def test_delete_removes_it(ctx: Ctx):  # noqa: F811
    vid = add(ctx).json()["id"]
    assert ctx.client.delete(f"{URL}/{vid}", headers=ctx.as_customer).status_code == 204
    assert ctx.client.get(URL, headers=ctx.as_customer).json() == []
    assert ctx.client.delete(f"{URL}/{vid}", headers=ctx.as_customer).status_code == 404


def test_someone_elses_vehicle_looks_missing(ctx: Ctx):  # noqa: F811
    vid = add(ctx).json()["id"]
    other = headers_for(ctx.profiles.add(make_profile(UserRole.CUSTOMER)))
    assert ctx.client.get(URL, headers=other).json() == []
    assert ctx.client.patch(f"{URL}/{vid}", headers=other, json={"model": "X1"}).status_code == 404
    assert ctx.client.delete(f"{URL}/{vid}", headers=other).status_code == 404
    assert len(ctx.vehicles.rows) == 1


@pytest.mark.parametrize("who", ["as_driver", "as_admin"])
def test_only_customers_have_vehicles(ctx: Ctx, who):  # noqa: F811
    headers = getattr(ctx, who)
    assert ctx.client.get(URL, headers=headers).status_code == 403
    assert ctx.client.post(URL, headers=headers, json=GOOD).status_code == 403


def test_anonymous_is_refused(ctx: Ctx):  # noqa: F811
    assert ctx.client.get(URL).status_code == 401


# ---- On a booking -----------------------------------------------------------------------


def test_booking_copies_the_vehicle_and_keeps_it_after_deletion(w: World):  # noqa: F811
    vid = add(w.ctx).json()["id"]
    r = w.book(vehicle_id=vid)
    assert r.status_code == 201, r.text
    booking = r.json()
    assert booking["vehicle_registration"] == "MH12AB1234"
    assert booking["vehicle_make"] == "TVS" and booking["vehicle_model"] == "Jupiter"
    assert booking["vehicle_nickname"] == "Daily ride"

    w.ctx.client.delete(f"{URL}/{vid}", headers=w.ctx.as_customer)
    again = w.ctx.client.get(f"/api/v1/bookings/{booking['id']}", headers=w.ctx.as_customer)
    assert again.json()["vehicle_registration"] == "MH12AB1234"


def test_booking_without_a_vehicle_still_works(w: World):  # noqa: F811
    r = w.book()
    assert r.status_code == 201
    assert r.json()["vehicle_registration"] is None


def test_booking_with_someone_elses_vehicle_is_refused(w: World):  # noqa: F811
    other = headers_for(w.ctx.profiles.add(make_profile(UserRole.CUSTOMER)))
    vid = add(w.ctx, headers=other).json()["id"]
    r = w.book(vehicle_id=vid)
    assert r.status_code == 404
    assert w.ctx.bookings.create_calls == 0


def test_booking_with_the_wrong_kind_of_vehicle_is_refused(w: World):  # noqa: F811
    vid = add(w.ctx, vehicle_type="bike").json()["id"]  # the service is for scooters
    r = w.book(vehicle_id=vid)
    assert r.status_code == 422
    assert "scooter" in r.json()["detail"] if "detail" in r.json() else True
    assert w.ctx.bookings.create_calls == 0
