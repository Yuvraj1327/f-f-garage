"""Admin-only dashboard figures."""

from decimal import Decimal

from fastapi import APIRouter

from app.api.auth import AdminDep
from app.api.deps import DashboardRepositoryDep
from app.domain.enums import BookingStatus
from app.schemas.dashboard import DashboardOut

router = APIRouter(prefix="/admin/dashboard", tags=["Admin: Dashboard"])

_ADMIN = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Caller is not an admin"},
}


@router.get("", response_model=DashboardOut, summary="Dashboard figures", responses=_ADMIN)
def dashboard(_admin: AdminDep, repo: DashboardRepositoryDep) -> DashboardOut:
    """Real counts and money from the database; nothing is estimated."""
    figures = repo.figures()
    by_status = {status: figures.by_status.get(status.value, 0) for status in BookingStatus}
    collected = figures.collected.quantize(Decimal("0.01"))
    refunded = figures.refunded.quantize(Decimal("0.01"))
    return DashboardOut(
        bookings_total=sum(by_status.values()),
        by_status=by_status,
        revenue_collected=collected,
        revenue_refunded=refunded,
        revenue_net=collected - refunded,
        active_drivers=figures.active_drivers,
    )
