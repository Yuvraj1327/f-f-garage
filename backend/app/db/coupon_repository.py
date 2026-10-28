"""Coupons in Supabase (service-role client)."""

from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.db.postgrest import run
from app.schemas.coupon import CouponRecord

_DUPLICATE = "A coupon with this code already exists"


class CouponRepository(Protocol):
    def get_by_code(self, code: str) -> CouponRecord | None: ...

    def get(self, coupon_id: UUID) -> CouponRecord | None: ...

    def list_all(self) -> list[CouponRecord]: ...

    def create(self, values: dict[str, Any]) -> CouponRecord: ...

    def update(self, coupon_id: UUID, values: dict[str, Any]) -> CouponRecord | None: ...

    def usage(self, coupon_id: UUID, customer_id: UUID | None = None) -> int:
        """Redemptions on bookings that are not cancelled (all customers, or one)."""
        ...

    def usage_counts(self) -> dict[UUID, int]:
        """The same count for every coupon, for the admin list."""
        ...


class SupabaseCouponRepository:
    TABLE = "coupons"
    REDEMPTIONS = "coupon_redemptions"

    def __init__(self, client: Client) -> None:
        self._client = client

    @staticmethod
    def _record(row: dict[str, Any]) -> CouponRecord:
        return CouponRecord.model_validate(row)

    def get_by_code(self, code: str) -> CouponRecord | None:
        rows = run(self._client.table(self.TABLE).select("*").eq("code", code).limit(1))
        return self._record(rows[0]) if rows else None

    def get(self, coupon_id: UUID) -> CouponRecord | None:
        rows = run(self._client.table(self.TABLE).select("*").eq("id", str(coupon_id)).limit(1))
        return self._record(rows[0]) if rows else None

    def list_all(self) -> list[CouponRecord]:
        rows = run(self._client.table(self.TABLE).select("*").order("created_at", desc=True))
        return [self._record(r) for r in rows]

    def create(self, values: dict[str, Any]) -> CouponRecord:
        rows = run(self._client.table(self.TABLE).insert(values), conflict=_DUPLICATE)
        return self._record(rows[0])

    def update(self, coupon_id: UUID, values: dict[str, Any]) -> CouponRecord | None:
        rows = run(
            self._client.table(self.TABLE).update(values).eq("id", str(coupon_id)),
            conflict=_DUPLICATE,
        )
        return self._record(rows[0]) if rows else None

    def _live(self, coupon_id: UUID | None = None, customer_id: UUID | None = None):
        query = self._client.table(self.REDEMPTIONS).select(
            "coupon_id, customer_id, bookings!inner(status)"
        )
        if coupon_id is not None:
            query = query.eq("coupon_id", str(coupon_id))
        if customer_id is not None:
            query = query.eq("customer_id", str(customer_id))
        return run(query.neq("bookings.status", "cancelled"))

    def usage(self, coupon_id: UUID, customer_id: UUID | None = None) -> int:
        return len(self._live(coupon_id, customer_id))

    def usage_counts(self) -> dict[UUID, int]:
        counts: dict[UUID, int] = {}
        for row in self._live():
            key = UUID(str(row["coupon_id"]))
            counts[key] = counts.get(key, 0) + 1
        return counts
