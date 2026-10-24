"""Time slots, availability exceptions and booked-slot counts in Supabase."""

from datetime import date, time
from typing import Any, Protocol
from uuid import UUID

from supabase import Client

from app.core.errors import ServiceUnavailableError
from app.db.postgrest import run
from app.schemas.availability import ExceptionOut, TimeSlotOut

_OVERLAP = "This time slot overlaps another active slot on the same day"
_DUPLICATE_EXCEPTION = "There is already an entry for this date and slot"


class AvailabilityRepository(Protocol):
    def list_slots(self, *, active_only: bool = False) -> list[TimeSlotOut]: ...

    def get_slot(self, slot_id: UUID) -> TimeSlotOut | None: ...

    def create_slot(self, values: dict[str, Any]) -> TimeSlotOut: ...

    def update_slot(self, slot_id: UUID, values: dict[str, Any]) -> TimeSlotOut | None: ...

    def delete_slot(self, slot_id: UUID) -> bool: ...

    def list_exceptions(self, start: date, end: date) -> list[ExceptionOut]: ...

    def get_exception(self, exception_id: UUID) -> ExceptionOut | None: ...

    def create_exception(self, values: dict[str, Any]) -> ExceptionOut: ...

    def update_exception(
        self, exception_id: UUID, values: dict[str, Any]
    ) -> ExceptionOut | None: ...

    def delete_exception(self, exception_id: UUID) -> bool: ...

    def booked_counts(self, start: date, end: date) -> dict[tuple[date, time, time], int]:
        """Non-cancelled bookings per (date, slot start, slot end)."""
        ...


class SupabaseAvailabilityRepository:
    SLOTS = "time_slots"
    EXCEPTIONS = "availability_exceptions"

    def __init__(self, client: Client) -> None:
        self._client = client

    # ---- slots -------------------------------------------------------------------------
    def list_slots(self, *, active_only: bool = False) -> list[TimeSlotOut]:
        query = self._client.table(self.SLOTS).select("*")
        if active_only:
            query = query.eq("is_active", True)
        rows = run(query.order("start_time").order("end_time"))
        return [TimeSlotOut.model_validate(row) for row in rows]

    def get_slot(self, slot_id: UUID) -> TimeSlotOut | None:
        rows = run(self._client.table(self.SLOTS).select("*").eq("id", str(slot_id)).limit(1))
        return TimeSlotOut.model_validate(rows[0]) if rows else None

    def create_slot(self, values: dict[str, Any]) -> TimeSlotOut:
        rows = run(self._client.table(self.SLOTS).insert(values), conflict=_OVERLAP)
        return TimeSlotOut.model_validate(rows[0])

    def update_slot(self, slot_id: UUID, values: dict[str, Any]) -> TimeSlotOut | None:
        rows = run(
            self._client.table(self.SLOTS).update(values).eq("id", str(slot_id)),
            conflict=_OVERLAP,
        )
        return TimeSlotOut.model_validate(rows[0]) if rows else None

    def delete_slot(self, slot_id: UUID) -> bool:
        return bool(run(self._client.table(self.SLOTS).delete().eq("id", str(slot_id))))

    # ---- exceptions --------------------------------------------------------------------
    def list_exceptions(self, start: date, end: date) -> list[ExceptionOut]:
        rows = run(
            self._client.table(self.EXCEPTIONS)
            .select("*")
            .gte("exception_date", start.isoformat())
            .lte("exception_date", end.isoformat())
            .order("exception_date")
        )
        return [ExceptionOut.model_validate(row) for row in rows]

    def get_exception(self, exception_id: UUID) -> ExceptionOut | None:
        rows = run(
            self._client.table(self.EXCEPTIONS).select("*").eq("id", str(exception_id)).limit(1)
        )
        return ExceptionOut.model_validate(rows[0]) if rows else None

    def create_exception(self, values: dict[str, Any]) -> ExceptionOut:
        rows = run(
            self._client.table(self.EXCEPTIONS).insert(values), conflict=_DUPLICATE_EXCEPTION
        )
        return ExceptionOut.model_validate(rows[0])

    def update_exception(self, exception_id: UUID, values: dict[str, Any]) -> ExceptionOut | None:
        rows = run(self._client.table(self.EXCEPTIONS).update(values).eq("id", str(exception_id)))
        return ExceptionOut.model_validate(rows[0]) if rows else None

    def delete_exception(self, exception_id: UUID) -> bool:
        return bool(run(self._client.table(self.EXCEPTIONS).delete().eq("id", str(exception_id))))

    # ---- booked counts -----------------------------------------------------------------
    def booked_counts(self, start: date, end: date) -> dict[tuple[date, time, time], int]:
        rows = run(
            self._client.rpc(
                "slot_booking_counts", {"p_from": start.isoformat(), "p_to": end.isoformat()}
            )
        )
        counts: dict[tuple[date, time, time], int] = {}
        try:
            for row in rows:
                key = (
                    date.fromisoformat(row["scheduled_date"]),
                    time.fromisoformat(row["slot_start"]),
                    time.fromisoformat(row["slot_end"]),
                )
                counts[key] = int(row["booked"])
        except (KeyError, ValueError, TypeError) as exc:
            raise ServiceUnavailableError("Database returned unexpected data") from exc
        return counts
