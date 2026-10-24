"""One booking through every module over the real HTTP stack: browse and price,
book, pay (verified server-side), admin assigns a driver, the driver works the job,
and the customer, admin and driver each see a consistent picture. Only the database
and the payment gateway are in-memory fakes."""

from app.domain.enums import UserRole
from tests.fakes import make_profile
from tests.phase3_support import headers_for
from tests.test_bookings_api import API
from tests.test_payments_api import PayWorld


def test_a_booking_from_browsing_to_completion() -> None:
    w = PayWorld()
    # Browse: the customer sees the catalogue, can check the PIN code and the slots.
    services = w.client.get(f"{API}/catalog/services", headers=w.cust).json()
    assert services, "the catalogue should list the active service"
    check = w.client.get(f"{API}/service-areas/check", headers=w.cust, params={"pincode": "462001"})
    assert check.json()["serviceable"] is True
    nope = w.client.get(f"{API}/service-areas/check", headers=w.cust, params={"pincode": "999999"})
    assert nope.json()["serviceable"] is False

    # Book (price comes from the catalogue) and pay.
    booking = w.booking(with_oil=True)
    assert booking["status"] == "pending_payment"
    started = w.started(booking)
    w.gateway_reports(started, pay_id="pay_journey")
    verified = w.verify(started["payment"]["id"], started["checkout"]["order_id"], "pay_journey")
    assert verified.status_code == 200, verified.text
    assert w.booking_status(booking["id"]) == "confirmed"

    # Admin sees it as paid and assigns a driver.
    admin = w.ctx.as_admin
    driver = w.ctx.driver
    listed = w.client.get(f"{API}/admin/bookings", headers=admin).json()
    assert booking["id"] in [b["id"] for b in listed["items"]]
    paid = w.client.get(f"{API}/admin/payments", headers=admin).json()
    assert paid["items"], "the successful payment must be visible to the admin"
    r = w.client.put(
        f"{API}/admin/bookings/{booking['id']}/driver",
        headers=admin,
        json={"driver_id": str(driver.id)},
    )
    assert r.status_code == 200, r.text

    # The driver sees only this job and works through it in order.
    d = w.ctx.as_driver
    jobs = w.client.get(f"{API}/driver/bookings", headers=d).json()
    assert [j["id"] for j in jobs["items"]] == [booking["id"]]
    other_driver = make_profile(UserRole.DRIVER)
    w.ctx.profiles.add(other_driver)
    theirs = w.client.get(f"{API}/driver/bookings", headers=headers_for(other_driver)).json()
    assert theirs["items"] == []
    skip = w.client.post(
        f"{API}/driver/bookings/{booking['id']}/status", headers=d, json={"status": "completed"}
    )
    assert skip.status_code == 409, "a step cannot be skipped"
    for step in ("on_the_way", "in_progress", "completed"):
        r = w.client.post(
            f"{API}/driver/bookings/{booking['id']}/status", headers=d, json={"status": step}
        )
        assert r.status_code == 200, r.text

    # The customer sees the finished booking, the full timeline and the notifications.
    mine = w.client.get(f"{API}/bookings/{booking['id']}", headers=w.cust).json()
    assert mine["status"] == "completed"
    assert [e["status"] for e in mine["timeline"]] == [
        "pending_payment",
        "confirmed",
        "assigned",
        "on_the_way",
        "in_progress",
        "completed",
    ]
    notes = w.client.get(f"{API}/notifications", headers=w.cust).json()
    assert notes["unread"] >= 4
    assert w.client.post(f"{API}/notifications/read", headers=w.cust, json={}).json()["unread"] == 0

    # A finished booking can no longer be paid for, changed or cancelled.
    assert w.start(booking["id"]).status_code in (409, 422)
    assert (
        w.client.post(f"{API}/bookings/{booking['id']}/cancel", headers=w.cust, json={}).status_code
        == 409
    )
