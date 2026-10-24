"""The pure driver rules, and drift checks against the SQL functions of migration 10."""

import re
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.domain import booking as rules
from app.domain.enums import BookingStatus as S
from app.schemas.assignment import DriverStatusUpdate

MIGRATION = (
    Path(__file__).parents[2] / "supabase/migrations/20261020100000_driver_assignment_workflow.sql"
)


def _function(name: str) -> str:
    sql = MIGRATION.read_text()
    start = sql.index(f"create function public.{name}(")
    return sql[start : sql.index("$$;", sql.index("as $$", start))]


def test_sql_and_python_agree_on_the_driver_steps() -> None:
    body = _function("driver_update_status")
    pairs = set(re.findall(r"v_booking\.status = '([a-z_]+)'\s+and p_status = '([a-z_]+)'", body))
    assert pairs == {(a.value, b.value) for a, b in rules.DRIVER_STEPS.items()}


def test_sql_and_python_agree_on_what_an_admin_may_assign() -> None:
    body = _function("assign_driver")
    listed = re.search(r"v_booking\.status not in \(([^)]*)\)", body)
    assert listed
    assert set(re.findall(r"'([a-z_]+)'", listed.group(1))) == {
        s.value for s in rules.ADMIN_ASSIGNABLE_STATUSES
    }


def test_sql_and_python_agree_on_a_drivers_open_statuses() -> None:
    expected = {s.value for s in rules.DRIVER_OPEN_STATUSES}
    for name in ("driver_booking_ids", "driver_workload"):
        body = _function(name)
        found = re.search(r"status in \('assigned'[^)]*\)", body)
        assert found, name
        assert set(re.findall(r"'([a-z_]+)'", found.group(0))) == expected, name


def test_driver_steps_are_a_single_forward_chain() -> None:
    assert rules.DRIVER_STEPS == {
        S.ASSIGNED: S.ON_THE_WAY,
        S.ON_THE_WAY: S.IN_PROGRESS,
        S.IN_PROGRESS: S.COMPLETED,
    }
    # every driver step is also a legal booking transition
    for current, target in rules.DRIVER_STEPS.items():
        assert rules.can_transition(current, target)


def test_a_driver_can_never_cancel_confirm_or_reopen() -> None:
    assert S.CANCELLED not in rules.DRIVER_TARGETS
    assert S.CONFIRMED not in rules.DRIVER_TARGETS
    assert S.PENDING_PAYMENT not in rules.DRIVER_TARGETS
    assert S.ASSIGNED not in rules.DRIVER_TARGETS


@pytest.mark.parametrize(
    ("current", "expected"),
    [
        (S.ASSIGNED, S.ON_THE_WAY),
        (S.ON_THE_WAY, S.IN_PROGRESS),
        (S.IN_PROGRESS, S.COMPLETED),
        (S.COMPLETED, None),
        (S.CANCELLED, None),
        (S.CONFIRMED, None),
        (S.PENDING_PAYMENT, None),
    ],
)
def test_the_next_driver_step(current, expected) -> None:
    assert rules.driver_next_status(current) == expected


def test_only_paid_and_not_started_work_can_be_given_to_another_driver() -> None:
    assert rules.ADMIN_ASSIGNABLE_STATUSES == {S.CONFIRMED, S.ASSIGNED, S.ON_THE_WAY}
    assert S.PENDING_PAYMENT not in rules.ADMIN_ASSIGNABLE_STATUSES
    assert S.IN_PROGRESS not in rules.ADMIN_ASSIGNABLE_STATUSES


@pytest.mark.parametrize("value", ["on_the_way", "in_progress", "completed"])
def test_the_status_request_accepts_the_driver_steps(value) -> None:
    assert DriverStatusUpdate(status=value).status.value == value


@pytest.mark.parametrize("value", ["cancelled", "confirmed", "assigned", "pending_payment"])
def test_the_status_request_refuses_everything_else(value) -> None:
    with pytest.raises(ValidationError):
        DriverStatusUpdate(status=value)
