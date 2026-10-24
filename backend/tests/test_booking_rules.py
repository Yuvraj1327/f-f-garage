"""The pure booking rules, and a drift check against the SQL transition function."""

import re
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

from app.domain import booking as rules
from app.domain.enums import BookingStatus as S

IST = ZoneInfo("Asia/Kolkata")
VISIT = datetime(2026, 10, 20, 10, 0, tzinfo=IST)

MIGRATION = Path(__file__).parents[2] / "supabase/migrations/20261018100000_booking_workflow.sql"


def test_sql_and_python_agree_on_allowed_transitions() -> None:
    sql = MIGRATION.read_text()
    body = sql.split("booking_status_transition_allowed", 1)[1].split("$$;", 1)[0]
    pairs = set(re.findall(r"\('([a-z_]+)', '([a-z_]+)'\)", body))
    expected = {(a.value, b.value) for a, targets in rules.TRANSITIONS.items() for b in targets}
    assert pairs == expected


def test_every_status_has_a_transition_entry() -> None:
    assert set(rules.TRANSITIONS) == set(S)


def test_final_statuses_go_nowhere() -> None:
    for status in rules.FINAL_STATUSES:
        assert rules.TRANSITIONS[status] == frozenset()


@pytest.mark.parametrize(
    ("current", "target", "ok"),
    [
        (S.PENDING_PAYMENT, S.CONFIRMED, True),
        (S.PENDING_PAYMENT, S.COMPLETED, False),
        (S.CONFIRMED, S.PENDING_PAYMENT, False),
        (S.CONFIRMED, S.ASSIGNED, True),
        (S.IN_PROGRESS, S.COMPLETED, True),
        (S.COMPLETED, S.CANCELLED, False),
        (S.CANCELLED, S.CONFIRMED, False),
    ],
)
def test_can_transition(current, target, ok) -> None:
    assert rules.can_transition(current, target) is ok


def test_admin_next_statuses_only_offers_cancel() -> None:
    """Confirming belongs to the verified-payment path, not to a manual status change."""
    assert rules.admin_next_statuses(S.PENDING_PAYMENT) == [S.CANCELLED]
    assert rules.admin_next_statuses(S.CONFIRMED) == [S.CANCELLED]
    assert rules.admin_next_statuses(S.ASSIGNED) == [S.CANCELLED]
    assert rules.admin_next_statuses(S.COMPLETED) == []
    assert rules.admin_next_statuses(S.CANCELLED) == []


def test_booking_code() -> None:
    assert rules.booking_code(7) == "FF-000007"
    assert rules.booking_code(1234567) == "FF-1234567"


def hours_before(h: float) -> datetime:
    from datetime import timedelta

    return VISIT - timedelta(hours=h)


def test_pending_payment_can_always_be_cancelled() -> None:
    assert rules.customer_cancel_block(S.PENDING_PAYMENT, VISIT, hours_before(0.5), 4) is None


def test_confirmed_cancel_respects_the_cutoff() -> None:
    assert rules.customer_cancel_block(S.CONFIRMED, VISIT, hours_before(5), 4) is None
    assert rules.customer_cancel_block(S.CONFIRMED, VISIT, hours_before(4), 4) is None
    assert rules.customer_cancel_block(S.CONFIRMED, VISIT, hours_before(3.9), 4) is not None
    assert rules.customer_cancel_block(S.ASSIGNED, VISIT, hours_before(1), 4) is not None


def test_cutoff_zero_allows_until_the_slot_starts() -> None:
    assert rules.customer_cancel_block(S.CONFIRMED, VISIT, hours_before(0.1), 0) is None
    assert rules.customer_cancel_block(S.CONFIRMED, VISIT, hours_before(-0.1), 0) is not None


@pytest.mark.parametrize("status", [S.ON_THE_WAY, S.IN_PROGRESS, S.COMPLETED, S.CANCELLED])
def test_late_or_final_bookings_cannot_be_cancelled_online(status) -> None:
    assert rules.customer_cancel_block(status, VISIT, hours_before(48), 4) is not None


def test_editing_only_before_assignment_and_before_the_cutoff() -> None:
    assert rules.customer_edit_block(S.PENDING_PAYMENT, VISIT, hours_before(10), 4) is None
    assert rules.customer_edit_block(S.CONFIRMED, VISIT, hours_before(10), 4) is None
    assert rules.customer_edit_block(S.CONFIRMED, VISIT, hours_before(2), 4) is not None
    for status in (S.ASSIGNED, S.ON_THE_WAY, S.IN_PROGRESS, S.COMPLETED, S.CANCELLED):
        assert rules.customer_edit_block(status, VISIT, hours_before(48), 4) is not None
