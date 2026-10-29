"""Dashboard figures from the database (one SQL function)."""

from dataclasses import dataclass, field
from decimal import Decimal
from typing import Protocol

from supabase import Client

from app.core.errors import ServiceUnavailableError
from app.db.postgrest import run


@dataclass(frozen=True)
class DashboardFigures:
    by_status: dict[str, int] = field(default_factory=dict)
    collected: Decimal = Decimal("0")
    refunded: Decimal = Decimal("0")
    active_drivers: int = 0


class DashboardRepository(Protocol):
    def figures(self) -> DashboardFigures: ...


class SupabaseDashboardRepository:
    def __init__(self, client: Client) -> None:
        self._client = client

    def figures(self) -> DashboardFigures:
        rows = run(self._client.rpc("admin_dashboard_summary", {}))
        if not rows:
            raise ServiceUnavailableError("Database returned no dashboard figures")
        row = rows[0]
        return DashboardFigures(
            by_status={str(k): int(v) for k, v in (row.get("by_status") or {}).items()},
            collected=Decimal(str(row.get("collected") or 0)),
            refunded=Decimal(str(row.get("refunded") or 0)),
            active_drivers=int(row.get("active_drivers") or 0),
        )
