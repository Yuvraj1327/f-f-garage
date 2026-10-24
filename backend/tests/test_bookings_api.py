"""Customer booking API: quote, create, history, change, cancel, and who may do what."""

import uuid
from datetime import timedelta

import pytest

from app.domain.enums import BookingStatus, UserRole
from tests.fakes import make_profile
from tests.phase3_support import NOW, SETTINGS, Ctx, ctx, headers_for  # noqa: F401

API = "/api/v1"
TODAY = NOW.date()  # Monday 2026-10-19, 08:00 IST
DAY = (TODAY + timedelta(days=2)).isoformat()  # Wednesday


class World:
    """A catalogue, a serviceable PIN code and two slots, ready to book."""

    def __init__(self, ctx: Ctx) -> None:
        self.ctx = ctx
        self.service, self.package = ctx.service_with_package(inclusions=["Wash", "Oil top-up"])
        self.oil = self._charge("Engine oil", "350.00", "engine_oil")
        self.filter = self._charge("Air filter", None, "spare_part")
        self.area = ctx.areas.add("462001")
        self.slot = ctx.availability.add_slot("09:00", "11:00", capacity=2)
        self.slot2 = ctx.availability.add_slot("12:00", "14:00", capacity=1)

    def _charge(self, name, amount, kind, **extra):
        body = {"name": name, "charge_type": kind, **extra}
        if amount is not None:
            body["amount"] = amount
        r = self.ctx.client.post(
            f"{API}/admin/services/{self.service['id']}/extra-charges",
            headers=self.ctx.as_admin,
            json=body,
        )
        assert r.status_code == 201, r.text
        return r.json()

    def body(self, **over):
        data = {
            "package_id": self.package["id"],
            "pincode": "462001",
            "address_line": "12 MG Road, Near the temple",
            "scheduled_date": DAY,
            "time_slot_id": str(self.slot.id),
        }
        data.update(over)
        return data

    def book(self, headers=None, **over):
        return self.ctx.client.post(
            f"{API}/bookings", headers=headers or self.ctx.as_customer, json=self.body(**over)
        )


@pytest.fixture
def w(ctx: Ctx) -> World:  # noqa: F811
    return World(ctx)


def other_customer(ctx: Ctx):
    profile = ctx.profiles.add(make_profile(UserRole.CUSTOMER))
    return profile, headers_for(profile)


# ---- Quote -----------------------------------------------------------------------------


def test_quote_prices_come_from_the_catalogue(w: World) -> None:
    r = w.ctx.client.post(
        f"{API}/bookings/quote",
        headers=w.ctx.as_customer,
        json={"package_id": w.package["id"], "extra_charge_ids": [w.oil["id"]]},
    )
    assert r.status_code == 200, r.text
    q = r.json()
    assert (q["package_price"], q["extra_charges_total"], q["total_amount"]) == (
        "499.00",
        "350.00",
        "849.00",
    )
    assert q["inclusions"] == ["Wash", "Oil top-up"]
    by_name = {c["name"]: c for c in q["extra_charges"]}
    assert by_name["Engine oil"]["selected"] and by_name["Engine oil"]["selectable"]
    assert not by_name["Air filter"]["selectable"] and by_name["Air filter"]["amount"] is None


def test_quote_without_extras_is_just_the_package_price(w: World) -> None:
    r = w.ctx.client.post(
        f"{API}/bookings/quote", headers=w.ctx.as_customer, json={"package_id": w.package["id"]}
    )
    assert r.json()["total_amount"] == "499.00"
    assert all(not c["included_in_total"] for c in r.json()["extra_charges"])


def test_quote_rejects_charges_that_cannot_be_added_up_front(w: World) -> None:
    c = w.ctx.client
    at_actuals = c.post(
        f"{API}/bookings/quote",
        headers=w.ctx.as_customer,
        json={"package_id": w.package["id"], "extra_charge_ids": [w.filter["id"]]},
    )
    assert at_actuals.status_code == 422
    unknown = c.post(
        f"{API}/bookings/quote",
        headers=w.ctx.as_customer,
        json={"package_id": w.package["id"], "extra_charge_ids": [str(uuid.uuid4())]},
    )
    assert unknown.status_code == 422
    repeated = c.post(
        f"{API}/bookings/quote",
        headers=w.ctx.as_customer,
        json={"package_id": w.package["id"], "extra_charge_ids": [w.oil["id"], w.oil["id"]]},
    )
    assert repeated.status_code == 422


def test_quote_ignores_charges_of_another_package_and_inactive_ones(w: World) -> None:
    other_pkg = w.ctx.client.post(
        f"{API}/admin/services/{w.service['id']}/packages",
        headers=w.ctx.as_admin,
        json={"name": "Premium", "price": "899.00"},
    ).json()
    only_premium = w._charge("Premium wax", "100.00", "other", package_id=other_pkg["id"])
    r = w.ctx.client.post(
        f"{API}/bookings/quote",
        headers=w.ctx.as_customer,
        json={"package_id": w.package["id"], "extra_charge_ids": [only_premium["id"]]},
    )
    assert r.status_code == 422
    w.ctx.client.patch(
        f"{API}/admin/extra-charges/{w.oil['id']}",
        headers=w.ctx.as_admin,
        json={"is_active": False},
    )
    gone = w.ctx.client.post(
        f"{API}/bookings/quote",
        headers=w.ctx.as_customer,
        json={"package_id": w.package["id"], "extra_charge_ids": [w.oil["id"]]},
    )
    assert gone.status_code == 422


def test_quote_for_an_unavailable_package_is_404(w: World) -> None:
    c = w.ctx.client
    c.patch(
        f"{API}/admin/packages/{w.package['id']}", headers=w.ctx.as_admin, json={"is_active": False}
    )
    r = c.post(
        f"{API}/bookings/quote", headers=w.ctx.as_customer, json={"package_id": w.package["id"]}
    )
    assert r.status_code == 404
    missing = c.post(
        f"{API}/bookings/quote", headers=w.ctx.as_customer, json={"package_id": str(uuid.uuid4())}
    )
    assert missing.status_code == 404


# ---- Create ----------------------------------------------------------------------------


def test_create_booking_snapshots_everything_and_starts_pending_payment(w: World) -> None:
    r = w.book(extra_charge_ids=[w.oil["id"]], customer_notes="Gate code 1234")
    assert r.status_code == 201, r.text
    b = r.json()
    assert b["status"] == "pending_payment"
    assert b["booking_code"] == "FF-000001" and b["booking_number"] == 1
    assert (b["service_name"], b["package_name"]) == ("General Service", "Basic")
    assert b["package_inclusions"] == ["Wash", "Oil top-up"]
    assert (b["package_price"], b["extra_charges_total"], b["total_amount"]) == (
        "499.00",
        "350.00",
        "849.00",
    )
    # City and state come from the service area, not from the customer.
    assert (b["city"], b["state"], b["pincode"]) == ("Bhopal", "Madhya Pradesh", "462001")
    assert b["customer_name"] == "Test User" and b["customer_phone"] == "+919876543210"
    assert (b["scheduled_date"], b["slot_start"], b["slot_end"]) == (DAY, "09:00:00", "11:00:00")
    assert {(c["name"], c["included_in_total"]) for c in b["extra_charges"]} == {
        ("Engine oil", True),
        ("Air filter", False),
    }
    assert b["can_cancel"] is True and b["can_modify"] is True
    assert b["customer_notes"] == "Gate code 1234"
    assert "client_request_id" not in b and "customer_id" not in b


def test_snapshot_survives_later_catalogue_changes(w: World) -> None:
    booking = w.book().json()
    c = w.ctx.client
    c.patch(
        f"{API}/admin/packages/{w.package['id']}",
        headers=w.ctx.as_admin,
        json={"price": "999.00", "name": "Renamed"},
    )
    again = c.get(f"{API}/bookings/{booking['id']}", headers=w.ctx.as_customer).json()
    assert (again["package_price"], again["package_name"]) == ("499.00", "Basic")


@pytest.mark.parametrize(
    "tamper",
    [
        {"package_price": "1.00"},
        {"total_amount": "1.00"},
        {"price": "1.00"},
        {"extra_charges_total": "0"},
        {"status": "confirmed"},
        {"customer_id": str(uuid.uuid4())},
        {"city": "Elsewhere"},
        {"booking_number": 1},
    ],
)
def test_clients_cannot_send_prices_or_server_owned_fields(w: World, tamper) -> None:
    r = w.book(**tamper)
    assert r.status_code == 422
    assert w.ctx.bookings.rows == {}


def test_expected_total_is_only_a_safety_check(w: World) -> None:
    ok = w.book(extra_charge_ids=[w.oil["id"]], expected_total="849.00")
    assert ok.status_code == 201
    assert ok.json()["total_amount"] == "849.00"

    # The admin changes the price after the customer saw the summary.
    w.ctx.client.patch(
        f"{API}/admin/packages/{w.package['id']}", headers=w.ctx.as_admin, json={"price": "549.00"}
    )
    stale = w.book(scheduled_date=(TODAY + timedelta(days=3)).isoformat(), expected_total="499.00")
    assert stale.status_code == 409
    assert "price has changed" in stale.json()["detail"]
    assert len(w.ctx.bookings.rows) == 1

    lowball = w.book(scheduled_date=(TODAY + timedelta(days=3)).isoformat(), expected_total="1.00")
    assert lowball.status_code == 409


def test_booking_at_the_current_price_is_charged_the_current_price(w: World) -> None:
    w.ctx.client.patch(
        f"{API}/admin/packages/{w.package['id']}", headers=w.ctx.as_admin, json={"price": "549.00"}
    )
    assert w.book().json()["package_price"] == "549.00"


def test_inactive_service_or_package_cannot_be_booked(w: World) -> None:
    c = w.ctx.client
    c.patch(
        f"{API}/admin/services/{w.service['id']}", headers=w.ctx.as_admin, json={"is_active": False}
    )
    assert w.book().status_code == 404
    c.patch(
        f"{API}/admin/services/{w.service['id']}", headers=w.ctx.as_admin, json={"is_active": True}
    )
    c.patch(
        f"{API}/admin/packages/{w.package['id']}", headers=w.ctx.as_admin, json={"is_active": False}
    )
    assert w.book().status_code == 404
    assert w.book(package_id=str(uuid.uuid4())).status_code == 404
    assert w.ctx.bookings.rows == {}


def test_unserviceable_pin_codes_are_refused(w: World) -> None:
    assert w.book(pincode="560001").status_code == 422
    w.ctx.areas.add("560002", is_active=False)
    r = w.book(pincode="560002")
    assert r.status_code == 422 and "do not service" in r.json()["detail"]
    assert w.book(pincode="12345").status_code == 422
    assert w.ctx.bookings.rows == {}


def test_slots_that_cannot_be_booked_are_refused(w: World) -> None:
    past = w.book(scheduled_date=(TODAY - timedelta(days=1)).isoformat())
    assert past.status_code == 409
    too_far = w.book(
        scheduled_date=(TODAY + timedelta(days=SETTINGS.booking_window_days + 1)).isoformat()
    )
    assert too_far.status_code == 409
    # 10:00 is two hours away, the lead time is two hours; a 09:00 slot today has started.
    started = w.book(scheduled_date=TODAY.isoformat())
    assert started.status_code == 409
    assert w.book(time_slot_id=str(uuid.uuid4())).status_code == 404
    off = w.ctx.availability.add_slot("15:00", "16:00", is_active=False)
    assert w.book(time_slot_id=str(off.id)).status_code == 404
    assert w.ctx.bookings.rows == {}


def test_a_closed_day_or_slot_cannot_be_booked(w: World) -> None:
    c = w.ctx.client
    c.post(
        f"{API}/admin/availability/exceptions",
        headers=w.ctx.as_admin,
        json={"exception_date": DAY, "reason": "Diwali"},
    )
    assert w.book().status_code == 409
    assert w.ctx.bookings.rows == {}


def test_a_full_slot_is_refused_and_a_cancellation_frees_it(w: World) -> None:
    only = w.slot2  # capacity 1
    first = w.book(time_slot_id=str(only.id))
    assert first.status_code == 201
    _, other = other_customer(w.ctx)
    full = w.book(headers=other, time_slot_id=str(only.id))
    assert full.status_code == 409
    w.ctx.client.post(f"{API}/bookings/{first.json()['id']}/cancel", headers=w.ctx.as_customer)
    assert w.book(headers=other, time_slot_id=str(only.id)).status_code == 201


def test_availability_reflects_new_bookings(w: World) -> None:
    w.book()
    r = w.ctx.client.get(
        f"{API}/availability", headers=w.ctx.as_customer, params={"start_date": DAY}
    ).json()[0]
    left = {s["slot_id"]: s["spots_left"] for s in r["slots"]}
    assert left[str(w.slot.id)] == 1


def test_one_customer_cannot_hold_the_same_slot_twice(w: World) -> None:
    assert w.book().status_code == 201
    again = w.book()
    assert again.status_code == 409
    assert "already have a booking" in again.json()["detail"]
    assert len(w.ctx.bookings.rows) == 1
    # A different slot or day is fine.
    assert w.book(time_slot_id=str(w.slot2.id)).status_code == 201
    assert w.book(scheduled_date=(TODAY + timedelta(days=3)).isoformat()).status_code == 201


def test_a_repeated_request_key_returns_the_first_booking(w: World) -> None:
    key = str(uuid.uuid4())
    first = w.book(client_request_id=key)
    second = w.book(client_request_id=key)
    assert (first.status_code, second.status_code) == (201, 200)
    assert first.json()["id"] == second.json()["id"]
    assert len(w.ctx.bookings.rows) == 1


def test_a_request_key_is_not_shared_between_customers(w: World) -> None:
    key = str(uuid.uuid4())
    mine = w.book(client_request_id=key).json()
    _, other = other_customer(w.ctx)
    theirs = w.book(headers=other, client_request_id=key)
    assert theirs.status_code == 201
    assert theirs.json()["id"] != mine["id"]


def test_a_customer_without_name_or_phone_must_complete_the_profile(w: World) -> None:
    profile = w.ctx.profiles.add(make_profile(UserRole.CUSTOMER, phone=None))
    r = w.book(headers=headers_for(profile))
    assert r.status_code == 422 and "profile" in r.json()["detail"]
    assert w.ctx.bookings.rows == {}


def test_only_customers_can_create_bookings(w: World) -> None:
    c = w.ctx.client
    assert c.post(f"{API}/bookings", json=w.body()).status_code == 401
    assert w.book(headers=w.ctx.as_admin).status_code == 403
    assert w.book(headers=w.ctx.as_driver).status_code == 403
    assert (
        c.post(
            f"{API}/bookings/quote", headers=w.ctx.as_driver, json={"package_id": w.package["id"]}
        ).status_code
        == 403
    )
    assert w.ctx.bookings.rows == {}


def test_invalid_input_is_rejected(w: World) -> None:
    for bad in (
        {"address_line": "ab"},
        {"address_line": "x" * 251},
        {"customer_notes": "n" * 501},
        {"landmark": "l" * 121},
        {"latitude": 12.5},
        {"latitude": 91, "longitude": 10},
        {"scheduled_date": "not-a-date"},
        {"time_slot_id": "nope"},
    ):
        assert w.book(**bad).status_code == 422, bad
    ok = w.book(latitude=23.2599, longitude=77.4126, landmark="  Near the park ")
    assert ok.status_code == 201
    assert ok.json()["landmark"] == "Near the park"
    assert ok.json()["latitude"] == pytest.approx(23.2599)


# ---- Reading ---------------------------------------------------------------------------


def test_customers_only_see_their_own_bookings(w: World) -> None:
    mine = w.book().json()
    _, other = other_customer(w.ctx)
    theirs = w.book(headers=other, time_slot_id=str(w.slot2.id)).json()
    c = w.ctx.client

    listing = c.get(f"{API}/bookings", headers=w.ctx.as_customer).json()
    assert [b["id"] for b in listing["items"]] == [mine["id"]]
    assert listing["total"] == 1

    assert c.get(f"{API}/bookings/{mine['id']}", headers=w.ctx.as_customer).status_code == 200
    stranger = c.get(f"{API}/bookings/{theirs['id']}", headers=w.ctx.as_customer)
    missing = c.get(f"{API}/bookings/{uuid.uuid4()}", headers=w.ctx.as_customer)
    assert stranger.status_code == missing.status_code == 404
    assert stranger.json() == missing.json(), "a stranger's booking must look like a missing one"


def test_history_is_newest_first_with_paging_and_status_filter(w: World) -> None:
    ids = []
    for offset in (2, 3, 4):
        r = w.book(scheduled_date=(TODAY + timedelta(days=offset)).isoformat())
        ids.append(r.json()["id"])
    c = w.ctx.client
    page = c.get(f"{API}/bookings", headers=w.ctx.as_customer, params={"limit": 2}).json()
    assert [b["id"] for b in page["items"]] == [ids[2], ids[1]]
    assert (page["total"], page["limit"], page["offset"]) == (3, 2, 0)
    rest = c.get(
        f"{API}/bookings", headers=w.ctx.as_customer, params={"limit": 2, "offset": 2}
    ).json()
    assert [b["id"] for b in rest["items"]] == [ids[0]]

    c.post(f"{API}/bookings/{ids[0]}/cancel", headers=w.ctx.as_customer)
    cancelled = c.get(
        f"{API}/bookings", headers=w.ctx.as_customer, params={"status": "cancelled"}
    ).json()
    assert [b["id"] for b in cancelled["items"]] == [ids[0]]
    both = c.get(
        f"{API}/bookings",
        headers=w.ctx.as_customer,
        params=[("status", "cancelled"), ("status", "pending_payment")],
    ).json()
    assert both["total"] == 3
    for bad in ({"limit": 0}, {"limit": 101}, {"offset": -1}, {"status": "nonsense"}):
        assert c.get(f"{API}/bookings", headers=w.ctx.as_customer, params=bad).status_code == 422


def test_empty_history(w: World) -> None:
    r = w.ctx.client.get(f"{API}/bookings", headers=w.ctx.as_customer).json()
    assert r == {"items": [], "total": 0, "limit": 20, "offset": 0}


# ---- Changing --------------------------------------------------------------------------


def patch(w: World, booking_id, headers=None, **body):
    return w.ctx.client.patch(
        f"{API}/bookings/{booking_id}", headers=headers or w.ctx.as_customer, json=body
    )


def test_address_notes_and_location_can_be_changed(w: World) -> None:
    b = w.book(landmark="Old", latitude=23.0, longitude=77.0).json()
    r = patch(w, b["id"], address_line="14 New Road", landmark=None, customer_notes="Call first")
    assert r.status_code == 200, r.text
    out = r.json()
    assert (out["address_line"], out["landmark"], out["customer_notes"]) == (
        "14 New Road",
        None,
        "Call first",
    )
    assert out["package_price"] == "499.00" and out["total_amount"] == "499.00"
    cleared = patch(w, b["id"], latitude=None, longitude=None)
    assert cleared.json()["latitude"] is None
    assert patch(w, b["id"], latitude=12.0).status_code == 422


def test_changing_the_pin_code_revalidates_the_area(w: World) -> None:
    b = w.book().json()
    w.ctx.areas.add("462002", city="Indore")
    moved = patch(w, b["id"], pincode="462002")
    assert moved.status_code == 200
    assert (moved.json()["pincode"], moved.json()["city"]) == ("462002", "Indore")
    assert patch(w, b["id"], pincode="999999").status_code == 422
    assert w.ctx.bookings.rows[uuid.UUID(b["id"])]["pincode"] == "462002"


def test_rescheduling_checks_availability_and_capacity(w: World) -> None:
    b = w.book().json()
    _, other = other_customer(w.ctx)
    w.book(headers=other, time_slot_id=str(w.slot2.id))  # slot2 is now full
    full = patch(w, b["id"], scheduled_date=DAY, time_slot_id=str(w.slot2.id))
    assert full.status_code == 409
    free = patch(
        w,
        b["id"],
        scheduled_date=(TODAY + timedelta(days=4)).isoformat(),
        time_slot_id=str(w.slot.id),
    )
    assert (
        free.status_code == 200
        and free.json()["scheduled_date"] == (TODAY + timedelta(days=4)).isoformat()
    )
    past = patch(
        w,
        b["id"],
        scheduled_date=(TODAY - timedelta(days=1)).isoformat(),
        time_slot_id=str(w.slot.id),
    )
    assert past.status_code == 409
    assert patch(w, b["id"], scheduled_date=DAY).status_code == 422
    assert patch(w, b["id"], time_slot_id=str(w.slot.id)).status_code == 422


def test_resending_the_same_schedule_is_not_a_conflict_with_itself(w: World) -> None:
    only = w.slot2  # capacity 1, held by this very booking
    b = w.book(time_slot_id=str(only.id)).json()
    r = patch(w, b["id"], scheduled_date=DAY, time_slot_id=str(only.id), customer_notes="Same slot")
    assert r.status_code == 200, r.text
    assert r.json()["customer_notes"] == "Same slot"


def test_rescheduling_onto_a_slot_you_already_hold_is_refused(w: World) -> None:
    a = w.book().json()
    w.book(time_slot_id=str(w.slot2.id))
    r = patch(w, a["id"], scheduled_date=DAY, time_slot_id=str(w.slot2.id))
    assert r.status_code == 409


@pytest.mark.parametrize(
    "locked",
    [
        {"package_id": str(uuid.uuid4())},
        {"service_id": str(uuid.uuid4())},
        {"package_price": "1.00"},
        {"total_amount": "1.00"},
        {"status": "confirmed"},
        {"customer_phone": "+910000000000"},
        {"extra_charge_ids": []},
    ],
)
def test_price_service_and_status_cannot_be_patched(w: World, locked) -> None:
    b = w.book().json()
    assert patch(w, b["id"], **locked).status_code == 422
    row = w.ctx.bookings.rows[uuid.UUID(b["id"])]
    assert str(row["package_price"]) == "499.00" and row["status"] == BookingStatus.PENDING_PAYMENT


def test_empty_or_null_patches_are_rejected(w: World) -> None:
    b = w.book().json()
    assert patch(w, b["id"]).status_code == 422
    assert patch(w, b["id"], address_line=None).status_code == 422
    assert patch(w, b["id"], pincode=None).status_code == 422


def test_bookings_can_only_be_changed_before_assignment(w: World) -> None:
    b = w.book().json()
    booking_id = uuid.UUID(b["id"])
    for status in (
        BookingStatus.ASSIGNED,
        BookingStatus.ON_THE_WAY,
        BookingStatus.IN_PROGRESS,
        BookingStatus.COMPLETED,
        BookingStatus.CANCELLED,
    ):
        w.ctx.bookings.force_status(booking_id, status)
        r = patch(w, b["id"], customer_notes="late")
        assert r.status_code == 409, status
        assert r.json()["detail"] == "This booking can no longer be changed"


def test_a_booking_too_close_to_the_visit_cannot_be_changed(w: World) -> None:
    today_slot = w.ctx.availability.add_slot("11:00", "13:00", capacity=1)  # 3h away
    b = w.book(scheduled_date=TODAY.isoformat(), time_slot_id=str(today_slot.id)).json()
    r = patch(w, b["id"], customer_notes="too late")
    assert r.status_code == 409 and "until 4 hour" in r.json()["detail"]
    assert b["can_modify"] is False


def test_other_customers_and_roles_cannot_change_a_booking(w: World) -> None:
    b = w.book().json()
    _, other = other_customer(w.ctx)
    assert patch(w, b["id"], headers=other, customer_notes="x").status_code == 404
    assert patch(w, b["id"], headers=w.ctx.as_admin, customer_notes="x").status_code == 403
    assert patch(w, b["id"], headers=w.ctx.as_driver, customer_notes="x").status_code == 403
    assert (
        w.ctx.client.patch(f"{API}/bookings/{b['id']}", json={"customer_notes": "x"}).status_code
        == 401
    )


# ---- Cancelling ------------------------------------------------------------------------


def cancel(w: World, booking_id, headers=None, **body):
    return w.ctx.client.post(
        f"{API}/bookings/{booking_id}/cancel",
        headers=headers or w.ctx.as_customer,
        json=body or None,
    )


def test_a_pending_booking_can_be_cancelled_with_a_reason(w: World) -> None:
    b = w.book().json()
    r = cancel(w, b["id"], reason="Changed my mind")
    assert r.status_code == 200, r.text
    out = r.json()
    assert out["status"] == "cancelled" and out["cancellation_reason"] == "Changed my mind"
    assert out["cancelled_at"] is not None
    assert out["can_cancel"] is False and out["can_modify"] is False
    assert w.ctx.bookings.rows[uuid.UUID(b["id"])]["cancelled_by"] == w.ctx.customer.id


def test_cancel_without_a_body_works(w: World) -> None:
    b = w.book().json()
    assert cancel(w, b["id"]).status_code == 200


def test_a_repeated_cancel_is_not_an_error(w: World) -> None:
    b = w.book().json()
    assert cancel(w, b["id"]).status_code == 200
    again = cancel(w, b["id"])
    assert again.status_code == 200 and again.json()["status"] == "cancelled"


def test_cancelling_a_confirmed_booking_respects_the_cutoff(w: World) -> None:
    far = w.book().json()  # Wednesday, plenty of time
    w.ctx.bookings.force_status(uuid.UUID(far["id"]), BookingStatus.CONFIRMED)
    assert cancel(w, far["id"]).status_code == 200

    near_slot = w.ctx.availability.add_slot("11:00", "13:00", capacity=1)  # 3h from now
    near = w.book(scheduled_date=TODAY.isoformat(), time_slot_id=str(near_slot.id)).json()
    assert near["can_cancel"] is True, "pending bookings are always cancellable"
    w.ctx.bookings.force_status(uuid.UUID(near["id"]), BookingStatus.CONFIRMED)
    r = cancel(w, near["id"])
    assert r.status_code == 409 and "hour(s) before" in r.json()["detail"]
    shown = w.ctx.client.get(f"{API}/bookings/{near['id']}", headers=w.ctx.as_customer).json()
    assert shown["can_cancel"] is False and "hour(s) before" in shown["cancel_blocked_reason"]


@pytest.mark.parametrize(
    "status",
    [BookingStatus.ON_THE_WAY, BookingStatus.IN_PROGRESS, BookingStatus.COMPLETED],
)
def test_late_bookings_cannot_be_cancelled_online(w: World, status) -> None:
    b = w.book().json()
    w.ctx.bookings.force_status(uuid.UUID(b["id"]), status)
    assert cancel(w, b["id"]).status_code == 409


def test_cancelling_frees_the_slot_and_allows_rebooking(w: World) -> None:
    b = w.book().json()
    assert w.book().status_code == 409
    cancel(w, b["id"])
    assert w.book().status_code == 201


def test_other_customers_cannot_cancel_my_booking(w: World) -> None:
    b = w.book().json()
    _, other = other_customer(w.ctx)
    assert cancel(w, b["id"], headers=other).status_code == 404
    assert cancel(w, b["id"], headers=w.ctx.as_admin).status_code == 403
    assert cancel(w, b["id"], headers=w.ctx.as_driver).status_code == 403
    assert w.ctx.bookings.rows[uuid.UUID(b["id"])]["status"] == BookingStatus.PENDING_PAYMENT


def test_cancel_rejects_unknown_fields_and_long_reasons(w: World) -> None:
    b = w.book().json()
    assert cancel(w, b["id"], status="completed").status_code == 422
    assert cancel(w, b["id"], reason="x" * 301).status_code == 422
