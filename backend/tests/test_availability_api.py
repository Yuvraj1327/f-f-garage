"""Time slots, exceptions and availability: admin management, customer view, booking guard."""

import uuid
from datetime import date, time

import pytest

from app.core.errors import ConflictError, NotFoundError
from app.services.availability_service import AvailabilityService
from tests.phase3_support import NOW, SETTINGS, ctx  # noqa: F401 (pytest fixture)

API = "/api/v1"
SLOTS = f"{API}/admin/availability/slots"
EXCEPTIONS = f"{API}/admin/availability/exceptions"
TOMORROW = "2026-10-20"  # Tuesday
SATURDAY = "2026-10-24"


def create_slot(ctx, **body):
    payload = {"start_time": "09:00", "end_time": "11:00", **body}
    return ctx.client.post(SLOTS, headers=ctx.as_admin, json=payload)


# ---- Slot management ---------------------------------------------------------------------


def test_admin_creates_edits_deactivates_and_deletes_a_slot(ctx) -> None:
    created = create_slot(ctx, capacity=2, days_of_week=[5, 1, 1, 3])
    assert created.status_code == 201
    slot = created.json()
    assert slot["days_of_week"] == [1, 3, 5] and slot["capacity"] == 2 and slot["is_active"]
    assert slot["start_time"] == "09:00:00"

    url = f"{SLOTS}/{slot['id']}"
    edited = ctx.client.patch(url, headers=ctx.as_admin, json={"end_time": "10:30", "capacity": 3})
    assert edited.status_code == 200 and edited.json()["end_time"] == "10:30:00"
    off = ctx.client.patch(url, headers=ctx.as_admin, json={"is_active": False})
    assert off.json()["is_active"] is False
    assert ctx.client.get(SLOTS, headers=ctx.as_admin).json()[0]["is_active"] is False
    assert ctx.client.delete(url, headers=ctx.as_admin).status_code == 204
    assert ctx.client.delete(url, headers=ctx.as_admin).status_code == 404


def test_overlapping_active_slots_are_rejected_but_adjacent_ones_are_fine(ctx) -> None:
    weekdays = [1, 2, 3, 4, 5]
    assert create_slot(ctx, days_of_week=weekdays).status_code == 201
    overlapping = create_slot(ctx, start_time="10:00", end_time="12:00", days_of_week=weekdays)
    assert overlapping.status_code == 409
    adjacent = create_slot(ctx, start_time="11:00", end_time="13:00", days_of_week=weekdays)
    assert adjacent.status_code == 201
    other_days = create_slot(ctx, start_time="10:00", end_time="12:00", days_of_week=[6, 7])
    assert other_days.status_code == 201
    slot_id = create_slot(ctx, start_time="15:00", end_time="16:00", days_of_week=weekdays).json()[
        "id"
    ]
    overlap_edit = ctx.client.patch(
        f"{SLOTS}/{slot_id}", headers=ctx.as_admin, json={"start_time": "12:30"}
    )
    assert overlap_edit.status_code == 409


@pytest.mark.parametrize(
    "body",
    [
        {"start_time": "11:00", "end_time": "09:00"},
        {"start_time": "09:00", "end_time": "09:00"},
        {"start_time": "09:00:30", "end_time": "11:00"},
        {"start_time": "9am", "end_time": "11:00"},
        {"capacity": 0},
        {"capacity": 51},
        {"days_of_week": []},
        {"days_of_week": [0]},
        {"days_of_week": [8]},
        {"days_of_week": ["mon"]},
        {"unknown": True},
    ],
)
def test_invalid_slot_payloads_are_rejected(ctx, body) -> None:
    assert create_slot(ctx, **body).status_code == 422
    assert not ctx.availability.slots


def test_slot_edit_cannot_make_it_end_before_it_starts(ctx) -> None:
    slot = create_slot(ctx).json()
    response = ctx.client.patch(
        f"{SLOTS}/{slot['id']}", headers=ctx.as_admin, json={"start_time": "12:00"}
    )
    assert response.status_code == 422


def test_slot_with_upcoming_bookings_keeps_its_times_and_cannot_be_deleted(ctx) -> None:
    slot = create_slot(ctx).json()
    ctx.availability.booked[(date(2026, 10, 21), time(9, 0), time(11, 0))] = 2
    url = f"{SLOTS}/{slot['id']}"
    assert (
        ctx.client.patch(url, headers=ctx.as_admin, json={"end_time": "12:00"}).status_code == 409
    )
    assert ctx.client.delete(url, headers=ctx.as_admin).status_code == 409
    # Capacity and deactivation do not move the slot, so they stay allowed.
    assert ctx.client.patch(url, headers=ctx.as_admin, json={"capacity": 4}).status_code == 200
    assert ctx.client.patch(url, headers=ctx.as_admin, json={"is_active": False}).status_code == 200


def test_bookings_in_the_past_do_not_lock_a_slot(ctx) -> None:
    slot = create_slot(ctx).json()
    ctx.availability.booked[(date(2026, 10, 1), time(9, 0), time(11, 0))] = 2
    assert ctx.client.delete(f"{SLOTS}/{slot['id']}", headers=ctx.as_admin).status_code == 204


# ---- Exceptions --------------------------------------------------------------------------


def test_admin_closes_a_day_and_a_slot_and_opens_a_slot(ctx) -> None:
    slot = create_slot(ctx).json()
    whole = ctx.client.post(
        EXCEPTIONS,
        headers=ctx.as_admin,
        json={"exception_date": "2026-11-08", "reason": "  Closed for Diwali "},
    )
    assert whole.status_code == 201
    assert whole.json()["reason"] == "Closed for Diwali" and whole.json()["time_slot_id"] is None

    closed = ctx.client.post(
        EXCEPTIONS,
        headers=ctx.as_admin,
        json={"exception_date": TOMORROW, "time_slot_id": slot["id"]},
    )
    assert closed.status_code == 201 and closed.json()["is_open"] is False

    opened = ctx.client.post(
        EXCEPTIONS,
        headers=ctx.as_admin,
        json={
            "exception_date": SATURDAY,
            "time_slot_id": slot["id"],
            "is_open": True,
            "capacity": 3,
        },
    )
    assert opened.status_code == 201 and opened.json()["capacity"] == 3

    listing = ctx.client.get(
        f"{EXCEPTIONS}?start_date=2026-10-19&end_date=2026-12-31", headers=ctx.as_admin
    ).json()
    assert [e["exception_date"] for e in listing] == [TOMORROW, SATURDAY, "2026-11-08"]


def test_duplicate_exception_for_the_same_date_and_slot_is_a_conflict(ctx) -> None:
    body = {"exception_date": TOMORROW}
    assert ctx.client.post(EXCEPTIONS, headers=ctx.as_admin, json=body).status_code == 201
    assert ctx.client.post(EXCEPTIONS, headers=ctx.as_admin, json=body).status_code == 409


@pytest.mark.parametrize(
    "body",
    [
        {"exception_date": "2026-10-18"},  # yesterday
        {"exception_date": "not-a-date"},
        {"exception_date": TOMORROW, "is_open": True},  # opening a whole day
        {"exception_date": TOMORROW, "capacity": 2},  # capacity on a closure
        {"exception_date": TOMORROW, "reason": "x" * 201},
        {
            "exception_date": TOMORROW,
            "reason": "ok",
            "time_slot_id": str(uuid.uuid4()),
        },  # no such slot
    ],
)
def test_invalid_exceptions_are_rejected(ctx, body) -> None:
    response = ctx.client.post(EXCEPTIONS, headers=ctx.as_admin, json=body)
    assert response.status_code in (404, 422)
    assert not ctx.availability.exceptions


def test_today_is_a_valid_exception_date(ctx) -> None:
    assert (
        ctx.client.post(
            EXCEPTIONS, headers=ctx.as_admin, json={"exception_date": "2026-10-19"}
        ).status_code
        == 201
    )


def test_exception_edit_and_delete(ctx) -> None:
    slot = create_slot(ctx).json()
    opened = ctx.client.post(
        EXCEPTIONS,
        headers=ctx.as_admin,
        json={
            "exception_date": SATURDAY,
            "time_slot_id": slot["id"],
            "is_open": True,
            "capacity": 3,
        },
    ).json()
    url = f"{EXCEPTIONS}/{opened['id']}"
    assert ctx.client.patch(url, headers=ctx.as_admin, json={"capacity": 5}).json()["capacity"] == 5
    closed = ctx.client.patch(url, headers=ctx.as_admin, json={"is_open": False})
    assert closed.json()["is_open"] is False and closed.json()["capacity"] is None
    assert ctx.client.patch(url, headers=ctx.as_admin, json={"capacity": 2}).status_code == 422
    assert ctx.client.patch(url, headers=ctx.as_admin, json={}).status_code == 422
    assert ctx.client.delete(url, headers=ctx.as_admin).status_code == 204
    assert ctx.client.delete(url, headers=ctx.as_admin).status_code == 404


def test_a_whole_day_exception_cannot_be_edited_into_an_opening(ctx) -> None:
    whole = ctx.client.post(
        EXCEPTIONS, headers=ctx.as_admin, json={"exception_date": TOMORROW}
    ).json()
    response = ctx.client.patch(
        f"{EXCEPTIONS}/{whole['id']}", headers=ctx.as_admin, json={"is_open": True}
    )
    assert response.status_code == 422


def test_exception_listing_validates_its_range(ctx) -> None:
    bad = ctx.client.get(
        f"{EXCEPTIONS}?start_date=2026-10-30&end_date=2026-10-20", headers=ctx.as_admin
    )
    assert bad.status_code == 422
    huge = ctx.client.get(
        f"{EXCEPTIONS}?start_date=2026-01-01&end_date=2028-01-01", headers=ctx.as_admin
    )
    assert huge.status_code == 422
    assert ctx.client.get(EXCEPTIONS, headers=ctx.as_admin).status_code == 422


def test_deleting_a_slot_removes_its_exceptions(ctx) -> None:
    slot = create_slot(ctx).json()
    ctx.client.post(
        EXCEPTIONS,
        headers=ctx.as_admin,
        json={"exception_date": TOMORROW, "time_slot_id": slot["id"]},
    )
    ctx.client.delete(f"{SLOTS}/{slot['id']}", headers=ctx.as_admin)
    assert not ctx.availability.exceptions


# ---- What customers see ------------------------------------------------------------------


def availability(ctx, start, end=None, who=None):
    params = {"start_date": start, **({"end_date": end} if end else {})}
    return ctx.client.get(f"{API}/availability", params=params, headers=who or ctx.as_customer)


def test_customer_sees_open_slots_and_how_many_spots_are_left(ctx) -> None:
    ctx.availability.add_slot("09:00", "11:00", capacity=2)
    ctx.availability.booked[(date(2026, 10, 20), time(9, 0), time(11, 0))] = 1
    response = availability(ctx, TOMORROW)
    assert response.status_code == 200
    (day,) = response.json()
    assert day["date"] == TOMORROW and day["is_open"] is True
    assert day["slots"][0]["available"] is True and day["slots"][0]["spots_left"] == 1


def test_customer_sees_why_a_slot_or_day_is_unavailable(ctx) -> None:
    ctx.availability.add_slot("09:00", "11:00", capacity=1)
    ctx.availability.booked[(date(2026, 10, 20), time(9, 0), time(11, 0))] = 1
    full = availability(ctx, TOMORROW).json()[0]
    assert full["is_open"] is False and full["closed_reason"] == "unavailable"
    assert full["slots"][0]["reason"] == "fully_booked"

    ctx.client.post(
        EXCEPTIONS, headers=ctx.as_admin, json={"exception_date": "2026-10-21", "reason": "Holiday"}
    )
    closed = availability(ctx, "2026-10-21").json()[0]
    assert (
        closed["closed_reason"] == "closed"
        and closed["note"] == "Holiday"
        and closed["slots"] == []
    )

    today = availability(ctx, "2026-10-19").json()[0]  # 08:00 now, 09:00 slot, 2h lead
    assert today["slots"][0]["reason"] == "lead_time_passed"
    assert availability(ctx, "2026-10-18").json()[0]["closed_reason"] == "past_date"
    assert availability(ctx, "2026-12-31").json()[0]["closed_reason"] == "outside_booking_window"


def test_inactive_slots_are_invisible_to_customers(ctx) -> None:
    ctx.availability.add_slot("09:00", "11:00", is_active=False)
    day = availability(ctx, TOMORROW).json()[0]
    assert day["closed_reason"] == "no_slots" and day["slots"] == []


def test_range_requests(ctx) -> None:
    ctx.availability.add_slot()
    week = availability(ctx, "2026-10-20", "2026-10-26").json()
    assert [d["date"] for d in week][0] == "2026-10-20" and len(week) == 7
    assert len(availability(ctx, "2026-10-20", "2026-11-19").json()) == 31
    assert availability(ctx, "2026-10-20", "2026-11-20").status_code == 422  # 32 days
    assert availability(ctx, "2026-10-26", "2026-10-20").status_code == 422
    assert availability(ctx, "garbage").status_code == 422
    assert ctx.client.get(f"{API}/availability", headers=ctx.as_customer).status_code == 422


def test_availability_is_readable_by_every_signed_in_role(ctx) -> None:
    ctx.availability.add_slot()
    for who in (ctx.as_customer, ctx.as_driver, ctx.as_admin):
        assert availability(ctx, TOMORROW, who=who).status_code == 200


# ---- Guard for the booking workflow ------------------------------------------------------


@pytest.fixture
def service(ctx):
    return AvailabilityService(ctx.availability, SETTINGS, clock=lambda tz: NOW.astimezone(tz))


def test_ensure_bookable_accepts_an_open_slot(ctx, service) -> None:
    slot = ctx.availability.add_slot()
    assert service.ensure_bookable(date(2026, 10, 20), slot.id).id == slot.id


def test_ensure_bookable_refuses_every_kind_of_invalid_slot(ctx, service) -> None:
    slot = ctx.availability.add_slot("09:00", "11:00", capacity=1, days=[1, 2, 3, 4, 5])
    inactive = ctx.availability.add_slot("14:00", "16:00", is_active=False)

    with pytest.raises(NotFoundError):
        service.ensure_bookable(date(2026, 10, 20), uuid.uuid4())
    with pytest.raises(NotFoundError):
        service.ensure_bookable(date(2026, 10, 20), inactive.id)
    with pytest.raises(ConflictError):  # past
        service.ensure_bookable(date(2026, 10, 18), slot.id)
    with pytest.raises(ConflictError):  # too soon (08:00 now, 09:00 slot, 2h lead)
        service.ensure_bookable(date(2026, 10, 19), slot.id)
    with pytest.raises(ConflictError):  # weekday it does not run (Saturday)
        service.ensure_bookable(date(2026, 10, 24), slot.id)
    with pytest.raises(ConflictError):  # outside the booking window
        service.ensure_bookable(date(2026, 12, 31), slot.id)

    ctx.availability.booked[(date(2026, 10, 21), time(9, 0), time(11, 0))] = 1
    with pytest.raises(ConflictError):  # full
        service.ensure_bookable(date(2026, 10, 21), slot.id)

    ctx.client.post(EXCEPTIONS, headers=ctx.as_admin, json={"exception_date": "2026-10-22"})
    with pytest.raises(ConflictError):  # whole day closed
        service.ensure_bookable(date(2026, 10, 22), slot.id)
