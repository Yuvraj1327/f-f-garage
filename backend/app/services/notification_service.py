"""A customer's in-app notifications.

The rows are written by database triggers when a booking or payment really changes, so
this service only reads them and marks them read. Every call is scoped to the signed-in
customer's own id; there is no way to name another user.
"""

from uuid import UUID

from app.db.tracking_repository import NotificationRepository
from app.domain import booking as rules
from app.schemas.profile import ProfileOut
from app.schemas.tracking import (
    MarkReadResult,
    NotificationOut,
    NotificationPage,
    NotificationRecord,
    UnreadCount,
)


def notification_view(record: NotificationRecord) -> NotificationOut:
    return NotificationOut(
        id=record.id,
        booking_id=record.booking_id,
        booking_code=rules.booking_code(record.booking_number)
        if record.booking_number is not None
        else None,
        kind=record.kind,
        title=record.title,
        body=record.body,
        created_at=record.created_at,
        is_read=record.read_at is not None,
    )


class NotificationService:
    def __init__(self, notifications: NotificationRepository) -> None:
        self._notifications = notifications

    def list_page(
        self, customer: ProfileOut, *, unread_only: bool, limit: int, offset: int
    ) -> NotificationPage:
        records, total = self._notifications.list_for_user(
            customer.id, unread_only=unread_only, limit=limit, offset=offset
        )
        unread = total if unread_only else self._notifications.unread_count(customer.id)
        return NotificationPage(
            items=[notification_view(r) for r in records],
            total=total,
            unread=unread,
            limit=limit,
            offset=offset,
        )

    def unread_count(self, customer: ProfileOut) -> UnreadCount:
        return UnreadCount(unread=self._notifications.unread_count(customer.id))

    def mark_read(self, customer: ProfileOut, ids: list[UUID] | None) -> MarkReadResult:
        """Ids that are not the customer's own are ignored, exactly like ids that do not exist."""
        updated = self._notifications.mark_read(customer.id, ids)
        return MarkReadResult(updated=updated, unread=self._notifications.unread_count(customer.id))
