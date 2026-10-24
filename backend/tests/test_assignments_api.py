"""Driver assignment and the driver's own work: who may do what, the status steps, and
consistency with bookings and payments. The assignment repository is an in-memory mirror of
the SQL functions in migration 10 (which supabase/tests/06 tests on a real PostgreSQL)."""

import uuid
from datetime import UTC, datetime

import pytest

from app.api.deps import get_auth_admin_gateway
from app.domain.enums import BookingStatus, PaymentStatus, UserRole
from tests.fakes import FakeAuthAdminGateway, make_profile
from tests.phase3_support import Ctx, ctx, headers_for  # noqa: F401
from tests.test_bookings_api import API, World

S = BookingStatus


class Work(World):
    """A bookable catalogue, a customer, an admin and two drivers."""

    def __init__(self, ctx: Ctx) -> None:
        super().__init__(ctx)
        self.client = ctx.client
        self.admin = ctx.as_admin
        self.cust = ctx.as_customer
        self.d1 = ctx.driver
        self.d1_headers = ctx.as_driver
        self.d2 = ctx.profiles.add(make_profile(UserRole.DRIVER, full_name="Second Driver"))
        self.d2_headers = headers_for(self.d2)

    # ---- bookings ----------------------------------------------------------------------
    def booking(self, headers=None, **over) -> dict:
        r = self.book(headers=headers, **over)
        assert r.status_code == 201, r.text
        return r.json()

    def mark_paid(self, booking_id: str) -> None:
        """What a verified payment leaves behind: a successful payment, booking confirmed."""
        bid = uuid.UUID(booking_id)
        row = self.ctx.bookings.rows[bid]
        attempt = self.ctx.payments.create_attempt(
            {
                "booking_id": booking_id,
                "customer_id": str(row["customer_id"]),
                "provider": "razorpay",
                "provider_order_id": f"order_{uuid.uuid4().hex[:8]}",
                "amount": str(row["package_price"] + row["extra_charges_total"]),
            }
        )
        self.ctx.payments._set(
            attempt,
            status=PaymentStatus.SUCCESSFUL,
            provider_payment_id=f"pay_{uuid.uuid4().hex[:8]}",
            paid_at=datetime.now(UTC),
        )
        self.ctx.bookings.confirm_paid(bid)

    def paid(self, headers=None, **over) -> dict:
        b = self.booking(headers=headers, **over)
        self.mark_paid(b["id"])
        return b

    # ---- calls -------------------------------------------------------------------------
    def assign(self, booking_id, driver, headers=None):
        driver_id = driver if isinstance(driver, str) else str(driver.id)
        return self.client.put(
            f"{API}/admin/bookings/{booking_id}/driver",
            headers=headers or self.admin,
            json={"driver_id": driver_id},
        )

    def unassign(self, booking_id, headers=None):
        return self.client.delete(
            f"{API}/admin/bookings/{booking_id}/driver", headers=headers or self.admin
        )

    def step(self, booking_id, status, headers=None):
        return self.client.post(
            f"{API}/driver/bookings/{booking_id}/status",
            headers=headers or self.d1_headers,
            json={"status": status},
        )

    def mine(self, headers=None, scope="open"):
        return self.client.get(
            f"{API}/driver/bookings", headers=headers or self.d1_headers, params={"scope": scope}
        )

    def as_customer_sees(self, booking_id) -> dict:
        return self.client.get(f"{API}/bookings/{booking_id}", headers=self.cust).json()

    def admin_sees(self, booking_id) -> dict:
        return self.client.get(f"{API}/admin/bookings/{booking_id}", headers=self.admin).json()

    def other_customer(self):
        profile = self.ctx.profiles.add(make_profile(UserRole.CUSTOMER))
        return profile, headers_for(profile)


@pytest.fixture
def w(ctx: Ctx) -> Work:  # noqa: F811
    return Work(ctx)


# ---- Assigning ---------------------------------------------------------------------------


def test_admin_assigns_a_paid_booking(w: Work) -> None:
    b = w.paid()
    assert w.admin_sees(b["id"])["can_assign"] is True
    r = w.assign(b["id"], w.d1)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "assigned"
    assert body["assignment"]["driver_id"] == str(w.d1.id)
    assert body["assignment"]["driver_name"] == w.d1.full_name
    assert body["assignment"]["driver_login_id"] == w.d1.driver_login_id
    assert body["assignment"]["assigned_by"] == str(w.ctx.admin.id)
    assert body["can_assign"] is True  # an assigned booking can be handed to someone else
    assert body["can_unassign"] is True


def test_an_unpaid_booking_cannot_be_assigned(w: Work) -> None:
    b = w.booking()
    assert w.admin_sees(b["id"])["can_assign"] is False
    r = w.assign(b["id"], w.d1)
    assert r.status_code == 409
    assert "not been paid" in r.json()["detail"]
    assert w.admin_sees(b["id"])["status"] == "pending_payment"


def test_a_confirmed_booking_without_a_verified_payment_cannot_be_assigned(w: Work) -> None:
    b = w.booking()
    w.ctx.bookings.confirm_paid(uuid.UUID(b["id"]))  # an old manual confirmation
    r = w.assign(b["id"], w.d1)
    assert r.status_code == 409
    assert "no verified payment" in r.json()["detail"]
    assert w.admin_sees(b["id"])["status"] == "confirmed"


def test_assigning_the_same_driver_again_changes_nothing(w: Work) -> None:
    b = w.paid()
    assert w.assign(b["id"], w.d1).status_code == 200
    again = w.assign(b["id"], w.d1)
    assert again.status_code == 200
    assert again.json()["status"] == "assigned"
    history = w.client.get(f"{API}/admin/bookings/{b['id']}/assignments", headers=w.admin).json()
    assert len(history) == 1


def test_reassigning_keeps_the_status_and_the_history(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    r = w.assign(b["id"], w.d2)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "assigned"
    assert r.json()["assignment"]["driver_id"] == str(w.d2.id)
    history = w.client.get(f"{API}/admin/bookings/{b['id']}/assignments", headers=w.admin).json()
    assert [(h["driver_id"], h["is_active"]) for h in history] == [
        (str(w.d2.id), True),
        (str(w.d1.id), False),
    ]
    assert history[1]["unassigned_at"] is not None
    assert history[0]["driver_name"] == "Second Driver"
    assert history[0]["assigned_by_name"] == w.ctx.admin.full_name


def test_an_on_the_way_booking_can_still_be_reassigned(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    assert w.step(b["id"], "on_the_way").status_code == 200
    r = w.assign(b["id"], w.d2)
    assert r.status_code == 200
    assert r.json()["status"] == "on_the_way"
    assert w.step(b["id"], "in_progress", w.d1_headers).status_code == 404
    assert w.step(b["id"], "in_progress", w.d2_headers).status_code == 200


def test_work_in_progress_or_finished_cannot_be_reassigned(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    for status in ("on_the_way", "in_progress"):
        assert w.step(b["id"], status).status_code == 200
    r = w.assign(b["id"], w.d2)
    assert r.status_code == 409
    assert "in progress" in r.json()["detail"]
    assert w.step(b["id"], "completed").status_code == 200
    assert w.assign(b["id"], w.d2).status_code == 409
    assert w.assign(b["id"], w.d1).status_code == 200  # same driver: harmless no-op


def test_a_cancelled_booking_cannot_be_assigned(w: Work) -> None:
    b = w.paid()
    assert (
        w.client.patch(
            f"{API}/admin/bookings/{b['id']}/status", headers=w.admin, json={"status": "cancelled"}
        ).status_code
        == 200
    )
    r = w.assign(b["id"], w.d1)
    assert r.status_code == 409
    assert "cancelled" in r.json()["detail"]


def test_unknown_booking_or_driver_is_not_found(w: Work) -> None:
    b = w.paid()
    assert w.assign(str(uuid.uuid4()), w.d1).status_code == 404
    assert w.assign(b["id"], str(uuid.uuid4())).status_code == 404
    # a customer or an admin is not a driver
    assert w.assign(b["id"], w.ctx.customer).status_code == 404
    assert w.assign(b["id"], w.ctx.admin).status_code == 404
    assert w.admin_sees(b["id"])["status"] == "confirmed"


def test_a_deactivated_driver_cannot_be_given_work(w: Work) -> None:
    b = w.paid()
    w.ctx.profiles.update(str(w.d2.id), {"is_active": False})
    r = w.assign(b["id"], w.d2)
    assert r.status_code == 409
    assert "deactivated" in r.json()["detail"]


def test_a_driver_cannot_be_in_two_places_at_once(w: Work) -> None:
    first = w.paid()
    _, other_headers = w.other_customer()
    second = w.paid(headers=other_headers)  # same date and slot
    assert w.assign(first["id"], w.d1).status_code == 200
    r = w.assign(second["id"], w.d1)
    assert r.status_code == 409
    assert "overlaps" in r.json()["detail"]
    assert w.assign(second["id"], w.d2).status_code == 200
    third = w.paid(time_slot_id=str(w.slot2.id))  # another slot, no overlap
    assert w.assign(third["id"], w.d1).status_code == 200


def test_assignment_input_is_validated(w: Work) -> None:
    b = w.paid()
    url = f"{API}/admin/bookings/{b['id']}/driver"
    assert w.client.put(url, headers=w.admin, json={}).status_code == 422
    assert w.client.put(url, headers=w.admin, json={"driver_id": "nope"}).status_code == 422
    r = w.client.put(url, headers=w.admin, json={"driver_id": str(w.d1.id), "extra": 1})
    assert r.status_code == 422
    assert (
        w.client.put(f"{API}/admin/bookings/not-a-uuid/driver", headers=w.admin).status_code == 422
    )


# ---- Unassigning -------------------------------------------------------------------------


def test_unassigning_returns_the_booking_to_confirmed(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    r = w.unassign(b["id"])
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "confirmed"
    assert r.json()["assignment"] is None
    assert r.json()["can_assign"] is True
    assert w.mine().json()["items"] == []
    assert w.unassign(b["id"]).status_code == 200  # nothing to remove: harmless
    assert w.assign(b["id"], w.d2).status_code == 200


def test_a_driver_who_has_set_off_cannot_be_removed(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    w.step(b["id"], "on_the_way")
    r = w.unassign(b["id"])
    assert r.status_code == 409
    assert "on the way" in r.json()["detail"]
    assert w.admin_sees(b["id"])["status"] == "on_the_way"
    assert w.unassign(str(uuid.uuid4())).status_code == 404


# ---- Who may call what -------------------------------------------------------------------


def test_only_admins_can_manage_assignments(w: Work) -> None:
    b = w.paid()
    calls = [
        ("put", f"{API}/admin/bookings/{b['id']}/driver", {"json": {"driver_id": str(w.d1.id)}}),
        ("delete", f"{API}/admin/bookings/{b['id']}/driver", {}),
        ("get", f"{API}/admin/bookings/{b['id']}/assignments", {}),
        ("get", f"{API}/admin/drivers/{w.d1.id}/bookings", {}),
    ]
    for method, url, kwargs in calls:
        for who, headers, code in (
            ("customer", w.cust, 403),
            ("driver", w.d1_headers, 403),
            ("anonymous", {}, 401),
        ):
            r = w.client.request(method, url, headers=headers, **kwargs)
            assert r.status_code == code, (method, url, who, r.status_code)
    assert w.admin_sees(b["id"])["status"] == "confirmed"


def test_only_drivers_can_use_the_driver_endpoints(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    calls = [
        ("get", f"{API}/driver/bookings", {}),
        ("get", f"{API}/driver/bookings/{b['id']}", {}),
        ("post", f"{API}/driver/bookings/{b['id']}/status", {"json": {"status": "on_the_way"}}),
    ]
    for method, url, kwargs in calls:
        for who, headers, code in (
            ("customer", w.cust, 403),
            ("admin", w.admin, 403),
            ("anonymous", {}, 401),
        ):
            r = w.client.request(method, url, headers=headers, **kwargs)
            assert r.status_code == code, (method, url, who, r.status_code)
    assert w.admin_sees(b["id"])["status"] == "assigned"


def test_a_deactivated_driver_loses_access_at_once(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    w.ctx.profiles.update(str(w.d1.id), {"is_active": False})
    assert w.mine().status_code == 403
    assert w.step(b["id"], "on_the_way").status_code == 403
    assert w.admin_sees(b["id"])["status"] == "assigned"
    # the admin can still see the work and move it to someone else
    assert w.assign(b["id"], w.d2).status_code == 200


# ---- The driver's list -------------------------------------------------------------------


def test_a_driver_sees_only_their_own_bookings(w: Work) -> None:
    mine = w.paid()
    _, other_headers = w.other_customer()
    theirs = w.paid(headers=other_headers)
    unassigned = w.paid(time_slot_id=str(w.slot2.id))
    w.assign(mine["id"], w.d1)
    w.assign(theirs["id"], w.d2)
    items = w.mine().json()["items"]
    assert [i["id"] for i in items] == [mine["id"]]
    assert [i["id"] for i in w.mine(w.d2_headers).json()["items"]] == [theirs["id"]]
    assert unassigned["id"] not in str(w.mine().json())


def test_a_driver_sees_what_they_need_for_the_visit(w: Work) -> None:
    b = w.paid(landmark="Near the temple", customer_notes="Gate code 1234")
    w.assign(b["id"], w.d1)
    item = w.mine().json()["items"][0]
    assert item["service_name"] == "General Service"
    assert item["package_name"] == "Basic"
    assert item["vehicle_type"] == "scooter"
    assert item["customer_name"] == w.ctx.customer.full_name
    assert item["customer_phone"] == w.ctx.customer.phone
    assert item["address_line"].startswith("12 MG Road")
    assert (item["landmark"], item["city"], item["pincode"]) == (
        "Near the temple",
        "Bhopal",
        "462001",
    )
    assert item["scheduled_date"] == b["scheduled_date"]
    assert (item["slot_start"], item["slot_end"]) == ("09:00:00", "11:00:00")
    assert item["customer_notes"] == "Gate code 1234"
    assert item["status"] == "assigned"
    assert item["next_status"] == "on_the_way"


def test_a_driver_never_sees_prices_or_payments(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    for body in (
        w.mine().json()["items"][0],
        w.client.get(f"{API}/driver/bookings/{b['id']}", headers=w.d1_headers).json(),
    ):
        forbidden = {
            "total_amount",
            "package_price",
            "extra_charges_total",
            "payment",
            "is_paid",
            "can_pay",
            "customer_id",
            "driver",
        }
        assert not forbidden & set(body)
        for charge in body["extra_charges"]:
            assert set(charge) >= {"name", "included_in_total"}


def test_open_and_history_scopes_are_separate_and_ordered(w: Work) -> None:
    first = w.paid()
    second = w.paid(time_slot_id=str(w.slot2.id))
    w.assign(first["id"], w.d1)
    w.assign(second["id"], w.d1)
    assert [i["id"] for i in w.mine().json()["items"]] == [first["id"], second["id"]]
    for status in ("on_the_way", "in_progress", "completed"):
        w.step(first["id"], status)
    assert [i["id"] for i in w.mine().json()["items"]] == [second["id"]]
    history = w.mine(scope="history").json()
    assert [i["id"] for i in history["items"]] == [first["id"]]
    assert history["items"][0]["status"] == "completed"
    assert history["items"][0]["next_status"] is None
    assert history["total"] == 1


def test_the_list_pages(w: Work) -> None:
    first = w.paid()
    second = w.paid(time_slot_id=str(w.slot2.id))
    w.assign(first["id"], w.d1)
    w.assign(second["id"], w.d1)
    page = w.client.get(
        f"{API}/driver/bookings", headers=w.d1_headers, params={"limit": 1, "offset": 1}
    ).json()
    assert page["total"] == 2
    assert [i["id"] for i in page["items"]] == [second["id"]]
    bad = w.client.get(f"{API}/driver/bookings", headers=w.d1_headers, params={"limit": 0})
    assert bad.status_code == 422
    bad = w.client.get(f"{API}/driver/bookings", headers=w.d1_headers, params={"scope": "all"})
    assert bad.status_code == 422


def test_someone_elses_booking_looks_like_a_missing_one(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    other = w.client.get(f"{API}/driver/bookings/{b['id']}", headers=w.d2_headers)
    missing = w.client.get(f"{API}/driver/bookings/{uuid.uuid4()}", headers=w.d2_headers)
    assert other.status_code == missing.status_code == 404
    assert other.json() == missing.json()
    mine = w.client.get(f"{API}/driver/bookings/{b['id']}", headers=w.d1_headers)
    assert mine.status_code == 200
    assert mine.json()["id"] == b["id"]


# ---- Status steps ------------------------------------------------------------------------


def test_the_driver_walks_a_booking_through_its_steps(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    for status, next_status in (
        ("on_the_way", "in_progress"),
        ("in_progress", "completed"),
        ("completed", None),
    ):
        r = w.step(b["id"], status)
        assert r.status_code == 200, r.text
        assert r.json()["status"] == status
        assert r.json()["next_status"] == next_status
        assert w.as_customer_sees(b["id"])["status"] == status
    done = w.admin_sees(b["id"])
    assert done["status"] == "completed"
    assert done["completed_at"] is not None
    assert done["assignment"]["driver_id"] == str(w.d1.id)


def test_a_step_cannot_be_skipped_or_reversed(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    skip = w.step(b["id"], "completed")
    assert skip.status_code == 409
    assert "Next step: on_the_way" in skip.json()["detail"]
    assert w.step(b["id"], "in_progress").status_code == 409
    w.step(b["id"], "on_the_way")
    assert w.step(b["id"], "completed").status_code == 409
    w.step(b["id"], "in_progress")
    assert w.step(b["id"], "on_the_way").status_code == 409
    w.step(b["id"], "completed")
    assert w.step(b["id"], "in_progress").status_code == 409
    assert w.admin_sees(b["id"])["status"] == "completed"


def test_repeating_a_step_is_harmless(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    assert w.step(b["id"], "on_the_way").status_code == 200
    again = w.step(b["id"], "on_the_way")
    assert again.status_code == 200
    assert again.json()["status"] == "on_the_way"


@pytest.mark.parametrize("target", ["cancelled", "confirmed", "assigned", "pending_payment"])
def test_a_driver_cannot_set_other_statuses(w: Work, target: str) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    r = w.step(b["id"], target)
    assert r.status_code == 422
    assert w.admin_sees(b["id"])["status"] == "assigned"


def test_the_status_request_is_validated(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    url = f"{API}/driver/bookings/{b['id']}/status"
    assert w.client.post(url, headers=w.d1_headers, json={}).status_code == 422
    assert w.client.post(url, headers=w.d1_headers, json={"status": "flying"}).status_code == 422
    body = {"status": "on_the_way", "driver_id": str(w.d2.id)}
    assert w.client.post(url, headers=w.d1_headers, json=body).status_code == 422


def test_another_driver_cannot_change_the_status(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    assert w.step(b["id"], "on_the_way", w.d2_headers).status_code == 404
    assert w.step(str(uuid.uuid4()), "on_the_way").status_code == 404
    assert w.admin_sees(b["id"])["status"] == "assigned"


def test_a_driver_moved_off_a_booking_cannot_change_it(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    w.assign(b["id"], w.d2)
    assert w.step(b["id"], "on_the_way", w.d1_headers).status_code == 404
    assert w.client.get(f"{API}/driver/bookings/{b['id']}", headers=w.d1_headers).status_code == 404
    assert w.mine().json()["items"] == []
    assert [i["id"] for i in w.mine(w.d2_headers).json()["items"]] == [b["id"]]


# ---- Customer visibility -----------------------------------------------------------------


def test_the_customer_sees_their_driver_once_assigned(w: Work) -> None:
    b = w.paid()
    assert w.as_customer_sees(b["id"])["driver"] is None
    w.assign(b["id"], w.d1)
    seen = w.as_customer_sees(b["id"])
    assert seen["driver"] == {"name": w.d1.full_name, "phone": w.d1.phone}
    assert seen["status"] == "assigned"
    page = w.client.get(f"{API}/bookings", headers=w.cust).json()
    assert page["items"][0]["driver"]["name"] == w.d1.full_name


def test_the_customer_never_sees_internal_driver_details(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    text = str(w.as_customer_sees(b["id"]))
    assert str(w.d1.id) not in text
    assert w.d1.driver_login_id not in text
    assert "assignment" not in w.as_customer_sees(b["id"])


def test_the_customer_sees_a_change_of_driver_and_progress(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    w.assign(b["id"], w.d2)
    assert w.as_customer_sees(b["id"])["driver"]["name"] == "Second Driver"
    w.step(b["id"], "on_the_way", w.d2_headers)
    assert w.as_customer_sees(b["id"])["status"] == "on_the_way"
    assert w.unassign(b["id"]).status_code == 409  # an on-the-way booking keeps its driver
    assert w.as_customer_sees(b["id"])["driver"]["name"] == "Second Driver"


def test_after_unassigning_the_customer_sees_no_driver(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    w.unassign(b["id"])
    seen = w.as_customer_sees(b["id"])
    assert seen["driver"] is None
    assert seen["status"] == "confirmed"


def test_other_customers_cannot_see_the_driver(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    _, headers = w.other_customer()
    assert w.client.get(f"{API}/bookings/{b['id']}", headers=headers).status_code == 404


# ---- Consistency with cancellation, editing and payment ----------------------------------


def test_the_customer_cancelling_an_assigned_booking_reaches_the_driver(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    r = w.client.post(f"{API}/bookings/{b['id']}/cancel", headers=w.cust, json={})
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "cancelled"
    assert r.json()["driver"] is None  # a cancelled booking shows no driver
    assert w.mine().json()["items"] == []
    history = w.mine(scope="history").json()["items"]
    assert [(i["id"], i["status"]) for i in history] == [(b["id"], "cancelled")]
    failed = w.step(b["id"], "on_the_way")
    assert failed.status_code == 409
    assert "cancelled" in failed.json()["detail"]
    # the paid booking is flagged for a refund decision, exactly as without a driver
    paid = next(iter(w.ctx.payments.rows.values()))
    assert paid.status == PaymentStatus.SUCCESSFUL
    assert paid.needs_review is True
    assert w.assign(b["id"], w.d2).status_code == 409


def test_an_admin_can_still_cancel_an_assigned_booking(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    seen = w.admin_sees(b["id"])
    assert seen["allowed_status_updates"] == ["cancelled"]
    r = w.client.patch(
        f"{API}/admin/bookings/{b['id']}/status", headers=w.admin, json={"status": "cancelled"}
    )
    assert r.status_code == 200
    assert r.json()["status"] == "cancelled"
    assert r.json()["assignment"]["driver_id"] == str(w.d1.id)  # kept for the record
    assert r.json()["can_assign"] is False


def test_an_assigned_booking_can_no_longer_be_edited_by_the_customer(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    r = w.client.patch(
        f"{API}/bookings/{b['id']}", headers=w.cust, json={"customer_notes": "Changed my mind"}
    )
    assert r.status_code == 409


def test_driver_steps_do_not_touch_the_payment(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    before = next(iter(w.ctx.payments.rows.values()))
    for status in ("on_the_way", "in_progress", "completed"):
        w.step(b["id"], status)
    after = next(iter(w.ctx.payments.rows.values()))
    assert (after.status, after.needs_review, after.paid_at) == (
        before.status,
        before.needs_review,
        before.paid_at,
    )
    assert w.as_customer_sees(b["id"])["is_paid"] is True


# ---- Admin views -------------------------------------------------------------------------


def test_the_booking_list_shows_who_has_each_booking(w: Work) -> None:
    mine = w.paid()
    waiting = w.paid(time_slot_id=str(w.slot2.id))
    w.assign(mine["id"], w.d1)
    page = w.client.get(f"{API}/admin/bookings", headers=w.admin).json()
    by_id = {i["id"]: i for i in page["items"]}
    assert by_id[mine["id"]]["assignment"]["driver_name"] == w.d1.full_name
    assert by_id[waiting["id"]]["assignment"] is None
    assert by_id[waiting["id"]]["can_assign"] is True
    # bookings that still need a driver are the confirmed ones
    needing = w.client.get(
        f"{API}/admin/bookings", headers=w.admin, params={"status": "confirmed"}
    ).json()
    assert [i["id"] for i in needing["items"]] == [waiting["id"]]


def test_admin_sees_a_drivers_bookings(w: Work) -> None:
    first = w.paid()
    second = w.paid(time_slot_id=str(w.slot2.id))
    w.assign(first["id"], w.d1)
    w.assign(second["id"], w.d1)
    for status in ("on_the_way", "in_progress", "completed"):
        w.step(first["id"], status)
    url = f"{API}/admin/drivers/{w.d1.id}/bookings"
    open_ = w.client.get(url, headers=w.admin).json()
    assert [i["id"] for i in open_["items"]] == [second["id"]]
    assert open_["items"][0]["assignment"]["driver_id"] == str(w.d1.id)
    done = w.client.get(url, headers=w.admin, params={"scope": "history"}).json()
    assert [i["id"] for i in done["items"]] == [first["id"]]
    assert w.client.get(url, headers=w.admin, params={"scope": "x"}).status_code == 422
    unknown = w.client.get(f"{API}/admin/drivers/{uuid.uuid4()}/bookings", headers=w.admin)
    assert unknown.status_code == 404
    customer_id = w.client.get(f"{API}/admin/drivers/{w.ctx.customer.id}/bookings", headers=w.admin)
    assert customer_id.status_code == 404


def test_the_assignment_history_of_an_unknown_booking_is_not_found(w: Work) -> None:
    r = w.client.get(f"{API}/admin/bookings/{uuid.uuid4()}/assignments", headers=w.admin)
    assert r.status_code == 404


def test_the_driver_list_shows_open_bookings(w: Work) -> None:
    b = w.paid()
    w.assign(b["id"], w.d1)
    listing = {d["id"]: d for d in w.client.get(f"{API}/admin/drivers", headers=w.admin).json()}
    assert listing[str(w.d1.id)]["open_bookings"] == 1
    assert listing[str(w.d2.id)]["open_bookings"] == 0
    one = w.client.get(f"{API}/admin/drivers/{w.d1.id}", headers=w.admin).json()
    assert one["open_bookings"] == 1
    for status in ("on_the_way", "in_progress", "completed"):
        w.step(b["id"], status)
    one = w.client.get(f"{API}/admin/drivers/{w.d1.id}", headers=w.admin).json()
    assert one["open_bookings"] == 0


def test_deactivating_a_driver_reports_their_open_bookings(w: Work) -> None:
    gateway = FakeAuthAdminGateway(w.ctx.profiles)
    w.ctx.client.app.dependency_overrides[get_auth_admin_gateway] = lambda: gateway
    b = w.paid()
    w.assign(b["id"], w.d1)
    r = w.client.patch(f"{API}/admin/drivers/{w.d1.id}", headers=w.admin, json={"is_active": False})
    assert r.status_code == 200
    assert r.json()["is_active"] is False
    assert r.json()["open_bookings"] == 1
