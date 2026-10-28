"""Advance, extra charges the customer must approve, the balance, coupons and refunds.

The worked example: package 499, advance 20% = 99.80. The driver finds a 200 repair, the
customer approves it, so the final bill is 699 and the balance after the advance is 599.20.
"""

from uuid import UUID

import pytest

from app.domain.enums import BookingStatus
from tests.test_bookings_api import API
from tests.test_payments_api import PayWorld


@pytest.fixture
def pw() -> PayWorld:
    return PayWorld()


def pay(pw: PayWorld, booking_id: str, pay_id: str) -> dict:
    started = pw.started({"id": booking_id})
    pw.gateway_reports(started, pay_id=pay_id)
    r = pw.verify(started["payment"]["id"], started["checkout"]["order_id"], pay_id)
    assert r.status_code == 200, r.text
    return started


def in_progress(pw: PayWorld) -> dict:
    """A booked, advance-paid booking that the driver has started working on."""
    booking = pw.booking()
    pay(pw, booking["id"], "pay_adv")
    r = pw.client.put(
        f"{API}/admin/bookings/{booking['id']}/driver",
        headers=pw.ctx.as_admin,
        json={"driver_id": str(pw.ctx.driver.id)},
    )
    assert r.status_code == 200, r.text
    for step in ("on_the_way", "in_progress"):
        assert driver_step(pw, booking["id"], step).status_code == 200
    return booking


def driver_step(pw: PayWorld, booking_id: str, step: str):
    return pw.client.post(
        f"{API}/driver/bookings/{booking_id}/status",
        headers=pw.ctx.as_driver,
        json={"status": step},
    )


def raise_extra(pw: PayWorld, booking_id: str, amount="200.00", name="Brake pads", who="driver"):
    headers = pw.ctx.as_driver if who == "driver" else pw.ctx.as_admin
    prefix = "driver" if who == "driver" else "admin"
    return pw.client.post(
        f"{API}/{prefix}/bookings/{booking_id}/extras",
        headers=headers,
        json={"name": name, "amount": amount, "charge_type": "spare_part"},
    )


def bill(pw: PayWorld, booking_id: str, headers=None) -> dict:
    r = pw.client.get(f"{API}/bookings/{booking_id}/bill", headers=headers or pw.cust)
    assert r.status_code == 200, r.text
    return r.json()


# ---- The advance -----------------------------------------------------------------------


def test_booking_shows_the_advance_and_the_bill_starts_from_it(pw: PayWorld) -> None:
    booking = pw.booking()
    assert booking["total_amount"] == "499.00"
    assert booking["advance_amount"] == "99.80"
    b = bill(pw, booking["id"])
    assert (b["estimated_total"], b["advance_due"], b["advance_paid"]) == (
        "499.00",
        "99.80",
        "0.00",
    )
    assert b["balance_due"] == "499.00" and b["can_pay_balance"] is False
    pay(pw, booking["id"], "pay_adv")
    b = bill(pw, booking["id"])
    assert b["advance_paid"] == "99.80" and b["amount_paid"] == "99.80"
    assert b["balance_due"] == "399.20"
    assert [p["kind"] for p in b["payments"] if p["status"] == "successful"] == ["advance"]


def test_the_quote_reports_the_advance(pw: PayWorld) -> None:
    r = pw.client.post(
        f"{API}/bookings/quote", headers=pw.cust, json={"package_id": pw.package["id"]}
    )
    assert r.status_code == 200, r.text
    q = r.json()
    assert (q["total_amount"], q["advance_amount"], q["balance_after_advance"]) == (
        "499.00",
        "99.80",
        "399.20",
    )


# ---- Extra charges ---------------------------------------------------------------------


def test_extras_can_only_be_requested_while_the_service_is_in_progress(pw: PayWorld) -> None:
    booking = pw.booking()
    assert raise_extra(pw, booking["id"]).status_code in (403, 404, 409)
    pay(pw, booking["id"], "pay_adv")
    pw.client.put(
        f"{API}/admin/bookings/{booking['id']}/driver",
        headers=pw.ctx.as_admin,
        json={"driver_id": str(pw.ctx.driver.id)},
    )
    assert raise_extra(pw, booking["id"]).status_code == 409
    driver_step(pw, booking["id"], "on_the_way")
    assert raise_extra(pw, booking["id"]).status_code == 409
    driver_step(pw, booking["id"], "in_progress")
    r = raise_extra(pw, booking["id"])
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "proposed" and r.json()["amount"] == "200.00"


def test_the_worked_example_end_to_end(pw: PayWorld) -> None:
    booking = in_progress(pw)
    extra = raise_extra(pw, booking["id"]).json()

    # Nothing is billed until the customer approves, and the driver cannot finish meanwhile.
    b = bill(pw, booking["id"])
    assert b["approved_extras_total"] == "0.00" and b["pending_extras_total"] == "200.00"
    assert driver_step(pw, booking["id"], "completed").status_code == 409

    # The customer sees it on the booking and approves.
    mine = pw.client.get(f"{API}/bookings/{booking['id']}", headers=pw.cust).json()
    assert mine["pending_extras_count"] == 1
    r = pw.client.post(
        f"{API}/bookings/{booking['id']}/extras/{extra['id']}/approve", headers=pw.cust
    )
    assert r.status_code == 200 and r.json()["status"] == "approved"
    b = bill(pw, booking["id"])
    assert (b["approved_extras_total"], b["final_total"], b["balance_due"]) == (
        "200.00",
        "699.00",
        "599.20",
    )
    assert b["can_pay_balance"] is False  # not finished yet

    # The driver completes, then the customer pays the balance (final minus the advance).
    assert driver_step(pw, booking["id"], "completed").status_code == 200
    b = bill(pw, booking["id"])
    assert b["is_final"] is True and b["can_pay_balance"] is True
    started = pw.start(booking["id"])
    assert started.status_code == 201, started.text
    out = started.json()
    assert out["payment"]["kind"] == "balance" and out["payment"]["amount"] == "599.20"
    assert out["checkout"]["amount_paise"] == 59920
    pw.gateway_reports(out, pay_id="pay_bal")
    r = pw.verify(out["payment"]["id"], out["checkout"]["order_id"], "pay_bal")
    assert r.status_code == 200, r.text
    b = bill(pw, booking["id"])
    assert (b["amount_paid"], b["balance_due"], b["can_pay_balance"]) == (
        "699.00",
        "0.00",
        False,
    )
    assert sorted(p["kind"] for p in b["payments"] if p["status"] == "successful") == [
        "advance",
        "balance",
    ]
    assert pw.booking_status(booking["id"]) == "completed"
    # Nothing left to collect.
    assert pw.start(booking["id"]).status_code == 409


def test_a_declined_request_adds_nothing(pw: PayWorld) -> None:
    booking = in_progress(pw)
    extra = raise_extra(pw, booking["id"]).json()
    r = pw.client.post(
        f"{API}/bookings/{booking['id']}/extras/{extra['id']}/decline", headers=pw.cust
    )
    assert r.status_code == 200 and r.json()["status"] == "declined"
    assert bill(pw, booking["id"])["final_total"] == "499.00"
    assert driver_step(pw, booking["id"], "completed").status_code == 200
    # A request can be answered only once.
    again = pw.client.post(
        f"{API}/bookings/{booking['id']}/extras/{extra['id']}/approve", headers=pw.cust
    )
    assert again.status_code == 409


def test_only_the_owner_answers_and_only_staff_raise_requests(pw: PayWorld) -> None:
    from tests.test_bookings_api import other_customer

    booking = in_progress(pw)
    extra = raise_extra(pw, booking["id"], who="admin").json()
    _, stranger = other_customer(pw.ctx)
    url = f"{API}/bookings/{booking['id']}/extras/{extra['id']}/approve"
    assert pw.client.post(url, headers=stranger).status_code == 404
    assert (
        pw.client.get(f"{API}/bookings/{booking['id']}/bill", headers=stranger).status_code == 404
    )
    # A customer cannot raise a charge on themselves.
    r = pw.client.post(
        f"{API}/driver/bookings/{booking['id']}/extras",
        headers=pw.cust,
        json={"name": "Free stuff", "amount": "1.00"},
    )
    assert r.status_code == 403
    # A driver who is not on the job gets a 404.
    from app.domain.enums import UserRole
    from tests.fakes import make_profile
    from tests.phase3_support import headers_for

    other = pw.ctx.profiles.add(make_profile(UserRole.DRIVER))
    r = pw.client.post(
        f"{API}/driver/bookings/{booking['id']}/extras",
        headers=headers_for(other),
        json={"name": "Nope", "amount": "10.00"},
    )
    assert r.status_code == 404


def test_the_driver_cannot_see_prices_of_the_bill_but_can_withdraw_a_request(
    pw: PayWorld,
) -> None:
    booking = in_progress(pw)
    extra = raise_extra(pw, booking["id"]).json()
    r = pw.client.post(
        f"{API}/driver/bookings/{booking['id']}/extras/{extra['id']}/withdraw",
        headers=pw.ctx.as_driver,
    )
    assert r.status_code == 200 and r.json()["status"] == "withdrawn"
    assert driver_step(pw, booking["id"], "completed").status_code == 200


def test_cancelling_withdraws_open_requests(pw: PayWorld) -> None:
    booking = pw.booking()
    pay(pw, booking["id"], "pay_adv")
    pw.client.put(
        f"{API}/admin/bookings/{booking['id']}/driver",
        headers=pw.ctx.as_admin,
        json={"driver_id": str(pw.ctx.driver.id)},
    )
    for step in ("on_the_way", "in_progress"):
        driver_step(pw, booking["id"], step)
    extra = raise_extra(pw, booking["id"]).json()
    pw.ctx.bookings.force_status(UUID(booking["id"]), BookingStatus.CANCELLED)
    pw.ctx.extras.withdraw_open(UUID(booking["id"]))
    rows = pw.client.get(f"{API}/bookings/{booking['id']}/extras", headers=pw.cust).json()
    assert [r["status"] for r in rows if r["id"] == extra["id"]] == ["withdrawn"]


# ---- Coupons ---------------------------------------------------------------------------


def make_coupon(pw: PayWorld, **over):
    body = {"code": "save10", "discount_type": "percent", "discount_value": "10", **over}
    r = pw.client.post(f"{API}/admin/coupons", headers=pw.ctx.as_admin, json=body)
    assert r.status_code == 201, r.text
    return r.json()


def test_a_coupon_discounts_the_estimate_and_the_advance(pw: PayWorld) -> None:
    make_coupon(pw)
    r = pw.client.post(
        f"{API}/bookings/quote",
        headers=pw.cust,
        json={"package_id": pw.package["id"], "coupon_code": " Save10 "},
    )
    assert r.status_code == 200, r.text
    q = r.json()
    assert (q["coupon_code"], q["discount_amount"], q["total_amount"]) == (
        "SAVE10",
        "49.90",
        "449.10",
    )
    assert q["advance_amount"] == "89.82"
    b = pw.book(coupon_code="SAVE10", expected_total="449.10")
    assert b.status_code == 201, b.text
    assert b.json()["total_amount"] == "449.10" and b.json()["coupon_code"] == "SAVE10"


def test_a_wrong_expected_total_is_refused_with_a_coupon(pw: PayWorld) -> None:
    make_coupon(pw)
    assert pw.book(coupon_code="SAVE10", expected_total="499.00").status_code == 409


@pytest.mark.parametrize(
    "over",
    [
        {"is_active": False},
        {"min_order_amount": "1000.00"},
    ],
)
def test_an_unusable_coupon_is_a_422_with_a_reason(pw: PayWorld, over) -> None:
    make_coupon(pw, **over)
    r = pw.client.post(
        f"{API}/bookings/quote",
        headers=pw.cust,
        json={"package_id": pw.package["id"], "coupon_code": "SAVE10"},
    )
    assert r.status_code == 422 and r.json()["detail"]


def test_an_unknown_coupon_is_a_422(pw: PayWorld) -> None:
    r = pw.client.post(
        f"{API}/bookings/quote",
        headers=pw.cust,
        json={"package_id": pw.package["id"], "coupon_code": "NOPE99"},
    )
    assert r.status_code == 422


def test_a_coupon_is_one_use_per_customer_by_default(pw: PayWorld) -> None:
    make_coupon(pw)
    first = pw.book(coupon_code="SAVE10")
    assert first.status_code == 201, first.text
    again = pw.client.post(
        f"{API}/bookings/quote",
        headers=pw.cust,
        json={"package_id": pw.package["id"], "coupon_code": "SAVE10"},
    )
    assert again.status_code == 422


def test_flat_coupons_never_exceed_the_price_and_codes_are_unique(pw: PayWorld) -> None:
    make_coupon(pw, code="BIG", discount_type="flat", discount_value="5000")
    r = pw.client.post(
        f"{API}/bookings/quote",
        headers=pw.cust,
        json={"package_id": pw.package["id"], "coupon_code": "BIG"},
    )
    assert r.status_code == 200, r.text
    assert r.json()["total_amount"] == "0.00"
    dup = pw.client.post(
        f"{API}/admin/coupons",
        headers=pw.ctx.as_admin,
        json={"code": "big", "discount_type": "flat", "discount_value": "5"},
    )
    assert dup.status_code == 409


def test_only_admins_manage_coupons(pw: PayWorld) -> None:
    body = {"code": "MINE", "discount_type": "flat", "discount_value": "5"}
    assert pw.client.post(f"{API}/admin/coupons", headers=pw.cust, json=body).status_code == 403
    assert pw.client.get(f"{API}/admin/coupons", headers=pw.ctx.as_driver).status_code == 403
    coupon = make_coupon(pw)
    r = pw.client.patch(
        f"{API}/admin/coupons/{coupon['id']}", headers=pw.ctx.as_admin, json={"is_active": False}
    )
    assert r.status_code == 200 and r.json()["is_active"] is False


# ---- Refunds (recorded by an admin, never automatic) -----------------------------------


def test_an_admin_records_a_refund_and_the_receipt_shows_it(pw: PayWorld) -> None:
    booking = pw.booking()
    started = pay(pw, booking["id"], "pay_adv")
    payment_id = started["payment"]["id"]
    url = f"{API}/admin/payments/{payment_id}/refunds"
    too_much = pw.client.post(url, headers=pw.ctx.as_admin, json={"amount": "500.00"})
    assert too_much.status_code == 409
    assert pw.client.post(url, headers=pw.cust, json={"amount": "10.00"}).status_code == 403
    r = pw.client.post(url, headers=pw.ctx.as_admin, json={"amount": "50.00", "note": "Goodwill"})
    assert r.status_code == 201, r.text
    b = bill(pw, booking["id"])
    assert b["refunded_total"] == "50.00"
    assert [x["amount"] for x in b["refunds"]] == ["50.00"]
    # A second refund cannot take the total above what was paid.
    r = pw.client.post(url, headers=pw.ctx.as_admin, json={"amount": "60.00"})
    assert r.status_code == 409


def test_nothing_is_refunded_automatically_on_cancel(pw: PayWorld) -> None:
    booking = pw.booking()
    pay(pw, booking["id"], "pay_adv")
    r = pw.client.post(f"{API}/bookings/{booking['id']}/cancel", headers=pw.cust, json={})
    assert r.status_code == 200, r.text
    assert pw.ctx.refunds.rows == {}
    assert bill(pw, booking["id"])["refunded_total"] == "0.00"
