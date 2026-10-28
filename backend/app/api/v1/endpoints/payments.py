"""Payments: start and confirm a payment, the gateway webhook, and admin access.

Customers can only reach payments of their own bookings (anything else is a 404). The
webhook has no login: it is authenticated by the gateway's signature over the raw body.
Admins can read payments; nothing here lets anyone edit one.
"""

from datetime import date
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Header, Query, Request, status

from app.api.auth import AdminDep, CustomerDep
from app.api.deps import PaymentServiceDep
from app.domain.enums import PaymentStatus
from app.schemas.billing import RefundCreate
from app.schemas.payment import (
    AdminPaymentDetail,
    AdminPaymentPage,
    PaymentInitiated,
    PaymentOut,
    PaymentResult,
    PaymentVerify,
    WebhookAck,
)

router = APIRouter(tags=["Payments"])
webhook_router = APIRouter(tags=["Payments"])
admin_router = APIRouter(prefix="/admin/payments", tags=["Admin: payments"])

_AUTH = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Only customers can use this endpoint"},
}
_ADMIN = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Admin access required"},
}


@router.post(
    "/bookings/{booking_id}/payments",
    response_model=PaymentInitiated,
    status_code=status.HTTP_201_CREATED,
    summary="Start paying for a booking",
    description=(
        "Creates (or returns the still-open) gateway order for the booking's own total and "
        "the options for the checkout window. The amount is never taken from the app."
    ),
    responses={
        **_AUTH,
        404: {"description": "No such booking (or not yours)"},
        409: {"description": "Booking is not waiting for payment, or is already paid"},
        503: {"description": "Online payments are not available"},
    },
)
def start_payment(
    booking_id: UUID, customer: CustomerDep, service: PaymentServiceDep
) -> PaymentInitiated:
    return service.initiate(customer, booking_id)


@router.get(
    "/bookings/{booking_id}/payments",
    response_model=list[PaymentOut],
    summary="Payment attempts for my booking, newest first",
    responses={**_AUTH, 404: {"description": "No such booking (or not yours)"}},
)
def list_booking_payments(
    booking_id: UUID, customer: CustomerDep, service: PaymentServiceDep
) -> list[PaymentOut]:
    return service.list_for_booking(customer, booking_id)


@router.get(
    "/payments/{payment_id}",
    response_model=PaymentOut,
    summary="One of my payments",
    responses={**_AUTH, 404: {"description": "No such payment (or not yours)"}},
)
def get_payment(payment_id: UUID, customer: CustomerDep, service: PaymentServiceDep) -> PaymentOut:
    return service.get(customer, payment_id)


@router.post(
    "/payments/{payment_id}/verify",
    response_model=PaymentResult,
    summary="Report the checkout result so the server can verify it",
    description=(
        "The signature is recomputed with the secret key and the payment is confirmed with "
        "the gateway before anything is marked paid. Safe to call repeatedly."
    ),
    responses={
        **_AUTH,
        404: {"description": "No such payment (or not yours)"},
        422: {"description": "Signature invalid or payment could not be verified"},
        503: {"description": "Online payments are not available"},
    },
)
def verify_payment(
    payment_id: UUID,
    payload: PaymentVerify,
    customer: CustomerDep,
    service: PaymentServiceDep,
) -> PaymentResult:
    return service.verify(customer, payment_id, payload)


@router.post(
    "/payments/{payment_id}/cancel",
    response_model=PaymentOut,
    summary="The customer closed the checkout without paying",
    responses={**_AUTH, 404: {"description": "No such payment (or not yours)"}},
)
def cancel_payment(
    payment_id: UUID, customer: CustomerDep, service: PaymentServiceDep
) -> PaymentOut:
    return service.cancel(customer, payment_id)


@webhook_router.post(
    "/webhooks/razorpay",
    response_model=WebhookAck,
    summary="Razorpay webhook",
    description="Called by Razorpay. Authenticated by the X-Razorpay-Signature header.",
    responses={
        400: {"description": "Invalid signature or malformed body"},
        503: {"description": "Webhooks are not configured"},
    },
)
async def razorpay_webhook(
    request: Request,
    service: PaymentServiceDep,
    x_razorpay_signature: Annotated[str | None, Header()] = None,
    x_razorpay_event_id: Annotated[str | None, Header()] = None,
) -> WebhookAck:
    body = await request.body()
    return service.handle_webhook(body, x_razorpay_signature, x_razorpay_event_id)


# ---- Admin -----------------------------------------------------------------------------


@admin_router.get(
    "",
    response_model=AdminPaymentPage,
    summary="Search and filter payments",
    responses=_ADMIN,
)
def admin_list_payments(
    _admin: AdminDep,
    service: PaymentServiceDep,
    payment_status: Annotated[list[PaymentStatus] | None, Query(alias="status")] = None,
    booking_id: UUID | None = None,
    customer_id: UUID | None = None,
    needs_review: Annotated[
        bool | None, Query(description="Only payments that need a human (refund, mismatch)")
    ] = None,
    date_from: Annotated[
        date | None, Query(description="Created on or after (business time)")
    ] = None,
    date_to: Annotated[
        date | None, Query(description="Created on or before (business time)")
    ] = None,
    q: Annotated[
        str | None,
        Query(max_length=60, description="Gateway order/payment id or booking number (FF-000123)"),
    ] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 25,
    offset: Annotated[int, Query(ge=0, le=100_000)] = 0,
) -> AdminPaymentPage:
    return service.admin_search(
        statuses=payment_status,
        booking_id=booking_id,
        customer_id=customer_id,
        needs_review=needs_review,
        date_from=date_from,
        date_to=date_to,
        query=q,
        limit=limit,
        offset=offset,
    )


@admin_router.get(
    "/{payment_id}",
    response_model=AdminPaymentDetail,
    summary="Payment details with the gateway event log",
    responses={**_ADMIN, 404: {"description": "No such payment"}},
)
def admin_get_payment(
    payment_id: UUID, _admin: AdminDep, service: PaymentServiceDep
) -> AdminPaymentDetail:
    return service.admin_get(payment_id)


@admin_router.post(
    "/{payment_id}/refunds",
    response_model=AdminPaymentDetail,
    status_code=status.HTTP_201_CREATED,
    summary="Record a refund you already made in the payment gateway's dashboard",
    description=(
        "This application moves no money and applies no refund rule: an admin decides, refunds "
        "in the gateway dashboard, then records it here so the customer's receipt shows it."
    ),
    responses={
        **_ADMIN,
        404: {"description": "No such payment"},
        409: {"description": "Payment not successful, or refunds would exceed the payment"},
    },
)
def admin_record_refund(
    payment_id: UUID, payload: RefundCreate, admin: AdminDep, service: PaymentServiceDep
) -> AdminPaymentDetail:
    return service.admin_record_refund(admin, payment_id, payload)


@admin_router.post(
    "/{payment_id}/resolve-review",
    response_model=AdminPaymentDetail,
    summary="Mark a flagged payment as dealt with (no refund needed)",
    responses={**_ADMIN, 404: {"description": "No such payment"}},
)
def admin_resolve_review(
    payment_id: UUID, admin: AdminDep, service: PaymentServiceDep
) -> AdminPaymentDetail:
    return service.admin_resolve_review(admin, payment_id)
