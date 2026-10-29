"""The admin dashboard endpoint and its database adapter."""

from decimal import Decimal

import pytest

from app.core.errors import ServiceUnavailableError
from app.db.dashboard_repository import DashboardFigures, SupabaseDashboardRepository
from tests.phase3_support import Ctx, ctx  # noqa: F401
from tests.test_supabase_adapters import StubClient

URL = "/api/v1/admin/dashboard"


class RpcClient(StubClient):
    def rpc(self, name, params):
        self.tables.append(f"rpc:{name}")
        self.params = params
        return self.query


def test_requires_sign_in(ctx: Ctx):  # noqa: F811
    assert ctx.client.get(URL).status_code == 401


@pytest.mark.parametrize("who", ["as_customer", "as_driver"])
def test_only_admins_can_read(ctx: Ctx, who):  # noqa: F811
    assert ctx.client.get(URL, headers=getattr(ctx, who)).status_code == 403


def test_an_empty_garage_has_zeros_for_every_status(ctx: Ctx):  # noqa: F811
    body = ctx.client.get(URL, headers=ctx.as_admin).json()
    assert body["bookings_total"] == 0
    assert set(body["by_status"]) == {
        "pending_payment",
        "confirmed",
        "assigned",
        "on_the_way",
        "in_progress",
        "completed",
        "cancelled",
    }
    assert set(body["by_status"].values()) == {0}
    assert Decimal(body["revenue_net"]) == 0
    assert body["active_drivers"] == 0


def test_figures_are_totalled_and_revenue_is_net_of_refunds(ctx: Ctx):  # noqa: F811
    ctx.dashboard.value = DashboardFigures(
        by_status={"completed": 7, "confirmed": 2, "cancelled": 1, "unknown_future": 9},
        collected=Decimal("12500.5"),
        refunded=Decimal("500"),
        active_drivers=3,
    )
    body = ctx.client.get(URL, headers=ctx.as_admin).json()
    assert body["bookings_total"] == 10
    assert body["by_status"]["completed"] == 7
    assert body["by_status"]["pending_payment"] == 0
    assert Decimal(body["revenue_collected"]) == Decimal("12500.50")
    assert Decimal(body["revenue_refunded"]) == Decimal("500.00")
    assert Decimal(body["revenue_net"]) == Decimal("12000.50")
    assert body["active_drivers"] == 3


def test_adapter_calls_the_sql_function_and_parses_the_row() -> None:
    client = RpcClient(
        [
            {
                "by_status": {"completed": 4},
                "collected": "100.00",
                "refunded": 0,
                "active_drivers": 2,
            }
        ]
    )
    figures = SupabaseDashboardRepository(client).figures()
    assert client.tables == ["rpc:admin_dashboard_summary"]
    assert figures == DashboardFigures({"completed": 4}, Decimal("100.00"), Decimal("0"), 2)


def test_adapter_fails_clearly_without_a_row() -> None:
    with pytest.raises(ServiceUnavailableError):
        SupabaseDashboardRepository(RpcClient([])).figures()
