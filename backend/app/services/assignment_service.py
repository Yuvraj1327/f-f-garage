"""Admin: give a booking to a driver, change the driver, or take the driver off.

The database function does the checking and the change in one locked transaction
(see migration 10). This service turns its answer into the right HTTP error and returns
the refreshed booking, so what the admin sees is always what the database now holds.
"""

import logging
from uuid import UUID

from app.core.errors import ConflictError, NotFoundError, UnprocessableError
from app.db.assignment_repository import AssignmentRepository
from app.db.booking_repository import BookingRepository
from app.db.profile_repository import ProfileRepository
from app.domain.enums import BookingStatus, UserRole
from app.schemas.assignment import AssignmentHistoryItem
from app.schemas.booking import AdminBookingOut, AdminBookingPage
from app.schemas.profile import ProfileOut
from app.services.booking_service import BookingService

logger = logging.getLogger(__name__)

_DRIVER_SCOPES = ("open", "history")

_NOT_ASSIGNABLE = {
    BookingStatus.PENDING_PAYMENT: "This booking has not been paid yet, so it cannot be assigned",
    BookingStatus.IN_PROGRESS: "The service is already in progress, so the driver cannot change",
    BookingStatus.COMPLETED: "This booking is completed and cannot be assigned",
    BookingStatus.CANCELLED: "This booking is cancelled and cannot be assigned",
}

_NOT_UNASSIGNABLE = {
    BookingStatus.PENDING_PAYMENT: "This booking has no driver to remove",
    BookingStatus.ON_THE_WAY: "The driver is already on the way, so they cannot be removed. "
    "Assign a different driver instead.",
    BookingStatus.IN_PROGRESS: "The service is already in progress, so the driver stays",
    BookingStatus.COMPLETED: "This booking is completed",
    BookingStatus.CANCELLED: "This booking is cancelled",
}


class AssignmentService:
    def __init__(
        self,
        assignments: AssignmentRepository,
        bookings: BookingRepository,
        profiles: ProfileRepository,
        booking_service: BookingService,
    ) -> None:
        self._assignments = assignments
        self._bookings = bookings
        self._profiles = profiles
        self._booking_service = booking_service

    def assign(self, admin: ProfileOut, booking_id: UUID, driver_id: UUID) -> AdminBookingOut:
        """Assigns or changes the driver. Asking for the current driver again is a no-op."""
        outcome = self._assignments.assign(booking_id, driver_id, admin.id)
        status = outcome.booking_status
        match outcome.result:
            case "assigned" | "reassigned" | "unchanged":
                if outcome.result != "unchanged":
                    logger.info(
                        "admin %s %s booking %s to driver %s",
                        admin.id,
                        outcome.result,
                        booking_id,
                        driver_id,
                    )
            case "booking_not_found":
                raise NotFoundError("Booking not found")
            case "driver_not_found":
                raise NotFoundError("Driver not found")
            case "driver_inactive":
                raise ConflictError("This driver is deactivated and cannot be given bookings")
            case "not_paid":
                raise ConflictError(
                    "This booking has no verified payment, so a driver cannot be assigned"
                )
            case "not_assignable":
                raise ConflictError(
                    _NOT_ASSIGNABLE.get(status, "This booking cannot be assigned")  # type: ignore[arg-type]
                )
            case "driver_busy":
                raise ConflictError("This driver already has a visit that overlaps this time slot")
            case other:
                raise ConflictError(f"The assignment could not be made ({other})")
        return self._booking_service.admin_get(booking_id)

    def unassign(self, admin: ProfileOut, booking_id: UUID) -> AdminBookingOut:
        outcome = self._assignments.unassign(booking_id, admin.id)
        match outcome.result:
            case "unassigned":
                logger.info("admin %s removed the driver of booking %s", admin.id, booking_id)
            case "unchanged":
                pass
            case "booking_not_found":
                raise NotFoundError("Booking not found")
            case "not_unassignable":
                raise ConflictError(
                    _NOT_UNASSIGNABLE.get(  # type: ignore[arg-type]
                        outcome.booking_status, "The driver cannot be removed from this booking"
                    )
                )
            case other:
                raise ConflictError(f"The driver could not be removed ({other})")
        return self._booking_service.admin_get(booking_id)

    def history(self, booking_id: UUID) -> list[AssignmentHistoryItem]:
        if self._bookings.get(booking_id) is None:
            raise NotFoundError("Booking not found")
        records = self._assignments.history(booking_id)
        ids = sorted({str(i) for r in records for i in (r.driver_id, r.assigned_by)})
        people = {p.id: p for p in self._profiles.get_many(ids)}
        items = []
        for r in records:
            driver = people.get(r.driver_id)
            by = people.get(r.assigned_by)
            items.append(
                AssignmentHistoryItem(
                    id=r.id,
                    driver_id=r.driver_id,
                    driver_name=driver.full_name if driver else None,
                    driver_login_id=driver.driver_login_id if driver else None,
                    assigned_by=r.assigned_by,
                    assigned_by_name=by.full_name if by else None,
                    assigned_at=r.assigned_at,
                    unassigned_at=r.unassigned_at,
                    is_active=r.is_active,
                )
            )
        return items

    def driver_bookings(
        self, driver_id: UUID, *, scope: str, limit: int, offset: int
    ) -> AdminBookingPage:
        """A driver's bookings as an admin sees them (for moving work off a driver)."""
        if scope not in _DRIVER_SCOPES:
            raise UnprocessableError("scope must be open or history")
        driver = self._profiles.get_driver(str(driver_id))
        if driver is None or driver.role != UserRole.DRIVER:
            raise NotFoundError("Driver not found")
        ids, total = self._assignments.driver_booking_ids(driver_id, scope, limit, offset)
        records = self._bookings.get_many(ids)
        return self._booking_service.admin_page(records, total=total, limit=limit, offset=offset)
