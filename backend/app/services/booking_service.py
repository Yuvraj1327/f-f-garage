"""Creating, reading, changing and cancelling bookings.

Everything the customer sends is checked here against data the server owns: the
package and its price, whether the service is active, whether the PIN code is
serviceable, and whether the slot can be booked. The final guarantees (no oversold
slot, no duplicate, no illegal status change) are enforced again by the database.
"""

import logging
from collections.abc import Callable
from datetime import UTC, date, datetime, time
from decimal import Decimal
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

from app.core.config import Settings
from app.core.errors import (
    ConflictError,
    NotFoundError,
    UnprocessableError,
)
from app.db.assignment_repository import AssignmentRepository
from app.db.booking_repository import BookingRepository
from app.db.catalog_repository import CatalogRepository
from app.db.payment_repository import PaymentRepository
from app.db.profile_repository import ProfileRepository
from app.db.service_area_repository import ServiceAreaRepository
from app.db.tracking_repository import TrackingRepository
from app.domain import booking as rules
from app.domain.enums import BookingStatus, PaymentStatus, VehicleType
from app.schemas.assignment import AdminAssignment, AssignmentRecord, DriverSummary
from app.schemas.booking import (
    AdminBookingOut,
    AdminBookingPage,
    AdminStatusUpdate,
    BookingCreate,
    BookingOut,
    BookingPage,
    BookingQuote,
    BookingRecord,
    BookingUpdate,
    QuoteCharge,
    QuoteRequest,
)
from app.schemas.catalog import ExtraChargeOut, PackageOut, ServiceOut
from app.schemas.payment import PaymentRecord, PaymentSummary
from app.schemas.profile import ProfileOut
from app.services.availability_service import AvailabilityService

logger = logging.getLogger(__name__)

_NOT_AVAILABLE = "This service is not available right now"
_CENT = Decimal("0.01")


class _Priced:
    """The server's own pricing of a package plus the chosen add-ons."""

    def __init__(
        self,
        service: ServiceOut,
        package: PackageOut,
        charges: list[ExtraChargeOut],
        chosen: set[UUID],
    ) -> None:
        self.service = service
        self.package = package
        self.charges = charges
        self.chosen = chosen
        self.package_price = package.price.quantize(_CENT)
        self.extra_total = sum(
            (c.amount.quantize(_CENT) for c in charges if c.id in chosen and c.amount is not None),
            Decimal("0.00"),
        )
        self.total = self.package_price + self.extra_total


class BookingService:
    def __init__(
        self,
        bookings: BookingRepository,
        catalog: CatalogRepository,
        areas: ServiceAreaRepository,
        availability: AvailabilityService,
        settings: Settings,
        clock: Callable[[ZoneInfo], datetime] | None = None,
        payments: PaymentRepository | None = None,
        assignments: AssignmentRepository | None = None,
        profiles: ProfileRepository | None = None,
        tracking: TrackingRepository | None = None,
    ) -> None:
        self._tracking = tracking
        self._payments = payments
        self._assignments = assignments
        self._profiles = profiles
        self._bookings = bookings
        self._catalog = catalog
        self._areas = areas
        self._availability = availability
        self._settings = settings
        self._tz = ZoneInfo(settings.business_timezone)
        self._clock = clock or (lambda tz: datetime.now(tz))

    def _now(self) -> datetime:
        return self._clock(self._tz)

    def _slot_start(self, day: date, start: time) -> datetime:
        return datetime.combine(day, start, tzinfo=self._tz)

    # ---- Pricing -----------------------------------------------------------------------
    def _price(self, request: QuoteRequest) -> _Priced:
        package = self._catalog.get_package(request.package_id)
        service = self._catalog.get_service(package.service_id) if package else None
        if package is None or service is None or not package.is_active or not service.is_active:
            raise NotFoundError(_NOT_AVAILABLE)

        applicable = [
            c
            for c in self._catalog.list_extra_charges([service.id], active_only=True)
            if c.package_id in (None, package.id)
        ]
        by_id = {c.id: c for c in applicable}
        for charge_id in request.extra_charge_ids:
            charge = by_id.get(charge_id)
            if charge is None:
                raise UnprocessableError("One of the selected extra charges is not available")
            if charge.amount is None:
                raise UnprocessableError(
                    f'"{charge.name}" is charged at actuals on the day and cannot be added up front'
                )
        return _Priced(service, package, applicable, set(request.extra_charge_ids))

    def quote(self, request: QuoteRequest) -> BookingQuote:
        """The summary the customer confirms: all numbers come from the catalogue."""
        priced = self._price(request)
        return BookingQuote(
            service_id=priced.service.id,
            service_name=priced.service.name,
            vehicle_type=priced.service.vehicle_type,
            package_id=priced.package.id,
            package_name=priced.package.name,
            inclusions=priced.package.inclusions,
            estimated_duration_minutes=priced.package.estimated_duration_minutes,
            package_price=priced.package_price,
            extra_charges=[
                QuoteCharge(
                    extra_charge_id=c.id,
                    charge_type=c.charge_type,
                    name=c.name,
                    amount=c.amount,
                    selectable=c.amount is not None,
                    selected=c.id in priced.chosen,
                    included_in_total=c.id in priced.chosen,
                )
                for c in priced.charges
            ],
            extra_charges_total=priced.extra_total,
            total_amount=priced.total,
        )

    # ---- Location ----------------------------------------------------------------------
    def _serviceable_area(self, pincode: str):
        area = self._areas.get_by_pincode(pincode)
        if area is None or not area.is_active:
            raise UnprocessableError("We do not service this PIN code yet")
        return area

    # ---- Customer: create --------------------------------------------------------------
    def create(self, customer: ProfileOut, payload: BookingCreate) -> tuple[BookingOut, bool]:
        """Returns (booking, created). `created` is False when the same
        `client_request_id` was already used and the earlier booking is returned."""
        if payload.client_request_id is not None:
            earlier = self._bookings.find_by_request(customer.id, payload.client_request_id)
            if earlier is not None:
                return self._customer_view(earlier), False

        name = (customer.full_name or "").strip()
        phone = (customer.phone or "").strip()
        if not name or not phone:
            raise UnprocessableError(
                "Add your name and mobile number in your profile before booking"
            )

        priced = self._price(payload)
        area = self._serviceable_area(payload.pincode)
        slot = self._availability.ensure_bookable(payload.scheduled_date, payload.time_slot_id)

        if payload.expected_total is not None and payload.expected_total != priced.total:
            raise ConflictError(
                "The price has changed. Please review the updated summary and confirm again."
            )

        values: dict[str, Any] = {
            "customer_id": str(customer.id),
            "service_id": str(priced.service.id),
            "package_id": str(priced.package.id),
            "vehicle_type": priced.service.vehicle_type.value,
            "customer_name": name,
            "customer_phone": phone,
            "address_line": payload.address_line,
            "landmark": payload.landmark,
            "city": area.city,
            "state": area.state,
            "pincode": area.pincode,
            "service_area_id": str(area.id),
            "latitude": payload.latitude,
            "longitude": payload.longitude,
            "scheduled_date": payload.scheduled_date.isoformat(),
            "slot_start": slot.start_time.isoformat(),
            "slot_end": slot.end_time.isoformat(),
            "service_name": priced.service.name,
            "package_name": priced.package.name,
            "package_inclusions": priced.package.inclusions,
            "estimated_duration_minutes": priced.package.estimated_duration_minutes,
            "package_price": str(priced.package_price),
            "customer_notes": payload.customer_notes,
            "client_request_id": (
                str(payload.client_request_id) if payload.client_request_id else None
            ),
        }
        charges = [
            {
                "extra_charge_id": str(c.id),
                "charge_type": c.charge_type.value,
                "name": c.name,
                "amount": str(c.amount.quantize(_CENT)) if c.amount is not None else None,
                "included_in_total": c.id in priced.chosen,
            }
            for c in priced.charges
        ]
        try:
            record = self._bookings.create(values, charges)
        except ConflictError:
            # Two taps racing with the same key: the other one won, return its booking.
            if payload.client_request_id is not None:
                earlier = self._bookings.find_by_request(customer.id, payload.client_request_id)
                if earlier is not None:
                    return self._customer_view(earlier), False
            raise
        logger.info(
            "booking %s created by %s for %s %s",
            record.id,
            customer.id,
            record.scheduled_date,
            record.slot_start,
        )
        return self._customer_view(record), True

    # ---- Customer: read ----------------------------------------------------------------
    def get_for_customer(self, customer: ProfileOut, booking_id: UUID) -> BookingOut:
        return self._customer_view(self._owned(customer, booking_id))

    def list_for_customer(
        self,
        customer: ProfileOut,
        *,
        statuses: list[BookingStatus] | None,
        limit: int,
        offset: int,
    ) -> BookingPage:
        records, total = self._bookings.list_for_customer(
            customer.id, statuses=statuses, limit=limit, offset=offset
        )
        summaries = self._summaries(records)
        assigned = self._assigned(records)
        return BookingPage(
            items=[
                self._customer_view(r, summaries, assigned, with_timeline=False) for r in records
            ],
            total=total,
            limit=limit,
            offset=offset,
        )

    def _owned(self, customer: ProfileOut, booking_id: UUID) -> BookingRecord:
        """Someone else's booking looks exactly like a missing one."""
        record = self._bookings.get(booking_id)
        if record is None or record.customer_id != customer.id:
            raise NotFoundError("Booking not found")
        return record

    # ---- Customer: change --------------------------------------------------------------
    def update(self, customer: ProfileOut, booking_id: UUID, payload: BookingUpdate) -> BookingOut:
        record = self._owned(customer, booking_id)
        block = rules.customer_edit_block(
            record.status,
            self._slot_start(record.scheduled_date, record.slot_start),
            self._now(),
            self._settings.booking_cancel_cutoff_hours,
        )
        if block:
            raise ConflictError(block)

        sent = payload.model_fields_set
        values: dict[str, Any] = {}
        for field in ("address_line", "landmark", "latitude", "longitude", "customer_notes"):
            if field in sent:
                values[field] = getattr(payload, field)
        if ("latitude" in sent or "longitude" in sent) and (
            values.get("latitude", record.latitude) is None
        ) != (values.get("longitude", record.longitude) is None):
            raise UnprocessableError("Send latitude and longitude together")

        if "pincode" in sent and payload.pincode != record.pincode:
            area = self._serviceable_area(payload.pincode)  # type: ignore[arg-type]
            values.update(
                pincode=area.pincode,
                city=area.city,
                state=area.state,
                service_area_id=str(area.id),
            )

        if "scheduled_date" in sent:
            slot = self._availability.get_active_slot(payload.time_slot_id)  # type: ignore[arg-type]
            same = payload.scheduled_date == record.scheduled_date and (
                slot.start_time,
                slot.end_time,
            ) == (record.slot_start, record.slot_end)
            if not same:
                # The booking's own place does not count against the new slot.
                self._availability.ensure_bookable(
                    payload.scheduled_date,  # type: ignore[arg-type]
                    slot.id,
                )
                values.update(
                    scheduled_date=payload.scheduled_date.isoformat(),  # type: ignore[union-attr]
                    slot_start=slot.start_time.isoformat(),
                    slot_end=slot.end_time.isoformat(),
                )

        if not values:
            return self._customer_view(record)
        updated = self._bookings.update(
            booking_id, values, only_statuses=sorted(rules.CUSTOMER_EDITABLE_STATUSES)
        )
        if updated is None:
            raise ConflictError("This booking can no longer be changed")
        logger.info("booking %s changed by %s (%s)", booking_id, customer.id, ", ".join(values))
        return self._customer_view(updated)

    # ---- Customer: cancel --------------------------------------------------------------
    def cancel(self, customer: ProfileOut, booking_id: UUID, reason: str | None) -> BookingOut:
        record = self._owned(customer, booking_id)
        if record.status == BookingStatus.CANCELLED and record.cancelled_by == customer.id:
            return self._customer_view(record)  # a retried cancel is not an error
        block = rules.customer_cancel_block(
            record.status,
            self._slot_start(record.scheduled_date, record.slot_start),
            self._now(),
            self._settings.booking_cancel_cutoff_hours,
        )
        if block:
            raise ConflictError(block)
        updated = self._cancel_record(record, customer, reason)
        return self._customer_view(updated)

    def _cancel_record(
        self, record: BookingRecord, actor: ProfileOut, reason: str | None
    ) -> BookingRecord:
        updated = self._bookings.update(
            record.id,
            {
                "status": BookingStatus.CANCELLED.value,
                "cancelled_at": datetime.now(UTC).isoformat(),
                "cancelled_by": str(actor.id),
                "cancellation_reason": reason,
            },
            only_statuses=[record.status],
        )
        if updated is None:
            raise ConflictError("This booking was just updated. Please refresh and try again.")
        logger.info("booking %s cancelled by %s", record.id, actor.id)
        return updated

    # ---- Admin -------------------------------------------------------------------------
    def admin_search(
        self,
        *,
        statuses: list[BookingStatus] | None,
        vehicle_type: VehicleType | None,
        date_from: date | None,
        date_to: date | None,
        pincode: str | None,
        customer_id: UUID | None,
        query: str | None,
        limit: int,
        offset: int,
    ) -> AdminBookingPage:
        if date_from and date_to and date_to < date_from:
            raise UnprocessableError("The end date must not be before the start date")
        records, total = self._bookings.search(
            statuses=statuses,
            vehicle_type=vehicle_type,
            date_from=date_from,
            date_to=date_to,
            pincode=pincode,
            customer_id=customer_id,
            query=query,
            limit=limit,
            offset=offset,
        )
        summaries = self._summaries(records)
        assigned = self._assigned(records)
        return AdminBookingPage(
            items=[self._admin_view(r, summaries, assigned, with_timeline=False) for r in records],
            total=total,
            limit=limit,
            offset=offset,
        )

    def admin_page(
        self, records: list[BookingRecord], *, total: int, limit: int, offset: int
    ) -> AdminBookingPage:
        """Admin views for bookings already loaded (for example one driver's bookings)."""
        summaries = self._summaries(records)
        assigned = self._assigned(records)
        return AdminBookingPage(
            items=[self._admin_view(r, summaries, assigned, with_timeline=False) for r in records],
            total=total,
            limit=limit,
            offset=offset,
        )

    def admin_get(self, booking_id: UUID) -> AdminBookingOut:
        record = self._bookings.get(booking_id)
        if record is None:
            raise NotFoundError("Booking not found")
        return self._admin_view(record)

    def admin_update_status(
        self, admin: ProfileOut, booking_id: UUID, payload: AdminStatusUpdate
    ) -> AdminBookingOut:
        record = self._bookings.get(booking_id)
        if record is None:
            raise NotFoundError("Booking not found")
        target = payload.status
        if target == record.status:
            return self._admin_view(record)
        if target not in rules.ADMIN_MANUAL_TARGETS:
            raise UnprocessableError(
                f'"{target.value}" is set by the payment and driver workflows, not by hand'
            )
        if target not in rules.admin_next_statuses(record.status):
            raise ConflictError(f"A {record.status.value} booking cannot become {target.value}")

        updated = self._cancel_record(record, admin, payload.reason)
        return self._admin_view(updated)

    # ---- Views -------------------------------------------------------------------------
    def _summaries(self, records: list[BookingRecord]) -> dict[UUID, PaymentRecord]:
        """One query for the payments of a whole page of bookings."""
        if self._payments is None or not records:
            return {}
        return self._payments.summaries_for([r.id for r in records])

    def _assigned(
        self, records: list[BookingRecord]
    ) -> dict[UUID, tuple[AssignmentRecord, ProfileOut | None]]:
        """The current driver of each booking that has one (two queries for a whole page)."""
        if self._assignments is None or self._profiles is None:
            return {}
        ids = [
            r.id
            for r in records
            if r.status not in (BookingStatus.PENDING_PAYMENT, BookingStatus.CONFIRMED)
        ]
        if not ids:
            return {}
        active = self._assignments.active_for_bookings(ids)
        people = {
            p.id: p
            for p in self._profiles.get_many(sorted({str(a.driver_id) for a in active.values()}))
        }
        return {booking_id: (a, people.get(a.driver_id)) for booking_id, a in active.items()}

    def _customer_view(
        self,
        record: BookingRecord,
        summaries: dict[UUID, PaymentRecord] | None = None,
        assigned: dict[UUID, tuple[AssignmentRecord, ProfileOut | None]] | None = None,
        *,
        with_timeline: bool = True,
    ) -> BookingOut:
        if assigned is None:
            assigned = self._assigned([record])
        data = self._base(record, summaries)
        if with_timeline and self._tracking is not None:
            data["timeline"] = self._tracking.timeline(record.id)
        found = assigned.get(record.id)
        if found and record.status != BookingStatus.CANCELLED:
            driver = found[1]
            data["driver"] = DriverSummary(
                name=driver.full_name if driver else None,
                phone=driver.phone if driver else None,
            )
        return BookingOut(**data)

    def _admin_view(
        self,
        record: BookingRecord,
        summaries: dict[UUID, PaymentRecord] | None = None,
        assigned: dict[UUID, tuple[AssignmentRecord, ProfileOut | None]] | None = None,
        *,
        with_timeline: bool = True,
    ) -> AdminBookingOut:
        if assigned is None:
            assigned = self._assigned([record])
        data = self._base(record, summaries)
        if with_timeline and self._tracking is not None:
            data["timeline"] = self._tracking.timeline(record.id)
        found = assigned.get(record.id)
        assignment = None
        if found:
            current, driver = found
            assignment = AdminAssignment(
                driver_id=current.driver_id,
                driver_name=driver.full_name if driver else None,
                driver_login_id=driver.driver_login_id if driver else None,
                driver_phone=driver.phone if driver else None,
                driver_is_active=driver.is_active if driver else False,
                assigned_at=current.assigned_at,
                assigned_by=current.assigned_by,
            )
        return AdminBookingOut(
            **data,
            customer_id=record.customer_id,
            service_area_id=record.service_area_id,
            cancelled_by=record.cancelled_by,
            updated_at=record.updated_at,
            allowed_status_updates=rules.admin_next_statuses(record.status),
            assignment=assignment,
            can_assign=record.status in rules.ADMIN_ASSIGNABLE_STATUSES
            and bool(data.get("is_paid")),
            can_unassign=record.status == BookingStatus.ASSIGNED,
        )

    def _payment_fields(
        self, record: BookingRecord, summaries: dict[UUID, PaymentRecord] | None
    ) -> dict[str, Any]:
        if self._payments is None:
            return {}
        if summaries is None:
            summaries = self._summaries([record])
        latest = summaries.get(record.id)
        paid = latest is not None and latest.status == PaymentStatus.SUCCESSFUL
        return {
            "payment": PaymentSummary(
                id=latest.id,
                status=latest.status,
                amount=latest.amount,
                currency=latest.currency,
                method=latest.method,
                transaction_id=latest.provider_payment_id,
                paid_at=latest.paid_at,
                failure_reason=latest.failure_reason,
                livemode=latest.livemode,
                created_at=latest.created_at,
            )
            if latest
            else None,
            "is_paid": paid,
            "can_pay": (
                self._settings.payments_enabled
                and record.status == BookingStatus.PENDING_PAYMENT
                and record.total_amount > 0
                and not paid
            ),
        }

    def _base(
        self, record: BookingRecord, summaries: dict[UUID, PaymentRecord] | None = None
    ) -> dict[str, Any]:
        slot_start = self._slot_start(record.scheduled_date, record.slot_start)
        now = self._now()
        cutoff = self._settings.booking_cancel_cutoff_hours
        cancel_block = rules.customer_cancel_block(record.status, slot_start, now, cutoff)
        edit_block = rules.customer_edit_block(record.status, slot_start, now, cutoff)
        data = record.model_dump(
            exclude={
                "customer_id",
                "service_area_id",
                "cancelled_by",
                "client_request_id",
                "updated_at",
            }
        )
        data["extra_charges"] = record.extra_charges
        data.update(
            booking_code=rules.booking_code(record.booking_number),
            can_cancel=cancel_block is None,
            can_modify=edit_block is None,
            cancel_blocked_reason=cancel_block
            if record.status not in rules.FINAL_STATUSES
            else None,
        )
        data.update(self._payment_fields(record, summaries))
        return data
