"""Extra parts or repairs found during a visit.

A driver (or an admin) proposes them while the service is in progress. Nothing is added to
the bill until the customer approves it, and a driver cannot finish the job while a request
is still unanswered (the database enforces both).
"""

import logging
from uuid import UUID

from app.core.errors import ConflictError, NotFoundError
from app.db.assignment_repository import AssignmentRepository
from app.db.booking_repository import BookingRepository
from app.db.extra_request_repository import ExtraRequestRepository
from app.domain.enums import BookingStatus
from app.schemas.billing import ExtraRequestCreate, ExtraRequestOut, ExtraRequestRecord
from app.schemas.booking import BookingRecord
from app.schemas.profile import ProfileOut

logger = logging.getLogger(__name__)

_NOT_FOUND = "Booking not found"
MAX_REQUESTS_PER_BOOKING = 20


def extra_out(record: ExtraRequestRecord) -> ExtraRequestOut:
    return ExtraRequestOut(
        id=record.id,
        booking_id=record.booking_id,
        charge_type=record.charge_type,
        name=record.name,
        description=record.description,
        amount=record.amount,
        status=record.status,
        requested_by_role=record.requested_by_role,
        decided_at=record.decided_at,
        created_at=record.created_at,
    )


class ExtraRequestService:
    def __init__(
        self,
        extras: ExtraRequestRepository,
        bookings: BookingRepository,
        assignments: AssignmentRepository,
    ) -> None:
        self._extras = extras
        self._bookings = bookings
        self._assignments = assignments

    # ---- shared ------------------------------------------------------------------------
    def _booking(self, booking_id: UUID) -> BookingRecord:
        record = self._bookings.get(booking_id)
        if record is None:
            raise NotFoundError(_NOT_FOUND)
        return record

    def _extra(self, booking_id: UUID, extra_id: UUID) -> ExtraRequestRecord:
        extra = self._extras.get(extra_id)
        if extra is None or extra.booking_id != booking_id:
            raise NotFoundError("Extra charge request not found")
        return extra

    def _list(self, booking_id: UUID) -> list[ExtraRequestOut]:
        return [extra_out(e) for e in self._extras.list_for_booking(booking_id)]

    def _create(
        self, booking: BookingRecord, actor: ProfileOut, role: str, payload: ExtraRequestCreate
    ) -> ExtraRequestOut:
        if booking.status != BookingStatus.IN_PROGRESS:
            raise ConflictError(
                "Extra charges can only be requested while the service is in progress"
            )
        if len(self._extras.list_for_booking(booking.id)) >= MAX_REQUESTS_PER_BOOKING:
            raise ConflictError("Too many extra charge requests for this booking")
        record = self._extras.create(
            {
                "booking_id": str(booking.id),
                "name": payload.name,
                "amount": str(payload.amount),
                "charge_type": payload.charge_type.value,
                "description": payload.description,
                "requested_by": str(actor.id),
                "requested_by_role": role,
            }
        )
        logger.info("%s %s requested extra %s on booking %s", role, actor.id, record.id, booking.id)
        return extra_out(record)

    def _withdraw(self, booking_id: UUID, extra_id: UUID) -> ExtraRequestOut:
        extra = self._extra(booking_id, extra_id)
        if extra.status == "withdrawn":
            return extra_out(extra)
        if extra.status != "proposed":
            raise ConflictError("This request was already answered by the customer")
        updated = self._extras.answer(extra_id, "withdrawn")
        if updated is None:
            raise ConflictError("This request was just answered. Please refresh.")
        return extra_out(updated)

    # ---- Customer ----------------------------------------------------------------------
    def _owned(self, customer: ProfileOut, booking_id: UUID) -> BookingRecord:
        record = self._booking(booking_id)
        if record.customer_id != customer.id:
            raise NotFoundError(_NOT_FOUND)
        return record

    def list_for_customer(self, customer: ProfileOut, booking_id: UUID) -> list[ExtraRequestOut]:
        self._owned(customer, booking_id)
        return self._list(booking_id)

    def decide(
        self, customer: ProfileOut, booking_id: UUID, extra_id: UUID, *, approve: bool
    ) -> ExtraRequestOut:
        booking = self._owned(customer, booking_id)
        extra = self._extra(booking_id, extra_id)
        target = "approved" if approve else "declined"
        if extra.status == target:
            return extra_out(extra)  # the same answer sent twice is not an error
        if extra.status != "proposed":
            raise ConflictError(
                "This request was withdrawn"
                if extra.status == "withdrawn"
                else "This request was already answered"
            )
        if booking.status != BookingStatus.IN_PROGRESS:
            raise ConflictError("This request can no longer be answered")
        updated = self._extras.answer(extra_id, target)
        if updated is None:
            current = self._extras.get(extra_id)
            if current is not None and current.status == target:
                return extra_out(current)
            raise ConflictError("This request was just changed. Please refresh.")
        logger.info(
            "customer %s %s extra %s on booking %s", customer.id, target, extra_id, booking_id
        )
        return extra_out(updated)

    # ---- Driver (own bookings only) ----------------------------------------------------
    def _mine(self, driver: ProfileOut, booking_id: UUID) -> BookingRecord:
        if not self._assignments.is_assigned(booking_id, driver.id):
            raise NotFoundError(_NOT_FOUND)
        return self._booking(booking_id)

    def list_for_driver(self, driver: ProfileOut, booking_id: UUID) -> list[ExtraRequestOut]:
        self._mine(driver, booking_id)
        return self._list(booking_id)

    def request_as_driver(
        self, driver: ProfileOut, booking_id: UUID, payload: ExtraRequestCreate
    ) -> ExtraRequestOut:
        return self._create(self._mine(driver, booking_id), driver, "driver", payload)

    def withdraw_as_driver(
        self, driver: ProfileOut, booking_id: UUID, extra_id: UUID
    ) -> ExtraRequestOut:
        self._mine(driver, booking_id)
        return self._withdraw(booking_id, extra_id)

    # ---- Admin -------------------------------------------------------------------------
    def list_for_admin(self, booking_id: UUID) -> list[ExtraRequestOut]:
        self._booking(booking_id)
        return self._list(booking_id)

    def request_as_admin(
        self, admin: ProfileOut, booking_id: UUID, payload: ExtraRequestCreate
    ) -> ExtraRequestOut:
        return self._create(self._booking(booking_id), admin, "admin", payload)

    def withdraw_as_admin(self, booking_id: UUID, extra_id: UUID) -> ExtraRequestOut:
        self._booking(booking_id)
        return self._withdraw(booking_id, extra_id)
