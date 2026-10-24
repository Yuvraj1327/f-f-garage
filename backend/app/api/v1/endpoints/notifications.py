"""The signed-in customer's in-app notifications. Customers only; each customer sees
only their own."""

from typing import Annotated

from fastapi import APIRouter, Query

from app.api.auth import CustomerDep
from app.api.deps import NotificationServiceDep
from app.schemas.tracking import MarkReadRequest, MarkReadResult, NotificationPage, UnreadCount

router = APIRouter(prefix="/notifications", tags=["Notifications"])

_AUTH = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Only customers have notifications"},
}


@router.get("", response_model=NotificationPage, summary="My notifications", responses=_AUTH)
def list_notifications(
    customer: CustomerDep,
    service: NotificationServiceDep,
    unread_only: bool = False,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0, le=100_000)] = 0,
) -> NotificationPage:
    """Newest first. `unread` is the number of unread notifications overall."""
    return service.list_page(customer, unread_only=unread_only, limit=limit, offset=offset)


@router.get(
    "/unread-count", response_model=UnreadCount, summary="How many are unread", responses=_AUTH
)
def unread_count(customer: CustomerDep, service: NotificationServiceDep) -> UnreadCount:
    return service.unread_count(customer)


@router.post(
    "/read",
    response_model=MarkReadResult,
    summary="Mark notifications as read",
    responses=_AUTH,
)
def mark_read(
    payload: MarkReadRequest, customer: CustomerDep, service: NotificationServiceDep
) -> MarkReadResult:
    """Send `ids` to mark those, or omit it to mark all. Safe to repeat."""
    return service.mark_read(customer, payload.ids)
