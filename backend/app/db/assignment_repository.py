"""Driver assignments. Every change goes through a SQL function (migration 10) that locks
the booking and checks the rules in one transaction; nothing here writes the tables."""

from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.core.errors import ServiceUnavailableError
from app.db.postgrest import run
from app.domain.enums import BookingStatus
from app.schemas.assignment import AssignmentRecord, AssignmentResult

TABLE = "driver_assignments"


class AssignmentRepository(Protocol):
    def assign(self, booking_id: UUID, driver_id: UUID, admin_id: UUID) -> AssignmentResult: ...

    def unassign(self, booking_id: UUID, admin_id: UUID) -> AssignmentResult: ...

    def driver_update_status(
        self, booking_id: UUID, driver_id: UUID, status: BookingStatus
    ) -> AssignmentResult: ...

    def active_for_bookings(self, booking_ids: list[UUID]) -> dict[UUID, AssignmentRecord]:
        """The current assignment of each booking that has one."""
        ...

    def is_assigned(self, booking_id: UUID, driver_id: UUID) -> bool:
        """Does this driver hold the booking's current assignment?"""
        ...

    def history(self, booking_id: UUID) -> list[AssignmentRecord]:
        """Every assignment the booking has had, newest first."""
        ...

    def driver_booking_ids(
        self, driver_id: UUID, scope: str, limit: int, offset: int
    ) -> tuple[list[UUID], int]:
        """A page of the driver's booking ids for `scope` ('open' or 'history') and the total."""
        ...

    def open_counts(self) -> dict[UUID, int]:
        """Open bookings per driver (drivers with none are absent)."""
        ...


class SupabaseAssignmentRepository:
    def __init__(self, client: Client) -> None:
        self._client = client

    def _call(self, function: str, params: dict[str, Any]) -> AssignmentResult:
        rows = run(self._client.rpc(function, params))
        if not rows:
            raise ServiceUnavailableError("Database returned no assignment result")
        row = rows[0]
        return AssignmentResult(
            result=row["result"],
            booking_status=row.get("booking_status"),
            assignment_id=row.get("assignment_id"),
        )

    def assign(self, booking_id: UUID, driver_id: UUID, admin_id: UUID) -> AssignmentResult:
        return self._call(
            "assign_driver",
            {
                "p_booking_id": str(booking_id),
                "p_driver_id": str(driver_id),
                "p_admin_id": str(admin_id),
            },
        )

    def unassign(self, booking_id: UUID, admin_id: UUID) -> AssignmentResult:
        return self._call(
            "unassign_driver", {"p_booking_id": str(booking_id), "p_admin_id": str(admin_id)}
        )

    def driver_update_status(
        self, booking_id: UUID, driver_id: UUID, status: BookingStatus
    ) -> AssignmentResult:
        return self._call(
            "driver_update_status",
            {
                "p_booking_id": str(booking_id),
                "p_driver_id": str(driver_id),
                "p_status": status.value,
            },
        )

    def active_for_bookings(self, booking_ids: list[UUID]) -> dict[UUID, AssignmentRecord]:
        if not booking_ids:
            return {}
        rows = run(
            self._client.table(TABLE)
            .select("*")
            .in_("booking_id", [str(i) for i in booking_ids])
            .eq("is_active", True)
        )
        records = [AssignmentRecord.model_validate(r) for r in rows]
        return {r.booking_id: r for r in records}

    def is_assigned(self, booking_id: UUID, driver_id: UUID) -> bool:
        rows = run(
            self._client.table(TABLE)
            .select("id")
            .eq("booking_id", str(booking_id))
            .eq("driver_id", str(driver_id))
            .eq("is_active", True)
            .limit(1)
        )
        return bool(rows)

    def history(self, booking_id: UUID) -> list[AssignmentRecord]:
        rows = run(
            self._client.table(TABLE)
            .select("*")
            .eq("booking_id", str(booking_id))
            .order("assigned_at", desc=True)
        )
        return [AssignmentRecord.model_validate(r) for r in rows]

    def driver_booking_ids(
        self, driver_id: UUID, scope: str, limit: int, offset: int
    ) -> tuple[list[UUID], int]:
        rows = run(
            self._client.rpc(
                "driver_booking_ids",
                {
                    "p_driver_id": str(driver_id),
                    "p_scope": scope,
                    "p_limit": limit,
                    "p_offset": offset,
                },
            )
        )
        total = int(rows[0]["total"]) if rows else 0
        return [UUID(r["booking_id"]) for r in rows], total

    def open_counts(self) -> dict[UUID, int]:
        rows = run(self._client.rpc("driver_workload", {}))
        return {UUID(r["driver_id"]): int(r["open_bookings"]) for r in rows}
