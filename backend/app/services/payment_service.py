"""Paying for a booking.

The rules this module enforces:

  * The amount is always worked out on the server. The app never sends one. When booking it
    is the ADVANCE (a share of the estimated total); after the service it is the BALANCE
    (the final bill, including extra charges the customer approved, minus what was paid).
  * Nothing the app reports is believed. A checkout result is accepted only after the
    signature is recomputed with the secret key AND the gateway confirms the payment
    (order, amount, currency, captured). Webhooks are accepted only with a valid
    signature over the raw body.
  * Marking a payment successful and confirming the booking happens in one database
    function (`apply_payment_event`), which is idempotent: the checkout callback, a
    replayed webhook and a retry all end in the same state.
"""

import hashlib
import json
import logging
from collections.abc import Callable
from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

from app.core.config import Settings
from app.core.errors import (
    BadRequestError,
    ConflictError,
    NotFoundError,
    ServiceUnavailableError,
    UnprocessableError,
)
from app.db.booking_repository import BookingRepository
from app.db.extra_request_repository import ExtraRequestRepository
from app.db.payment_repository import AppliedEvent, PaymentRepository
from app.db.refund_repository import RefundRepository
from app.domain import billing
from app.domain import booking as booking_rules
from app.domain import payment as rules
from app.domain.enums import BookingStatus, PaymentStatus
from app.schemas.billing import RefundCreate
from app.schemas.booking import BookingRecord
from app.schemas.payment import (
    AdminPaymentDetail,
    AdminPaymentOut,
    AdminPaymentPage,
    CheckoutOptions,
    PaymentInitiated,
    PaymentOut,
    PaymentRecord,
    PaymentResult,
    PaymentVerify,
    WebhookAck,
)
from app.schemas.profile import ProfileOut
from app.services.billing_service import successful_total
from app.services.payment_gateway import GatewayPayment, PaymentGateway

logger = logging.getLogger(__name__)

PROVIDER = "razorpay"
CURRENCY = "INR"
_UNAVAILABLE = "Online payments are not available right now."
_NOT_VERIFIED = "We could not verify this payment. If money was taken it will be matched shortly."


def payment_out(record: PaymentRecord) -> PaymentOut:
    return PaymentOut(
        id=record.id,
        booking_id=record.booking_id,
        provider=record.provider,
        gateway_order_id=record.provider_order_id,
        kind=record.kind,
        status=record.status,
        amount=record.amount,
        currency=record.currency,
        method=record.method,
        receipt=record.receipt,
        transaction_id=record.provider_payment_id,
        paid_at=record.paid_at,
        failure_reason=record.failure_reason,
        livemode=record.livemode,
        created_at=record.created_at,
    )


def admin_payment_out(record: PaymentRecord) -> AdminPaymentOut:
    return AdminPaymentOut(
        **payment_out(record).model_dump(),
        customer_id=record.customer_id,
        needs_review=record.needs_review,
        review_reason=record.review_reason,
        updated_at=record.updated_at,
    )


class PaymentService:
    def __init__(
        self,
        payments: PaymentRepository,
        bookings: BookingRepository,
        gateway: PaymentGateway | None,
        settings: Settings,
        clock: Callable[[], datetime] | None = None,
        extras: ExtraRequestRepository | None = None,
        refunds: RefundRepository | None = None,
    ) -> None:
        self._extras = extras
        self._refunds = refunds
        self._payments = payments
        self._bookings = bookings
        self._gateway = gateway
        self._settings = settings
        self._clock = clock or (lambda: datetime.now(UTC))

    # ---- helpers -----------------------------------------------------------------------
    def _require_gateway(self) -> PaymentGateway:
        if not self._settings.payments_enabled or self._gateway is None:
            raise ServiceUnavailableError(_UNAVAILABLE, log_message="payments are not configured")
        return self._gateway

    def _owned_booking(self, customer: ProfileOut, booking_id: UUID) -> BookingRecord:
        record = self._bookings.get(booking_id)
        if record is None or record.customer_id != customer.id:
            raise NotFoundError("Booking not found")
        return record

    def _owned_payment(self, customer: ProfileOut, payment_id: UUID) -> PaymentRecord:
        record = self._payments.get(payment_id)
        if record is None or record.customer_id != customer.id:
            raise NotFoundError("Payment not found")
        return record

    def _checkout(self, record: PaymentRecord, booking: BookingRecord, customer: ProfileOut):
        assert record.provider_order_id is not None
        return CheckoutOptions(
            key_id=self._settings.payment_gateway_key_id,
            order_id=record.provider_order_id,
            amount_paise=rules.to_paise(record.amount),
            currency=record.currency,
            name=self._settings.payment_checkout_name,
            description=f"{booking_rules.booking_code(booking.booking_number)} - "
            f"{booking.service_name} ({booking.package_name})"
            f" - {'balance' if record.kind == 'balance' else 'advance'}",
            prefill_name=customer.full_name,
            prefill_contact=customer.phone,
            prefill_email=customer.email,
            mode="live" if self._settings.payments_live else "test",
        )

    def _what_to_collect(
        self, booking: BookingRecord, existing: list[PaymentRecord]
    ) -> tuple[str, Decimal]:
        """('advance', amount) when booking, ('balance', amount) after the service. Raises
        409/422 when there is nothing to collect right now."""
        paid = successful_total(existing)
        if booking.status == BookingStatus.COMPLETED:
            approved = (
                self._extras.summaries([booking.id]).get(booking.id) if self._extras else None
            )
            extras_total = approved.approved_total if approved else billing.ZERO
            due = billing.balance_remaining(booking.total_amount + extras_total, paid)
            if due <= 0:
                raise ConflictError("This booking is already paid")
            return "balance", due
        if any(p.status == PaymentStatus.SUCCESSFUL for p in existing):
            raise ConflictError("This booking is already paid")
        if booking.status != BookingStatus.PENDING_PAYMENT:
            raise ConflictError(
                "This booking was cancelled"
                if booking.status == BookingStatus.CANCELLED
                else "This booking is not waiting for payment"
            )
        amount = billing.advance_due(booking.advance_amount, booking.total_amount)
        if amount <= 0:
            raise UnprocessableError("There is nothing to pay for this booking")
        return "advance", amount

    # ---- Customer: start a payment -------------------------------------------------------
    def initiate(self, customer: ProfileOut, booking_id: UUID) -> PaymentInitiated:
        gateway = self._require_gateway()
        booking = self._owned_booking(customer, booking_id)
        existing = self._payments.list_for_booking(booking.id)
        kind, amount = self._what_to_collect(booking, existing)

        # Reuse a recent, unfinished attempt for the same amount: two taps (or two
        # devices) never create two live orders.
        open_attempt = next((p for p in existing if p.status == PaymentStatus.PENDING), None)
        if open_attempt is not None:
            fresh = self._clock() - open_attempt.created_at < timedelta(
                minutes=self._settings.payment_attempt_reuse_minutes
            )
            if (
                fresh
                and open_attempt.amount == amount
                and open_attempt.kind == kind
                and open_attempt.provider_order_id
            ):
                return PaymentInitiated(
                    payment=payment_out(open_attempt),
                    checkout=self._checkout(open_attempt, booking, customer),
                )
            if self._payments.cancel_open(open_attempt.id) is None:
                raise ConflictError("A payment for this booking just changed. Please try again.")

        code = booking_rules.booking_code(booking.booking_number)
        receipt = code if kind == "advance" else f"{code}-B"
        order = gateway.create_order(
            amount_paise=rules.to_paise(amount),
            currency=CURRENCY,
            receipt=receipt,
            notes={"booking_id": str(booking.id), "booking_code": code, "kind": kind},
        )
        try:
            record = self._payments.create_attempt(
                {
                    "booking_id": str(booking.id),
                    "customer_id": str(customer.id),
                    "provider": PROVIDER,
                    "provider_order_id": order.id,
                    "kind": kind,
                    "amount": str(amount),
                    "currency": CURRENCY,
                    "receipt": receipt,
                    "livemode": self._settings.payments_live,
                }
            )
        except ConflictError:
            # A concurrent request won the race: hand back its attempt.
            winner = self._payments.find_open(booking.id)
            if winner is None or not winner.provider_order_id:
                raise
            return PaymentInitiated(
                payment=payment_out(winner), checkout=self._checkout(winner, booking, customer)
            )
        logger.info("payment %s started for booking %s", record.id, booking.id)
        return PaymentInitiated(
            payment=payment_out(record), checkout=self._checkout(record, booking, customer)
        )

    # ---- Customer: report the checkout result ------------------------------------------
    def verify(
        self, customer: ProfileOut, payment_id: UUID, payload: PaymentVerify
    ) -> PaymentResult:
        gateway = self._require_gateway()
        record = self._owned_payment(customer, payment_id)
        if payload.razorpay_order_id != record.provider_order_id:
            raise UnprocessableError("This payment does not belong to that order")

        secret = self._settings.payment_gateway_key_secret.get_secret_value()
        if not rules.verify_checkout_signature(
            payload.razorpay_order_id,
            payload.razorpay_payment_id,
            payload.razorpay_signature,
            secret,
        ):
            self._payments.log_event(
                provider=PROVIDER,
                source="verify",
                event_type="checkout.callback",
                outcome="invalid_signature",
                order_id=payload.razorpay_order_id,
                payment_id=payload.razorpay_payment_id,
                payment_uuid=record.id,
                detail=None,
            )
            logger.warning("invalid checkout signature for payment %s", record.id)
            raise UnprocessableError("The payment could not be verified")

        if (
            record.status == PaymentStatus.SUCCESSFUL
            and record.provider_payment_id == payload.razorpay_payment_id
        ):
            return self._result(record, "already_processed")

        remote = gateway.fetch_payment(payload.razorpay_payment_id)
        if remote is None or remote.order_id != record.provider_order_id:
            self._payments.log_event(
                provider=PROVIDER,
                source="verify",
                event_type="checkout.callback",
                outcome="gateway_mismatch",
                order_id=payload.razorpay_order_id,
                payment_id=payload.razorpay_payment_id,
                payment_uuid=record.id,
                detail=None,
            )
            raise UnprocessableError(_NOT_VERIFIED)

        applied = self._apply_remote(remote, record.provider_order_id, "verify", None)
        updated = self._payments.get(record.id) or record
        return self._result(updated, applied.result, applied.booking_status)

    @staticmethod
    def _outcome_of(remote: GatewayPayment) -> tuple[str, str | None]:
        if remote.status == "captured":
            return "captured", None
        if remote.status == "failed":
            return "failed", remote.error_description or "The payment failed"
        if remote.status == "refunded":
            return "failed", "The payment was refunded"
        return "authorized", None

    def _apply_remote(
        self, remote: GatewayPayment, order_id: str, source: str, event_id: str | None
    ) -> AppliedEvent:
        outcome, failure = self._outcome_of(remote)
        return self._payments.apply_event(
            provider=PROVIDER,
            order_id=order_id,
            payment_id=remote.id,
            outcome=outcome,
            amount_paise=remote.amount_paise,
            currency=remote.currency,
            method=remote.method,
            failure=failure,
            source=source,
            event_id=event_id,
            event_type=f"payment.{remote.status}",
            detail={
                "status": remote.status,
                "amount_paise": remote.amount_paise,
                "currency": remote.currency,
            },
        )

    def _result(
        self,
        record: PaymentRecord,
        outcome: str,
        booking_status: BookingStatus | None = None,
    ) -> PaymentResult:
        if booking_status is None:
            booking = self._bookings.get(record.booking_id)
            booking_status = booking.status if booking else BookingStatus.PENDING_PAYMENT
        return PaymentResult(
            payment=payment_out(record),
            booking_status=booking_status,
            outcome=outcome,
            paid=record.status == PaymentStatus.SUCCESSFUL,
        )

    # ---- Customer: cancel, read ---------------------------------------------------------
    def cancel(self, customer: ProfileOut, payment_id: UUID) -> PaymentOut:
        """The customer closed the checkout. Only an unfinished attempt can be cancelled; if
        money turns up later it is still honoured (see `apply_payment_event`)."""
        record = self._owned_payment(customer, payment_id)
        if record.status == PaymentStatus.PENDING:
            record = (
                self._payments.cancel_open(record.id) or self._payments.get(record.id) or record
            )
        return payment_out(record)

    def get(self, customer: ProfileOut, payment_id: UUID) -> PaymentOut:
        return payment_out(self._owned_payment(customer, payment_id))

    def list_for_booking(self, customer: ProfileOut, booking_id: UUID) -> list[PaymentOut]:
        booking = self._owned_booking(customer, booking_id)
        return [payment_out(p) for p in self._payments.list_for_booking(booking.id)]

    # ---- Webhook -------------------------------------------------------------------------
    def handle_webhook(
        self, body: bytes, signature: str | None, event_id: str | None
    ) -> WebhookAck:
        secret = self._settings.payment_gateway_webhook_secret.get_secret_value()
        if not self._settings.payments_enabled or not secret:
            # 503 so the gateway keeps retrying until the webhook secret is configured.
            raise ServiceUnavailableError(
                "Webhooks are not configured", log_message="webhook received but not configured"
            )
        if not rules.verify_webhook_signature(body, signature, secret):
            logger.warning("webhook with an invalid signature rejected")
            raise BadRequestError("Invalid signature")
        try:
            payload = json.loads(body)
            event = str(payload["event"])
        except (ValueError, KeyError, TypeError) as exc:
            raise BadRequestError("Malformed webhook") from exc

        outcome = {
            "payment.captured": "captured",
            "order.paid": "captured",
            "payment.failed": "failed",
        }.get(event)
        if outcome is None:
            return WebhookAck(status="ignored")
        try:
            entity: dict[str, Any] = payload["payload"]["payment"]["entity"]
            order_id = str(entity["order_id"])
            payment_id = str(entity["id"])
            amount = int(entity["amount"])
            currency = str(entity["currency"])
        except (KeyError, TypeError, ValueError) as exc:
            raise BadRequestError("Malformed webhook") from exc
        if outcome == "failed":
            failure = str(entity.get("error_description") or entity.get("error_code") or "") or None
        else:
            failure = None

        key = event_id.strip() if event_id and event_id.strip() else None
        if key is None:
            key = "body:" + hashlib.sha256(body).hexdigest()
        applied = self._payments.apply_event(
            provider=PROVIDER,
            order_id=order_id,
            payment_id=payment_id,
            outcome=outcome,
            amount_paise=amount,
            currency=currency,
            method=entity.get("method"),
            failure=failure,
            source="webhook",
            event_id=key,
            event_type=event,
            detail={"amount_paise": amount, "currency": currency, "event": event},
        )
        if applied.result in (
            "unknown_order",
            "amount_mismatch",
            "duplicate_payment",
            "paid_review",
        ):
            logger.warning("webhook %s for order %s: %s", event, order_id, applied.result)
        return WebhookAck(status=applied.result)

    # ---- Admin ---------------------------------------------------------------------------
    def admin_search(
        self,
        *,
        statuses: list[PaymentStatus] | None,
        booking_id: UUID | None,
        customer_id: UUID | None,
        needs_review: bool | None,
        date_from: date | None,
        date_to: date | None,
        query: str | None,
        limit: int,
        offset: int,
    ) -> AdminPaymentPage:
        if date_from and date_to and date_to < date_from:
            raise UnprocessableError("The end date must not be before the start date")
        tz = ZoneInfo(self._settings.business_timezone)
        created_from = datetime.combine(date_from, time.min, tzinfo=tz) if date_from else None
        created_before = (
            datetime.combine(date_to + timedelta(days=1), time.min, tzinfo=tz) if date_to else None
        )
        records, total = self._payments.search(
            statuses=statuses,
            booking_id=booking_id,
            customer_id=customer_id,
            needs_review=needs_review,
            created_from=created_from,
            created_before=created_before,
            query=query,
            limit=limit,
            offset=offset,
        )
        return AdminPaymentPage(
            items=[admin_payment_out(r) for r in records], total=total, limit=limit, offset=offset
        )

    def admin_get(self, payment_id: UUID) -> AdminPaymentDetail:
        record = self._payments.get(payment_id)
        if record is None:
            raise NotFoundError("Payment not found")
        return AdminPaymentDetail(
            **admin_payment_out(record).model_dump(),
            events=self._payments.events_for(record.id),
            refunds=self._refunds.list_for_payment(record.id) if self._refunds else [],
        )

    def admin_record_refund(
        self, admin: ProfileOut, payment_id: UUID, payload: RefundCreate
    ) -> AdminPaymentDetail:
        """Records a refund the admin already made in the gateway dashboard. The app moves no
        money and applies no refund rule of its own."""
        if self._refunds is None:
            raise ServiceUnavailableError("Refunds are not available")
        outcome = self._refunds.record(payment_id, payload.amount, payload.note, admin.id)
        match outcome.result:
            case "recorded":
                logger.info(
                    "admin %s recorded a refund of %s on payment %s",
                    admin.id,
                    payload.amount,
                    payment_id,
                )
            case "payment_not_found":
                raise NotFoundError("Payment not found")
            case "payment_not_successful":
                raise ConflictError("Only a payment that went through can be refunded")
            case "exceeds_payment":
                raise ConflictError("The refunds would add up to more than the payment")
            case other:
                raise ConflictError(f"The refund could not be recorded ({other})")
        return self.admin_get(payment_id)

    def admin_resolve_review(self, admin: ProfileOut, payment_id: UUID) -> AdminPaymentDetail:
        """The admin looked at a flagged payment and decided nothing more is needed."""
        if self._payments.resolve_review(payment_id) is None:
            raise NotFoundError("Payment not found")
        logger.info("admin %s resolved the review of payment %s", admin.id, payment_id)
        return self.admin_get(payment_id)
