"""The pure availability rules (no database, no HTTP, no real clock)."""

import uuid
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from app.domain import availability as av
from app.domain.availability import ExceptionRule, SlotRule, compute_day

IST = ZoneInfo("Asia/Kolkata")
# Monday 2026-10-19, 08:00 IST
NOW = datetime(2026, 10, 19, 8, 0, tzinfo=IST)
TODAY = NOW.date()
SLOT_A = SlotRule(uuid.uuid4(), time(9, 0), time(11, 0), 2, frozenset(range(1, 8)))
SLOT_B = SlotRule(uuid.uuid4(), time(14, 0), time(16, 0), 1, frozenset({1, 2, 3, 4, 5}))


def day(d, *, slots=(SLOT_A, SLOT_B), exceptions=(), booked=None, now=NOW, window=30, lead=120):
    return compute_day(
        d,
        now=now,
        slots=list(slots),
        exceptions=list(exceptions),
        booked=booked or {},
        window_days=window,
        lead_minutes=lead,
    )


def test_normal_future_day_lists_slots_in_time_order() -> None:
    result = day(TODAY + timedelta(days=1))
    assert result.is_open and result.closed_reason is None
    assert [s.start_time for s in result.slots] == [time(9, 0), time(14, 0)]
    assert all(s.available and s.reason is None for s in result.slots)
    assert [s.spots_left for s in result.slots] == [2, 1]


def test_past_dates_are_closed() -> None:
    result = day(TODAY - timedelta(days=1))
    assert not result.is_open and result.closed_reason == av.PAST_DATE and result.slots == []


def test_booking_window_is_inclusive_of_the_last_day() -> None:
    assert day(TODAY + timedelta(days=30)).is_open
    beyond = day(TODAY + timedelta(days=31))
    assert not beyond.is_open and beyond.closed_reason == av.OUTSIDE_WINDOW


def test_lead_time_blocks_slots_that_start_too_soon() -> None:
    # 08:00 now, 2h lead: the 09:00 slot is too soon, the 14:00 slot is fine.
    result = day(TODAY)
    first, second = result.slots
    assert not first.available and first.reason == av.LEAD_TIME_PASSED
    assert second.available


def test_lead_time_boundary_is_inclusive() -> None:
    now = datetime(2026, 10, 19, 7, 0, tzinfo=IST)  # exactly 2h before 09:00
    result = day(TODAY, now=now)
    assert result.slots[0].available


def test_slots_that_already_started_are_unavailable_even_with_zero_lead() -> None:
    now = datetime(2026, 10, 19, 9, 30, tzinfo=IST)
    result = day(TODAY, now=now, lead=0)
    assert result.slots[0].reason == av.LEAD_TIME_PASSED
    assert result.slots[1].available


def test_lead_time_uses_the_business_time_zone_not_utc() -> None:
    # 03:00 UTC == 08:30 IST; "today" in IST is still 2026-10-19.
    now = datetime(2026, 10, 19, 3, 0, tzinfo=ZoneInfo("UTC")).astimezone(IST)
    assert day(TODAY, now=now).slots[1].available


def test_capacity_is_reduced_by_bookings_and_fills_up() -> None:
    d = TODAY + timedelta(days=1)
    one_booked = day(d, booked={(time(9, 0), time(11, 0)): 1})
    assert one_booked.slots[0].available and one_booked.slots[0].spots_left == 1
    full = day(d, booked={(time(9, 0), time(11, 0)): 2})
    assert not full.slots[0].available
    assert full.slots[0].reason == av.FULLY_BOOKED and full.slots[0].spots_left == 0


def test_overbooked_slot_never_reports_negative_spots() -> None:
    result = day(TODAY + timedelta(days=1), booked={(time(9, 0), time(11, 0)): 5})
    assert result.slots[0].spots_left == 0


def test_all_slots_full_makes_the_day_unavailable_but_lists_the_reasons() -> None:
    d = TODAY + timedelta(days=1)
    result = day(d, booked={(time(9, 0), time(11, 0)): 2, (time(14, 0), time(16, 0)): 1})
    assert not result.is_open and result.closed_reason == av.UNAVAILABLE
    assert [s.reason for s in result.slots] == [av.FULLY_BOOKED, av.FULLY_BOOKED]


def test_slots_only_appear_on_their_weekdays() -> None:
    saturday = TODAY + timedelta(days=5)
    assert saturday.isoweekday() == 6
    result = day(saturday)
    assert [s.slot_id for s in result.slots] == [SLOT_A.id]


def test_a_day_with_no_operating_slots_is_closed() -> None:
    result = day(TODAY + timedelta(days=5), slots=(SLOT_B,))
    assert not result.is_open and result.closed_reason == av.NO_SLOTS


def test_whole_day_closure_wins_and_exposes_the_note() -> None:
    d = TODAY + timedelta(days=2)
    result = day(d, exceptions=[ExceptionRule(None, False, None, "Closed for Diwali")])
    assert not result.is_open and result.closed_reason == av.CLOSED
    assert result.note == "Closed for Diwali" and result.slots == []


def test_single_slot_closure_keeps_the_other_slots_bookable() -> None:
    d = TODAY + timedelta(days=2)
    result = day(d, exceptions=[ExceptionRule(SLOT_A.id, False, None, "Crew training")])
    closed, open_slot = result.slots
    assert closed.reason == av.CLOSED and closed.spots_left == 0
    assert open_slot.available
    assert result.is_open and result.note == "Crew training"


def test_exception_can_open_a_slot_on_a_weekday_it_does_not_run() -> None:
    saturday = TODAY + timedelta(days=5)
    result = day(saturday, exceptions=[ExceptionRule(SLOT_B.id, True, 3, None)])
    opened = next(s for s in result.slots if s.slot_id == SLOT_B.id)
    assert opened.available and opened.spots_left == 3


def test_exception_capacity_overrides_the_normal_capacity() -> None:
    d = TODAY + timedelta(days=1)
    result = day(
        d,
        exceptions=[ExceptionRule(SLOT_A.id, True, 5, None)],
        booked={(time(9, 0), time(11, 0)): 3},
    )
    assert result.slots[0].spots_left == 2


def test_open_exception_does_not_bypass_the_booking_window_or_the_past() -> None:
    far = TODAY + timedelta(days=40)
    assert (
        day(far, exceptions=[ExceptionRule(SLOT_A.id, True, None, None)]).closed_reason
        == av.OUTSIDE_WINDOW
    )
    past = TODAY - timedelta(days=1)
    assert (
        day(past, exceptions=[ExceptionRule(SLOT_A.id, True, None, None)]).closed_reason
        == av.PAST_DATE
    )


def test_open_exception_still_respects_lead_time_and_capacity() -> None:
    result = day(TODAY, exceptions=[ExceptionRule(SLOT_A.id, True, 1, None)])
    assert result.slots[0].reason == av.LEAD_TIME_PASSED


def test_bookings_for_a_different_slot_do_not_count() -> None:
    d = TODAY + timedelta(days=1)
    result = day(d, booked={(time(9, 0), time(12, 0)): 9})
    assert result.slots[0].spots_left == 2


def test_zero_lead_and_far_window_accept_everything_in_between() -> None:
    d = date(2027, 6, 1)
    now = datetime(2027, 5, 31, 23, 0, tzinfo=IST)
    result = day(d, now=now, window=365, lead=0)
    assert result.is_open
