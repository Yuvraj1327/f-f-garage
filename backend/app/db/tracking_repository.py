"""Booking status history and customer notifications (migration 11).

Both tables are written only by database triggers, so nothing here inserts or updates them
directly; the one write, "mark read", is a SQL function that only touches the caller's rows.
"""

from typing import Protocol
from uuid import UUID

from supabase import Client

from app.db.postgrest import run, run_counted
from app.schemas.tracking import NotificationRecord, TimelineEvent

EVENTS = "booking_status_events"
NOTIFICATIONS = "notifications"


class TrackingRepository(Protocol):
    def timeline(self, booking_id: UUID) -> list[TimelineEvent]:
        """The booking's status history, oldest first."""
        ...


class NotificationRepository(Protocol):
    def list_for_user(
        self, user_id: UUID, *, unread_only: bool, limit: int, offset: int
    ) -> tuple[list[NotificationRecord], int]:
        """A page of the user's notifications, newest first, and the total."""
        ...

    def unread_count(self, user_id: UUID) -> int: ...

    def mark_read(self, user_id: UUID, ids: list[UUID] | None) -> int:
        """Marks the user's own notifications read (all when `ids` is None); returns how many."""
        ...


class SupabaseTrackingRepository:
    def __init__(self, client: Client) -> None:
        self._client = client

    def timeline(self, booking_id: UUID) -> list[TimelineEvent]:
        rows = run(
            self._client.table(EVENTS)
            .select("status, created_at")
            .eq("booking_id", str(booking_id))
            .order("id")
        )
        return [TimelineEvent.model_validate(r) for r in rows]


class SupabaseNotificationRepository:
    def __init__(self, client: Client) -> None:
        self._client = client

    def list_for_user(
        self, user_id: UUID, *, unread_only: bool, limit: int, offset: int
    ) -> tuple[list[NotificationRecord], int]:
        q = (
            self._client.table(NOTIFICATIONS)
            .select("*, bookings(booking_number)", count="exact")
            .eq("user_id", str(user_id))
        )
        if unread_only:
            q = q.is_("read_at", "null")
        q = q.order("seq", desc=True).range(offset, offset + limit - 1)
        rows, total = run_counted(q)
        return [NotificationRecord.model_validate(r) for r in rows], total

    def unread_count(self, user_id: UUID) -> int:
        _, total = run_counted(
            self._client.table(NOTIFICATIONS)
            .select("id", count="exact")
            .eq("user_id", str(user_id))
            .is_("read_at", "null")
            .limit(1)
        )
        return total

    def mark_read(self, user_id: UUID, ids: list[UUID] | None) -> int:
        rows = run(
            self._client.rpc(
                "mark_notifications_read",
                {
                    "p_user_id": str(user_id),
                    "p_ids": None if ids is None else [str(i) for i in ids],
                },
            )
        )
        return int(rows[0]["updated"]) if rows else 0
