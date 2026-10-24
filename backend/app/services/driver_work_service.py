"""A driver's own work: the bookings assigned to them and the steps they may take.

Server-side authorization lives here and in the database, never in the app:
  * a driver only ever sees or changes a booking while they hold its current assignment;
    anyone else's booking looks exactly like a missing one (404);
  * the only steps are assigned -> on_the_way -> in_progress -> completed, one at a time;
  * drivers never see prices or payments, and cannot cancel or reassign.
"""

import logging
from uuid import UUID

from app.core.errors import ConflictError, ForbiddenError, NotFoundError, UnprocessableError
from app.db.assignment_repository import AssignmentRepository
from app.db.booking_repository import BookingRepository
from app.domain import booking as rules
from app.schemas.assignment import DriverStatusUpdate
from app.schemas.booking import BookingRecord
from app.schemas.driver_work import DriverBookingOut, DriverBookingPage
from app.schemas.profile import ProfileOut

logger = logging.getLogger(__name__)

_SCOPES = ("open", "history")
_NOT_FOUND = "Booking not found"


def driver_view(record: BookingRecord) -> DriverBookingOut:
    return DriverBookingOut(
        id=record.id,
        booking_number=record.booking_number,
        booking_code=rules.booking_code(record.booking_number),
        status=record.status,
        vehicle_type=record.vehicle_type,
        service_name=record.service_name,
        package_name=record.package_name,
        package_inclusions=record.package_inclusions,
        estimated_duration_minutes=record.estimated_duration_minutes,
        customer_name=record.customer_name,
        customer_phone=record.customer_phone,
        address_line=record.address_line,
        landmark=record.landmark,
        city=record.city,
        state=record.state,
        pincode=record.pincode,
        latitude=record.latitude,
        longitude=record.longitude,
        scheduled_date=record.scheduled_date,
        slot_start=record.slot_start,
        slot_end=record.slot_end,
        customer_notes=record.customer_notes,
        extra_charges=record.extra_charges,
        next_status=rules.driver_next_status(record.status),
    )


class DriverWorkService:
    def __init__(self, assignments: AssignmentRepository, bookings: BookingRepository) -> None:
        self._assignments = assignments
        self._bookings = bookings

    def list(self, driver: ProfileOut, *, scope: str, limit: int, offset: int) -> DriverBookingPage:
        if scope not in _SCOPES:
            raise UnprocessableError("scope must be open or history")
        ids, total = self._assignments.driver_booking_ids(driver.id, scope, limit, offset)
        records = self._bookings.get_many(ids)
        return DriverBookingPage(
            items=[driver_view(r) for r in records], total=total, limit=limit, offset=offset
        )

    def get(self, driver: ProfileOut, booking_id: UUID) -> DriverBookingOut:
        return driver_view(self._mine(driver, booking_id))

    def update_status(
        self, driver: ProfileOut, booking_id: UUID, payload: DriverStatusUpdate
    ) -> DriverBookingOut:
        outcome = self._assignments.driver_update_status(booking_id, driver.id, payload.status)
        match outcome.result:
            case "updated":
                logger.info(
                    "driver %s moved booking %s to %s", driver.id, booking_id, payload.status.value
                )
            case "unchanged":
                pass  # the same step sent twice (a retry) is not an error
            case "booking_not_found" | "not_assigned":
                raise NotFoundError(_NOT_FOUND)
            case "driver_inactive":
                raise ForbiddenError("This account has been disabled")
            case "booking_cancelled":
                raise ConflictError("This booking was cancelled")
            case "invalid_transition":
                current = outcome.booking_status
                expected = rules.driver_next_status(current) if current else None
                hint = f" Next step: {expected.value}." if expected else ""
                raise ConflictError(
                    f"The booking cannot move to {payload.status.value} from "
                    f"{current.value if current else 'its current status'}.{hint}"
                )
            case other:
                raise ConflictError(f"The status could not be updated ({other})")
        return driver_view(self._mine(driver, booking_id))

    def _mine(self, driver: ProfileOut, booking_id: UUID) -> BookingRecord:
        if not self._assignments.is_assigned(booking_id, driver.id):
            raise NotFoundError(_NOT_FOUND)
        record = self._bookings.get(booking_id)
        if record is None:
            raise NotFoundError(_NOT_FOUND)
        return record
