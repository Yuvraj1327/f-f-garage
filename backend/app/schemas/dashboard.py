"""The admin dashboard's headline figures."""

from decimal import Decimal

from pydantic import BaseModel

from app.domain.enums import BookingStatus


class DashboardOut(BaseModel):
    bookings_total: int
    # Every status is present (0 when there are none), so the app can draw a full breakdown.
    by_status: dict[BookingStatus, int]
    # Money actually taken through the gateway, refunds an admin recorded, and the difference.
    revenue_collected: Decimal
    revenue_refunded: Decimal
    revenue_net: Decimal
    active_drivers: int
