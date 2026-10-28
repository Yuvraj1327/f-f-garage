"""Refund records in Supabase. An admin refunds in the payment gateway's dashboard and
records it here; nothing in this application moves money back."""

from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.core.errors import ServiceUnavailableError
from app.db.postgrest import run
from app.schemas.billing import RefundRecord


@dataclass(frozen=True)
class RefundOutcome:
    result: str  # recorded | payment_not_found | payment_not_successful | exceeds_payment
    refund_id: UUID | None


class RefundRepository(Protocol):
    def record(
        self, payment_id: UUID, amount: Decimal, note: str | None, admin_id: UUID
    ) -> RefundOutcome: ...

    def list_for_booking(self, booking_id: UUID) -> list[RefundRecord]: ...

    def list_for_payment(self, payment_id: UUID) -> list[RefundRecord]: ...

    def get(self, refund_id: UUID) -> RefundRecord | None: ...


class SupabaseRefundRepository:
    TABLE = "payment_refunds"

    def __init__(self, client: Client) -> None:
        self._client = client

    @staticmethod
    def _record(row: dict[str, Any]) -> RefundRecord:
        return RefundRecord.model_validate(row)

    def record(
        self, payment_id: UUID, amount: Decimal, note: str | None, admin_id: UUID
    ) -> RefundOutcome:
        rows = run(
            self._client.rpc(
                "record_payment_refund",
                {
                    "p_payment_id": str(payment_id),
                    "p_amount": str(amount),
                    "p_note": note,
                    "p_admin": str(admin_id),
                },
            )
        )
        if not rows:
            raise ServiceUnavailableError("Database returned no refund result")
        row = rows[0]
        return RefundOutcome(
            result=row["result"],
            refund_id=UUID(row["refund_id"]) if row.get("refund_id") else None,
        )

    def get(self, refund_id: UUID) -> RefundRecord | None:
        rows = run(self._client.table(self.TABLE).select("*").eq("id", str(refund_id)).limit(1))
        return self._record(rows[0]) if rows else None

    def list_for_booking(self, booking_id: UUID) -> list[RefundRecord]:
        rows = run(
            self._client.table(self.TABLE)
            .select("*")
            .eq("booking_id", str(booking_id))
            .order("created_at")
        )
        return [self._record(r) for r in rows]

    def list_for_payment(self, payment_id: UUID) -> list[RefundRecord]:
        rows = run(
            self._client.table(self.TABLE)
            .select("*")
            .eq("payment_id", str(payment_id))
            .order("created_at")
        )
        return [self._record(r) for r in rows]
