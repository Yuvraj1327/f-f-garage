"""The bill of a booking: estimate, approved extras, advance, balance, receipts, refunds."""

from decimal import Decimal
from uuid import UUID

from app.core.config import Settings
from app.core.errors import NotFoundError
from app.db.booking_repository import BookingRepository
from app.db.extra_request_repository import ExtraRequestRepository
from app.db.payment_repository import PaymentRepository
from app.db.refund_repository import RefundRepository
from app.domain import billing
from app.domain import booking as booking_rules
from app.domain.enums import BookingStatus, PaymentStatus
from app.schemas.billing import BillOut, BillPayment, RefundRecord
from app.schemas.booking import BookingRecord
from app.schemas.payment import PaymentRecord
from app.schemas.profile import ProfileOut
from app.services.extra_request_service import extra_out
from app.services.garage_settings_service import GarageSettingsService

ZERO = Decimal("0.00")


def successful_total(payments: list[PaymentRecord], kind: str | None = None) -> Decimal:
    return sum(
        (
            p.amount
            for p in payments
            if p.status == PaymentStatus.SUCCESSFUL and (kind is None or p.kind == kind)
        ),
        ZERO,
    )


class BillingService:
    def __init__(
        self,
        bookings: BookingRepository,
        payments: PaymentRepository,
        extras: ExtraRequestRepository,
        refunds: RefundRepository,
        garage: GarageSettingsService,
        settings: Settings,
    ) -> None:
        self._bookings = bookings
        self._payments = payments
        self._extras = extras
        self._refunds = refunds
        self._garage = garage
        self._settings = settings

    def build(self, record: BookingRecord) -> BillOut:
        payments = sorted(self._payments.list_for_booking(record.id), key=lambda p: p.created_at)
        extras = self._extras.list_for_booking(record.id)
        refunds: list[RefundRecord] = self._refunds.list_for_booking(record.id)

        approved = [e for e in extras if e.status == "approved"]
        pending = [e for e in extras if e.status == "proposed"]
        approved_total = sum((e.amount for e in approved), ZERO)
        pending_total = sum((e.amount for e in pending), ZERO)
        estimated = record.total_amount
        final_total = estimated + approved_total
        advance_paid = successful_total(payments, "advance")
        paid = successful_total(payments)
        cancelled = record.status == BookingStatus.CANCELLED
        due = ZERO if cancelled else billing.balance_remaining(final_total, paid)
        completed = record.status == BookingStatus.COMPLETED
        addons = record.extra_charges_total

        return BillOut(
            booking_id=record.id,
            booking_code=booking_rules.booking_code(record.booking_number),
            status=record.status,
            is_final=completed,
            service_name=record.service_name,
            package_name=record.package_name,
            package_price=record.package_price,
            addons_total=addons,
            coupon_code=record.coupon_code,
            discount_amount=record.discount_amount,
            estimated_total=estimated,
            advance_percent=record.advance_percent,
            advance_due=billing.advance_due(record.advance_amount, estimated),
            advance_paid=advance_paid,
            approved_extras=[extra_out(e) for e in approved],
            approved_extras_total=approved_total,
            pending_extras=[extra_out(e) for e in pending],
            pending_extras_total=pending_total,
            final_total=final_total,
            amount_paid=paid,
            balance_due=due,
            can_pay_balance=(
                self._settings.payments_enabled and completed and due > 0 and not pending
            ),
            refunded_total=sum((r.amount for r in refunds), ZERO),
            payments=[
                BillPayment(
                    id=p.id,
                    kind=p.kind,  # type: ignore[arg-type]
                    status=p.status.value,
                    amount=p.amount,
                    method=p.method,
                    receipt=p.receipt,
                    transaction_id=p.provider_payment_id,
                    paid_at=p.paid_at,
                    created_at=p.created_at,
                )
                for p in payments
                if p.status == PaymentStatus.SUCCESSFUL
            ],
            refunds=refunds,
            refund_policy=self._garage.current().refund_policy,
        )

    def for_customer(self, customer: ProfileOut, booking_id: UUID) -> BillOut:
        record = self._bookings.get(booking_id)
        if record is None or record.customer_id != customer.id:
            raise NotFoundError("Booking not found")
        return self.build(record)

    def for_admin(self, booking_id: UUID) -> BillOut:
        record = self._bookings.get(booking_id)
        if record is None:
            raise NotFoundError("Booking not found")
        return self.build(record)
