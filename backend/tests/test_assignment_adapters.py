"""What the assignment repository asks Supabase for (stub clients). These cannot prove a
real Supabase accepts the queries; the SQL functions themselves are tested on PostgreSQL."""

import re
import uuid
from pathlib import Path

import pytest

from app.core.errors import ServiceUnavailableError
from app.db.assignment_repository import SupabaseAssignmentRepository
from app.db.booking_repository import SupabaseBookingRepository
from app.db.profile_repository import SupabaseProfileRepository
from app.domain.enums import BookingStatus
from tests.test_booking_adapters import Client, api_error, booking_row

A, B, C = (uuid.uuid4() for _ in range(3))
NOW = "2026-10-20T10:00:00+00:00"


def assignment_row(**over):
    return {
        "id": str(uuid.uuid4()),
        "booking_id": str(A),
        "driver_id": str(B),
        "assigned_by": str(C),
        "is_active": True,
        "assigned_at": NOW,
        "unassigned_at": None,
        **over,
    }


# ---- The SQL functions' parameter names ---------------------------------------------------


def _declared(function: str) -> set[str]:
    migrations = Path(__file__).resolve().parents[2] / "supabase" / "migrations"
    sql = "".join(p.read_text() for p in sorted(migrations.glob("*.sql")))
    match = re.search(rf"create function public\.{function}\((.*?)\)\s*returns", sql, re.S)
    assert match, f"{function} not found in the migrations"
    return set(re.findall(r"^\s*(p_\w+)\s", match.group(1), re.M))


def test_rpc_parameter_names_match_the_sql_functions() -> None:
    client = Client([{"result": "assigned"}])
    repo = SupabaseAssignmentRepository(client)
    repo.assign(A, B, C)
    repo.unassign(A, C)
    repo.driver_update_status(A, B, BookingStatus.ON_THE_WAY)
    client = Client([{"booking_id": str(A), "total": 1}])
    SupabaseAssignmentRepository(client).driver_booking_ids(B, "open", 10, 0)
    for name, params in client.rpcs:
        assert set(params) == _declared(name), name


def test_the_three_change_functions_are_called_by_name() -> None:
    client = Client([{"result": "assigned"}])
    repo = SupabaseAssignmentRepository(client)
    repo.assign(A, B, C)
    repo.unassign(A, C)
    repo.driver_update_status(A, B, BookingStatus.COMPLETED)
    assert [n for n, _ in client.rpcs] == [
        "assign_driver",
        "unassign_driver",
        "driver_update_status",
    ]
    assert client.rpcs[0][1] == {
        "p_booking_id": str(A),
        "p_driver_id": str(B),
        "p_admin_id": str(C),
    }
    assert client.rpcs[2][1]["p_status"] == "completed"


# ---- Results -----------------------------------------------------------------------------


def test_a_result_row_is_parsed() -> None:
    row = {"result": "assigned", "assignment_id": str(A), "booking_status": "assigned"}
    outcome = SupabaseAssignmentRepository(Client([row])).assign(A, B, C)
    assert outcome.result == "assigned"
    assert outcome.booking_status == BookingStatus.ASSIGNED
    assert outcome.assignment_id == A


def test_an_empty_result_is_unavailability() -> None:
    with pytest.raises(ServiceUnavailableError):
        SupabaseAssignmentRepository(Client([])).assign(A, B, C)


def test_a_database_failure_is_unavailability() -> None:
    with pytest.raises(ServiceUnavailableError):
        SupabaseAssignmentRepository(Client(api_error("XX000"))).unassign(A, C)


# ---- Reads -------------------------------------------------------------------------------


def test_active_assignments_are_loaded_in_one_query() -> None:
    client = Client([assignment_row(), assignment_row(booking_id=str(B))])
    found = SupabaseAssignmentRepository(client).active_for_bookings([A, B])
    assert set(found) == {A, B}
    calls = client.queries[0].calls
    assert ("in_", ("booking_id", [str(A), str(B)]), {}) in calls
    assert ("eq", ("is_active", True), {}) in calls
    assert client.tables == ["driver_assignments"]


def test_no_ids_means_no_query() -> None:
    client = Client([])
    assert SupabaseAssignmentRepository(client).active_for_bookings([]) == {}
    assert client.tables == []


def test_is_assigned_checks_the_booking_driver_and_active_flag() -> None:
    client = Client([{"id": str(uuid.uuid4())}])
    assert SupabaseAssignmentRepository(client).is_assigned(A, B) is True
    calls = client.queries[0].calls
    assert ("eq", ("booking_id", str(A)), {}) in calls
    assert ("eq", ("driver_id", str(B)), {}) in calls
    assert ("eq", ("is_active", True), {}) in calls
    assert SupabaseAssignmentRepository(Client([])).is_assigned(A, B) is False


def test_history_is_newest_first() -> None:
    client = Client([assignment_row(is_active=False, unassigned_at=NOW)])
    records = SupabaseAssignmentRepository(client).history(A)
    assert len(records) == 1 and records[0].is_active is False
    assert ("order", ("assigned_at",), {"desc": True}) in client.queries[0].calls


def test_a_page_of_driver_bookings_and_its_total() -> None:
    rows = [{"booking_id": str(A), "total": 5}, {"booking_id": str(B), "total": 5}]
    ids, total = SupabaseAssignmentRepository(Client(rows)).driver_booking_ids(C, "history", 2, 4)
    assert ids == [A, B]
    assert total == 5
    empty = SupabaseAssignmentRepository(Client([])).driver_booking_ids(C, "open", 2, 0)
    assert empty == ([], 0)


def test_workload_counts() -> None:
    rows = [{"driver_id": str(A), "open_bookings": 3}]
    assert SupabaseAssignmentRepository(Client(rows)).open_counts() == {A: 3}


def test_get_many_bookings_keeps_the_requested_order() -> None:
    first, second = booking_row(), booking_row()
    client = Client([second, first])  # the database may answer in any order
    ids = [uuid.UUID(first["id"]), uuid.UUID(second["id"])]
    records = SupabaseBookingRepository(client).get_many(ids)
    assert [r.id for r in records] == ids
    assert ("in_", ("id", [str(i) for i in ids]), {}) in client.queries[0].calls
    assert SupabaseBookingRepository(Client([])).get_many([]) == []


def test_get_many_profiles() -> None:
    from tests.fakes import make_profile

    profile = make_profile()
    row = profile.model_dump(mode="json")
    client = Client([row])
    assert SupabaseProfileRepository(client).get_many([str(profile.id)])[0].id == profile.id
    assert ("in_", ("id", [str(profile.id)]), {}) in client.queries[0].calls
    assert SupabaseProfileRepository(Client([])).get_many([]) == []
