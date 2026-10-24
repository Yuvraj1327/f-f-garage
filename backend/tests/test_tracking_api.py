"""Customer booking tracking and notifications through the API: what the customer sees
after payments, admin actions and driver actions, and who can see what. The history and
notifications come from an in-memory mirror of the migration-11 triggers (fakes_tracking)."""

import uuid

import pytest

from app.domain.enums import UserRole
from tests.fakes import make_profile
from tests.phase3_support import Ctx, ctx, headers_for  # noqa: F401
from tests.test_assignments_api import Work
from tests.test_bookings_api import API


@pytest.fixture
def w(ctx: Ctx) -> Work:  # noqa: F811
    return Work(ctx)


def mine(w: Work, headers=None, **params):
    r = w.client.get(f"{API}/notifications", headers=headers or w.cust, params=params)
    assert r.status_code == 200, r.text
    return r.json()


def kinds(w: Work, headers=None) -> list[str]:
    return [n["kind"] for n in reversed(mine(w, headers)["items"])]


def timeline(w: Work, booking_id: str) -> list[str]:
    return [e["status"] for e in w.as_customer_sees(booking_id)["timeline"]]


# ---- Timeline ----------------------------------------------------------------------------


def test_a_new_booking_has_a_one_step_timeline_and_no_notifications(w: Work) -> None:
    b = w.booking()
    assert timeline(w, b["id"]) == ["pending_payment"]
    assert b["timeline"][0]["status"] == "pending_payment"
    assert mine(w) == {"items": [], "total": 0, "unread": 0, "limit": 20, "offset": 0}


def test_the_timeline_follows_payment_assignment_and_the_driver_steps(w: Work) -> None:
    b = w.paid()
    assert timeline(w, b["id"]) == ["pending_payment", "confirmed"]
    w.assign(b["id"], w.d1)
    assert timeline(w, b["id"]) == ["pending_payment", "confirmed", "assigned"]
    for step in ("on_the_way", "in_progress", "completed"):
        assert w.step(b["id"], step).status_code == 200
    assert timeline(w, b["id"]) == [
        "pending_payment",
        "confirmed",
        "assigned",
        "on_the_way",
        "in_progress",
        "completed",
    ]
    stamps = [e["at"] for e in w.as_customer_sees(b["id"])["timeline"]]
    assert stamps == sorted(stamps)


def test_a_reassignment_adds_no_timeline_step_but_a_removal_does(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    w.assign(b["id"], w.d2)
    assert timeline(w, b["id"]) == ["pending_payment", "confirmed", "assigned"]
    w.unassign(b["id"])
    assert timeline(w, b["id"]) == ["pending_payment", "confirmed", "assigned", "confirmed"]


def test_cancellation_ends_the_timeline(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    r = w.client.post(f"{API}/bookings/{b['id']}/cancel", headers=w.cust, json={})
    assert r.status_code == 200, r.text
    assert r.json()["timeline"][-1]["status"] == "cancelled"
    assert timeline(w, b["id"]) == ["pending_payment", "confirmed", "assigned", "cancelled"]


def test_an_admin_cancellation_is_shown_to_the_customer(w: Work) -> None:
    b = w.booking()
    r = w.client.patch(
        f"{API}/admin/bookings/{b['id']}/status",
        headers=w.admin,
        json={"status": "cancelled", "reason": "Out of area"},
    )
    assert r.status_code == 200, r.text
    assert timeline(w, b["id"]) == ["pending_payment", "cancelled"]
    assert kinds(w) == ["booking_cancelled"]


def test_the_admin_view_carries_the_timeline_too(w: Work) -> None:
    b = w.paid()
    assert [e["status"] for e in w.admin_sees(b["id"])["timeline"]] == [
        "pending_payment",
        "confirmed",
    ]


def test_list_views_do_not_carry_a_timeline(w: Work) -> None:
    w.paid()
    items = w.client.get(f"{API}/bookings", headers=w.cust).json()["items"]
    assert items[0]["timeline"] == []
    items = w.client.get(f"{API}/admin/bookings", headers=w.admin).json()["items"]
    assert items[0]["timeline"] == []


# ---- Notifications for each event ---------------------------------------------------------


def test_notifications_follow_the_booking_lifecycle(w: Work) -> None:
    b = w.paid()
    assert kinds(w) == ["booking_confirmed"]
    w.assign(b["id"], w.d1)
    w.assign(b["id"], w.d2)
    w.unassign(b["id"])
    w.assign(b["id"], w.d1)
    for step in ("on_the_way", "in_progress", "completed"):
        w.step(b["id"], step)
    assert kinds(w) == [
        "booking_confirmed",
        "driver_assigned",
        "driver_changed",
        "driver_removed",
        "driver_changed",
        "driver_on_the_way",
        "service_started",
        "service_completed",
    ]


def test_repeating_actions_does_not_repeat_notifications(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    w.assign(b["id"], w.d1)
    w.step(b["id"], "on_the_way")
    w.step(b["id"], "on_the_way")
    assert kinds(w) == ["booking_confirmed", "driver_assigned", "driver_on_the_way"]


def test_a_refused_action_sends_nothing(w: Work) -> None:
    b = w.booking()
    assert w.assign(b["id"], w.d1).status_code == 409  # not paid
    assert kinds(w) == []
    p = w.paid(time_slot_id=str(w.slot2.id))
    assert w.step(p["id"], "on_the_way").status_code == 404  # no driver yet
    assert kinds(w) == ["booking_confirmed"]


def test_a_failed_payment_notifies_but_does_not_confirm(w: Work) -> None:
    b = w.booking()
    attempt = w.ctx.payments.create_attempt(
        {
            "booking_id": b["id"],
            "customer_id": str(w.ctx.customer.id),
            "provider": "razorpay",
            "provider_order_id": "order_x1",
            "amount": "499.00",
        }
    )
    w.ctx.payments._set(attempt, status="failed", failure_reason="Card declined")
    assert kinds(w) == ["payment_failed"]
    assert w.as_customer_sees(b["id"])["status"] == "pending_payment"
    assert timeline(w, b["id"]) == ["pending_payment"]


def test_messages_name_the_booking_and_the_driver(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    items = mine(w)["items"]
    assert items[0]["kind"] == "driver_assigned"
    assert w.d1.full_name in items[0]["body"]
    assert items[0]["booking_code"] == b["booking_code"]
    assert items[0]["booking_id"] == b["id"]
    assert items[1]["body"].startswith(f"Payment received for {b['booking_code']}")
    assert items[0]["is_read"] is False


def test_notifications_hold_no_contact_details_or_ids_of_others(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    text = str(mine(w))
    assert str(w.d1.id) not in text
    assert (w.d1.phone or "no-phone") not in text
    assert set(mine(w)["items"][0]) == {
        "id",
        "booking_id",
        "booking_code",
        "kind",
        "title",
        "body",
        "created_at",
        "is_read",
    }


# ---- Reading and marking ------------------------------------------------------------------


def test_unread_count_paging_and_unread_only(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    w.step(b["id"], "on_the_way")
    assert w.client.get(f"{API}/notifications/unread-count", headers=w.cust).json() == {"unread": 3}
    page = mine(w, limit=2)
    assert (page["total"], page["unread"], len(page["items"])) == (3, 3, 2)
    assert page["items"][0]["kind"] == "driver_on_the_way"  # newest first
    second = mine(w, limit=2, offset=2)
    assert [n["kind"] for n in second["items"]] == ["booking_confirmed"]


def test_marking_some_then_all_read(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    w.step(b["id"], "on_the_way")
    first = mine(w)["items"][0]["id"]
    r = w.client.post(f"{API}/notifications/read", headers=w.cust, json={"ids": [first]})
    assert r.json() == {"updated": 1, "unread": 2}
    assert [n["is_read"] for n in mine(w)["items"]] == [True, False, False]
    only = mine(w, unread_only=True)
    assert (only["total"], only["unread"]) == (2, 2)

    r = w.client.post(f"{API}/notifications/read", headers=w.cust, json={})
    assert r.json() == {"updated": 2, "unread": 0}
    again = w.client.post(f"{API}/notifications/read", headers=w.cust, json={})
    assert again.json() == {"updated": 0, "unread": 0}


def test_unknown_or_malformed_ids(w: Work) -> None:
    w.paid()
    r = w.client.post(
        f"{API}/notifications/read", headers=w.cust, json={"ids": [str(uuid.uuid4())]}
    )
    assert r.json() == {"updated": 0, "unread": 1}
    bad = w.client.post(f"{API}/notifications/read", headers=w.cust, json={"ids": ["nope"]})
    assert bad.status_code == 422
    extra = w.client.post(f"{API}/notifications/read", headers=w.cust, json={"user_id": "x"})
    assert extra.status_code == 422
    too_many = w.client.post(
        f"{API}/notifications/read",
        headers=w.cust,
        json={"ids": [str(uuid.uuid4()) for _ in range(201)]},
    )
    assert too_many.status_code == 422


def test_list_limits_are_validated(w: Work) -> None:
    for params in ({"limit": 0}, {"limit": 101}, {"offset": -1}):
        r = w.client.get(f"{API}/notifications", headers=w.cust, params=params)
        assert r.status_code == 422, params


# ---- Who can see what ---------------------------------------------------------------------


def test_customers_only_ever_see_their_own_notifications(w: Work) -> None:
    mine_b = w.paid()
    other, other_headers = w.other_customer()
    w.assign(mine_b["id"], w.d1)
    assert mine(w, other_headers)["items"] == []
    assert w.client.get(f"{API}/notifications/unread-count", headers=other_headers).json() == {
        "unread": 0
    }

    # the other customer cannot mark mine read, by id
    first = mine(w)["items"][0]["id"]
    r = w.client.post(f"{API}/notifications/read", headers=other_headers, json={"ids": [first]})
    assert r.json()["updated"] == 0
    assert mine(w)["unread"] == 2
    # ...nor read my booking's timeline
    assert w.client.get(f"{API}/bookings/{mine_b['id']}", headers=other_headers).status_code == 404


def test_each_customer_is_notified_about_their_own_booking_only(w: Work) -> None:
    other, other_headers = w.other_customer()
    w.paid()
    w.paid(headers=other_headers, time_slot_id=str(w.slot2.id))
    assert kinds(w) == ["booking_confirmed"]
    assert kinds(w, other_headers) == ["booking_confirmed"]


def test_drivers_and_admins_have_no_notifications(w: Work) -> None:
    for headers in (w.d1_headers, w.admin):
        assert w.client.get(f"{API}/notifications", headers=headers).status_code == 403
        assert w.client.get(f"{API}/notifications/unread-count", headers=headers).status_code == 403
        assert (
            w.client.post(f"{API}/notifications/read", headers=headers, json={}).status_code == 403
        )


def test_signed_out_requests_are_refused(w: Work) -> None:
    assert w.client.get(f"{API}/notifications").status_code == 401
    assert w.client.get(f"{API}/notifications/unread-count").status_code == 401
    assert w.client.post(f"{API}/notifications/read", json={}).status_code == 401


def test_an_inactive_customer_is_refused(w: Work) -> None:
    gone = w.ctx.profiles.add(make_profile(UserRole.CUSTOMER, is_active=False))
    r = w.client.get(f"{API}/notifications", headers=headers_for(gone))
    assert r.status_code == 403


def test_the_customer_driver_card_still_hides_ids(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    seen = w.as_customer_sees(b["id"])
    assert set(seen["driver"]) == {"name", "phone"}
    assert seen["status"] == "assigned"
