"""Extra charge requests (parts or repairs found during the visit) in Supabase."""

from collections import defaultdict
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.core.errors import ServiceUnavailableError
from app.db.postgrest import run
from app.schemas.billing import ExtraRequestRecord, ExtrasSummary

PROPOSED = "proposed"


class ExtraRequestRepository(Protocol):
    def create(self, values: dict[str, Any]) -> ExtraRequestRecord: ...

    def get(self, extra_id: UUID) -> ExtraRequestRecord | None: ...

    def list_for_booking(self, booking_id: UUID) -> list[ExtraRequestRecord]:
        """Oldest first."""
        ...

    def answer(self, extra_id: UUID, status: str) -> ExtraRequestRecord | None:
        """proposed -> approved / declined / withdrawn. None when it was no longer proposed
        (someone else answered first)."""
        ...

    def summaries(self, booking_ids: list[UUID]) -> dict[UUID, ExtrasSummary]: ...


class SupabaseExtraRequestRepository:
    TABLE = "booking_extra_requests"

    def __init__(self, client: Client) -> None:
        self._client = client

    @staticmethod
    def _record(row: dict[str, Any]) -> ExtraRequestRecord:
        return ExtraRequestRecord.model_validate(row)

    def create(self, values: dict[str, Any]) -> ExtraRequestRecord:
        rows = run(self._client.table(self.TABLE).insert(values))
        if not rows:
            raise ServiceUnavailableError("Database returned no extra charge request")
        return self._record(rows[0])

    def get(self, extra_id: UUID) -> ExtraRequestRecord | None:
        rows = run(self._client.table(self.TABLE).select("*").eq("id", str(extra_id)).limit(1))
        return self._record(rows[0]) if rows else None

    def list_for_booking(self, booking_id: UUID) -> list[ExtraRequestRecord]:
        rows = run(
            self._client.table(self.TABLE)
            .select("*")
            .eq("booking_id", str(booking_id))
            .order("created_at")
        )
        return [self._record(r) for r in rows]

    def answer(self, extra_id: UUID, status: str) -> ExtraRequestRecord | None:
        values: dict[str, Any] = {"status": status}
        if status in ("approved", "declined"):
            values["decided_at"] = datetime.now(UTC).isoformat()
        rows = run(
            self._client.table(self.TABLE)
            .update(values)
            .eq("id", str(extra_id))
            .eq("status", PROPOSED)
        )
        return self._record(rows[0]) if rows else None

    def summaries(self, booking_ids: list[UUID]) -> dict[UUID, ExtrasSummary]:
        if not booking_ids:
            return {}
        rows = run(
            self._client.table(self.TABLE)
            .select("booking_id, amount, status")
            .in_("booking_id", [str(i) for i in booking_ids])
            .in_("status", ["approved", PROPOSED])
        )
        totals: dict[UUID, Decimal] = defaultdict(lambda: Decimal("0"))
        pending: dict[UUID, int] = defaultdict(int)
        for row in rows:
            booking_id = UUID(str(row["booking_id"]))
            if row["status"] == "approved":
                totals[booking_id] += Decimal(str(row["amount"]))
            else:
                pending[booking_id] += 1
        return {
            i: ExtrasSummary(approved_total=totals[i], pending_count=pending[i])
            for i in {*totals, *pending}
        }
