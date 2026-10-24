"""Drift checks between the notification kinds in code and migration 11, plus the adapter
queries (stub clients; they cannot prove a real Supabase accepts them, the triggers
themselves are tested on PostgreSQL in supabase/tests/07)."""

import re
import uuid
from pathlib import Path

from app.db.tracking_repository import SupabaseNotificationRepository, SupabaseTrackingRepository
from app.schemas.tracking import NotificationKind, NotificationRecord, TimelineEvent
from tests.test_booking_adapters import Client, CountingQuery

MIGRATION = (
    Path(__file__).parents[2] / "supabase/migrations/20261021100000_tracking_and_notifications.sql"
)
U, B = uuid.uuid4(), uuid.uuid4()
NOW = "2026-10-21T10:00:00+00:00"


def test_notification_kinds_match_the_database_constraint() -> None:
    sql = MIGRATION.read_text()
    block = sql[sql.index("notifications_kind_known") : sql.index("notifications_text_not_blank")]
    assert set(re.findall(r"'([a-z_]+)'", block)) == {k.value for k in NotificationKind}


def test_every_kind_is_written_by_a_trigger() -> None:
    sql = MIGRATION.read_text()
    used = set(re.findall(r"notify_customer\([^,]+,\s*'([a-z_]+)'", sql))
    assert used == {k.value for k in NotificationKind}


def test_rpc_parameter_names_match_the_sql_function() -> None:
    sql = MIGRATION.read_text()
    match = re.search(
        r"create function public\.mark_notifications_read\((.*?)\)\s*returns", sql, re.S
    )
    assert match
    declared = set(re.findall(r"(p_\w+)\s", match.group(1)))
    client = Client([{"updated": 2}])
    assert SupabaseNotificationRepository(client).mark_read(U, [B]) == 2
    name, params = client.rpcs[0]
    assert name == "mark_notifications_read"
    assert set(params) == declared
    assert params == {"p_user_id": str(U), "p_ids": [str(B)]}


def test_mark_all_sends_a_null_id_list() -> None:
    client = Client([{"updated": 5}])
    assert SupabaseNotificationRepository(client).mark_read(U, None) == 5
    assert client.rpcs[0][1]["p_ids"] is None


def test_timeline_reads_one_bookings_events_in_order() -> None:
    client = Client(
        [
            {"status": "pending_payment", "created_at": NOW},
            {"status": "confirmed", "created_at": NOW},
        ]
    )
    events = SupabaseTrackingRepository(client).timeline(B)
    assert [e.status.value for e in events] == ["pending_payment", "confirmed"]
    assert isinstance(events[0], TimelineEvent)
    calls = client.queries[0].calls
    assert client.tables == ["booking_status_events"]
    assert ("eq", ("booking_id", str(B)), {}) in calls
    assert ("order", ("id",), {}) in calls


def test_listing_filters_by_owner_and_newest_first() -> None:
    row = {
        "id": str(uuid.uuid4()),
        "user_id": str(U),
        "booking_id": str(B),
        "kind": "driver_assigned",
        "title": "Driver assigned",
        "body": "x",
        "created_at": NOW,
        "read_at": None,
        "bookings": {"booking_number": 12},
    }
    client = Client([row])
    client.queries = [CountingQuery([row])]
    records, total = SupabaseNotificationRepository(client).list_for_user(
        U, unread_only=True, limit=10, offset=20
    )
    assert total == 7
    assert isinstance(records[0], NotificationRecord)
    assert records[0].booking_number == 12
    calls = client.queries[0].calls
    assert ("eq", ("user_id", str(U)), {}) in calls
    assert ("is_", ("read_at", "null"), {}) in calls
    assert ("order", ("seq",), {"desc": True}) in calls
    assert ("range", (20, 29), {}) in calls


def test_unread_count_asks_only_for_the_users_unread_rows() -> None:
    client = Client([])
    client.queries = [CountingQuery([])]
    assert SupabaseNotificationRepository(client).unread_count(U) == 7
    calls = client.queries[0].calls
    assert ("eq", ("user_id", str(U)), {}) in calls
    assert ("is_", ("read_at", "null"), {}) in calls
