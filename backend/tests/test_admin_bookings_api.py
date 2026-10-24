"""Admin booking APIs: backend-only access, search/filter, details, permitted status updates."""

import uuid
from datetime import timedelta

import pytest

from app.domain.enums import BookingStatus, UserRole
from tests.fakes import make_profile
from tests.phase3_support import Ctx, ctx, headers_for  # noqa: F401
from tests.test_bookings_api import API, DAY, TODAY, World, other_customer, w  # noqa: F401


def admin_list(w: World, **params):
    r = w.ctx.client.get(f"{API}/admin/bookings", headers=w.ctx.as_admin, params=params)
    assert r.status_code == 200, r.text
    return r.json()


def ids(page) -> set[str]:
    return {b["id"] for b in page["items"]}


@pytest.fixture
def busy(w: World):
    """Three bookings by two customers on different days, PINs, and vehicles."""
    w.ctx.areas.add("462002", city="Bhopal")
    bike_service, bike_pkg = w.ctx.service_with_package(name="Bike Service", vehicle="bike")
    asha = w.ctx.customer
    ravi, ravi_headers = other_customer(w.ctx)
    w.ctx.profiles.rows[str(ravi.id)] = ravi.model_copy(
        update={"full_name": "Ravi Kumar", "phone": "+919811112222"}
    )
    a = w.book().json()
    b = w.book(
        headers=ravi_headers,
        scheduled_date=(TODAY + timedelta(days=3)).isoformat(),
        pincode="462002",
        package_id=bike_pkg["id"],
    ).json()
    c = w.book(scheduled_date=(TODAY + timedelta(days=5)).isoformat()).json()
    w.ctx.client.post(f"{API}/bookings/{c['id']}/cancel", headers=w.ctx.as_customer)
    return w, a, b, c, asha, ravi


# ---- Access: backend only, admins only ---------------------------------------------------


def test_admin_booking_routes_require_an_admin(w: World) -> None:
    b = w.book().json()
    c = w.ctx.client
    routes = [
        ("GET", f"{API}/admin/bookings", None),
        ("GET", f"{API}/admin/bookings/{b['id']}", None),
        ("PATCH", f"{API}/admin/bookings/{b['id']}/status", {"status": "confirmed"}),
    ]
    for method, url, body in routes:
        assert c.request(method, url, json=body).status_code == 401, (method, url)
        for headers in (w.ctx.as_customer, w.ctx.as_driver):
            r = c.request(method, url, json=body, headers=headers)
            assert r.status_code == 403, (method, url)
    assert w.ctx.bookings.rows[uuid.UUID(b["id"])]["status"] == BookingStatus.PENDING_PAYMENT


def test_a_disabled_admin_loses_access(w: World) -> None:
    gone = w.ctx.profiles.add(make_profile(UserRole.ADMIN, is_active=False))
    r = w.ctx.client.get(f"{API}/admin/bookings", headers=headers_for(gone))
    assert r.status_code == 403


# ---- List, search, filter ----------------------------------------------------------------


def test_admin_sees_every_customers_bookings_newest_first(busy) -> None:
    w, a, b, c, *_ = busy
    page = admin_list(w)
    assert page["total"] == 3
    assert [x["id"] for x in page["items"]] == [c["id"], b["id"], a["id"]]
    first = page["items"][0]
    assert {"customer_id", "service_area_id", "allowed_status_updates"} <= set(first)


def test_filter_by_status_vehicle_pin_and_dates(busy) -> None:
    w, a, b, c, *_ = busy
    assert ids(admin_list(w, status="cancelled")) == {c["id"]}
    assert ids(admin_list(w, status=["pending_payment", "cancelled"])) == {
        a["id"],
        b["id"],
        c["id"],
    }
    assert ids(admin_list(w, vehicle_type="bike")) == {b["id"]}
    assert ids(admin_list(w, pincode="462002")) == {b["id"]}
    assert ids(admin_list(w, date_from=b["scheduled_date"])) == {b["id"], c["id"]}
    assert ids(admin_list(w, date_to=b["scheduled_date"])) == {a["id"], b["id"]}
    assert ids(admin_list(w, date_from=b["scheduled_date"], date_to=b["scheduled_date"])) == {
        b["id"]
    }
    assert ids(admin_list(w, status="confirmed")) == set()


def test_filter_by_customer(busy) -> None:
    w, a, b, c, asha, ravi = busy
    assert ids(admin_list(w, customer_id=str(ravi.id))) == {b["id"]}
    assert ids(admin_list(w, customer_id=str(asha.id))) == {a["id"], c["id"]}


def test_search_by_booking_number_name_or_phone(busy) -> None:
    w, a, b, c, *_ = busy
    assert ids(admin_list(w, q="FF-000002")) == {b["id"]}
    assert ids(admin_list(w, q="ff000001")) == {a["id"]}
    assert ids(admin_list(w, q="3")) == {c["id"]}
    assert ids(admin_list(w, q="ravi")) == {b["id"]}
    assert ids(admin_list(w, q="Kumar")) == {b["id"]}
    assert ids(admin_list(w, q="9811112222")) == {b["id"]}
    assert ids(admin_list(w, q="nobody here")) == set()


def test_filters_combine(busy) -> None:
    w, a, b, c, *_ = busy
    assert ids(admin_list(w, q="test user", status="pending_payment")) == {a["id"]}


def test_paging_reports_the_total(busy) -> None:
    w, *_ = busy
    page = admin_list(w, limit=2)
    assert (len(page["items"]), page["total"], page["limit"]) == (2, 3, 2)
    assert len(admin_list(w, limit=2, offset=2)["items"]) == 1
    assert admin_list(w, offset=50)["items"] == []


def test_invalid_filters_are_rejected(w: World) -> None:
    c = w.ctx.client
    for params in (
        {"status": "nonsense"},
        {"vehicle_type": "car"},
        {"pincode": "12"},
        {"date_from": "yesterday"},
        {"limit": 0},
        {"limit": 101},
        {"offset": -1},
        {"customer_id": "x"},
        {"q": "x" * 61},
    ):
        assert (
            c.get(f"{API}/admin/bookings", headers=w.ctx.as_admin, params=params).status_code == 422
        )
    backwards = c.get(
        f"{API}/admin/bookings",
        headers=w.ctx.as_admin,
        params={"date_from": DAY, "date_to": (TODAY).isoformat()},
    )
    assert backwards.status_code == 422


def test_search_text_cannot_inject_filters(busy) -> None:
    w, *_ = busy
    # Characters that would change a PostgREST filter are not special in the fake, but the
    # request must still succeed and return nothing rather than error.
    for q in ("a,b", "x)(", "*", "%", "name.eq.x"):
        r = w.ctx.client.get(f"{API}/admin/bookings", headers=w.ctx.as_admin, params={"q": q})
        assert r.status_code == 200


# ---- Details -----------------------------------------------------------------------------


def test_admin_can_open_any_booking(busy) -> None:
    w, a, b, *_ = busy
    r = w.ctx.client.get(f"{API}/admin/bookings/{b['id']}", headers=w.ctx.as_admin)
    assert r.status_code == 200
    out = r.json()
    assert out["customer_name"] == "Ravi Kumar" and out["customer_phone"] == "+919811112222"
    assert out["booking_code"] == "FF-000002"
    assert out["allowed_status_updates"] == ["cancelled"]
    assert (
        w.ctx.client.get(f"{API}/admin/bookings/{uuid.uuid4()}", headers=w.ctx.as_admin).status_code
        == 404
    )


# ---- Status updates ----------------------------------------------------------------------


def set_status(w: World, booking_id, status, headers=None, **extra):
    return w.ctx.client.patch(
        f"{API}/admin/bookings/{booking_id}/status",
        headers=headers or w.ctx.as_admin,
        json={"status": status, **extra},
    )


def test_admin_cannot_confirm_a_booking_by_hand(w: World) -> None:
    """Only a payment the backend has verified confirms a booking."""
    b = w.book().json()
    r = set_status(w, b["id"], "confirmed")
    assert r.status_code == 422, r.text
    assert "payment" in r.json()["detail"]
    mine = w.ctx.client.get(f"{API}/bookings/{b['id']}", headers=w.ctx.as_customer).json()
    assert mine["status"] == "pending_payment" and mine["confirmed_at"] is None


def test_admin_cancels_with_a_reason_and_it_is_recorded(w: World) -> None:
    b = w.book().json()
    r = set_status(w, b["id"], "cancelled", reason="Area closed that day")
    assert r.status_code == 200
    out = r.json()
    assert (out["status"], out["cancellation_reason"]) == ("cancelled", "Area closed that day")
    assert out["cancelled_by"] == str(w.ctx.admin.id)
    # The customer sees it too, and the slot is free again.
    assert w.book().status_code == 201


def test_admin_can_cancel_even_close_to_the_visit(w: World) -> None:
    near = w.ctx.availability.add_slot("11:00", "13:00", capacity=1)
    b = w.book(scheduled_date=TODAY.isoformat(), time_slot_id=str(near.id)).json()
    w.ctx.bookings.force_status(uuid.UUID(b["id"]), BookingStatus.CONFIRMED)
    assert set_status(w, b["id"], "cancelled").status_code == 200


@pytest.mark.parametrize("status", ["assigned", "on_the_way", "in_progress", "completed"])
def test_statuses_owned_by_later_phases_cannot_be_set_by_hand(w: World, status) -> None:
    b = w.book().json()
    assert set_status(w, b["id"], status).status_code == 422
    assert w.ctx.bookings.rows[uuid.UUID(b["id"])]["status"] == BookingStatus.PENDING_PAYMENT


def test_a_booking_cannot_be_moved_back_to_pending_payment(w: World) -> None:
    b = w.book().json()
    w.ctx.bookings.force_status(uuid.UUID(b["id"]), BookingStatus.CONFIRMED)
    assert set_status(w, b["id"], "pending_payment").status_code == 422
    assert w.ctx.bookings.rows[uuid.UUID(b["id"])]["status"] == BookingStatus.CONFIRMED


def test_final_bookings_cannot_change(w: World) -> None:
    done = w.book().json()
    w.ctx.bookings.force_status(uuid.UUID(done["id"]), BookingStatus.COMPLETED)
    assert set_status(w, done["id"], "cancelled").status_code == 409
    assert set_status(w, done["id"], "confirmed").status_code == 422

    gone = w.book(time_slot_id=str(w.slot2.id)).json()
    set_status(w, gone["id"], "cancelled")
    assert set_status(w, gone["id"], "confirmed").status_code == 422


def test_confirm_is_never_a_manual_target(w: World) -> None:
    b = w.book().json()
    assert set_status(w, b["id"], "confirmed").status_code == 422
    w.ctx.bookings.force_status(uuid.UUID(b["id"]), BookingStatus.CONFIRMED)
    assert set_status(w, b["id"], "confirmed").status_code == 200  # already there: no change
    w.ctx.bookings.force_status(uuid.UUID(b["id"]), BookingStatus.ASSIGNED)
    assert set_status(w, b["id"], "confirmed").status_code == 422


def test_status_update_validation_and_unknown_booking(w: World) -> None:
    b = w.book().json()
    assert set_status(w, b["id"], "teleported").status_code == 422
    assert set_status(w, b["id"], "cancelled", reason="x" * 301).status_code == 422
    assert set_status(w, uuid.uuid4(), "cancelled").status_code == 404
    bad = w.ctx.client.patch(
        f"{API}/admin/bookings/{b['id']}/status",
        headers=w.ctx.as_admin,
        json={"status": "confirmed", "package_price": "1"},
    )
    assert bad.status_code == 422
