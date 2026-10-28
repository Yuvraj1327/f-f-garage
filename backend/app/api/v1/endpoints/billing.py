"""The bill, extra charges that need approval, and coupons.

Customers see the bill of their own bookings and answer extra charge requests. Drivers and
admins raise requests while a service is in progress. Admins manage coupons. A booking or
request that is not yours looks exactly like a missing one (404).
"""

from uuid import UUID

from fastapi import APIRouter, status

from app.api.auth import AdminDep, CustomerDep, DriverDep
from app.api.deps import (
    BillingServiceDep,
    CouponServiceDep,
    ExtraRequestServiceDep,
)
from app.schemas.billing import BillOut, ExtraRequestCreate, ExtraRequestOut
from app.schemas.coupon import CouponCreate, CouponOut, CouponUpdate

router = APIRouter(tags=["Billing"])
driver_router = APIRouter(prefix="/driver", tags=["Driver"])
admin_router = APIRouter(prefix="/admin", tags=["Admin: billing"])

_CUSTOMER = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Only customers can use this endpoint"},
    404: {"description": "No such booking (or not yours)"},
}
_DRIVER = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Only drivers can use this endpoint"},
    404: {"description": "Not one of your bookings"},
}
_ADMIN = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Admin access required"},
}
_RAISE = {
    409: {"description": "The service is not in progress, or too many requests"},
}
_ANSWER = {
    409: {"description": "Already answered, withdrawn, or the service is no longer in progress"}
}


# ---- Customer ------------------------------------------------------------------------


@router.get(
    "/bookings/{booking_id}/bill",
    response_model=BillOut,
    summary="The bill: estimate, approved extras, advance, balance, receipts and refunds",
    responses=_CUSTOMER,
)
def my_bill(booking_id: UUID, customer: CustomerDep, service: BillingServiceDep) -> BillOut:
    return service.for_customer(customer, booking_id)


@router.get(
    "/bookings/{booking_id}/extras",
    response_model=list[ExtraRequestOut],
    summary="Extra charge requests on my booking, oldest first",
    responses=_CUSTOMER,
)
def my_extras(
    booking_id: UUID, customer: CustomerDep, service: ExtraRequestServiceDep
) -> list[ExtraRequestOut]:
    return service.list_for_customer(customer, booking_id)


@router.post(
    "/bookings/{booking_id}/extras/{extra_id}/approve",
    response_model=ExtraRequestOut,
    summary="Approve an extra charge (it is added to the final bill)",
    responses={**_CUSTOMER, **_ANSWER},
)
def approve_extra(
    booking_id: UUID, extra_id: UUID, customer: CustomerDep, service: ExtraRequestServiceDep
) -> ExtraRequestOut:
    return service.decide(customer, booking_id, extra_id, approve=True)


@router.post(
    "/bookings/{booking_id}/extras/{extra_id}/decline",
    response_model=ExtraRequestOut,
    summary="Decline an extra charge (nothing is added to the bill)",
    responses={**_CUSTOMER, **_ANSWER},
)
def decline_extra(
    booking_id: UUID, extra_id: UUID, customer: CustomerDep, service: ExtraRequestServiceDep
) -> ExtraRequestOut:
    return service.decide(customer, booking_id, extra_id, approve=False)


# ---- Driver --------------------------------------------------------------------------


@driver_router.get(
    "/bookings/{booking_id}/extras",
    response_model=list[ExtraRequestOut],
    summary="Extra charge requests on my booking",
    responses=_DRIVER,
)
def driver_extras(
    booking_id: UUID, driver: DriverDep, service: ExtraRequestServiceDep
) -> list[ExtraRequestOut]:
    return service.list_for_driver(driver, booking_id)


@driver_router.post(
    "/bookings/{booking_id}/extras",
    response_model=ExtraRequestOut,
    status_code=status.HTTP_201_CREATED,
    summary="Ask the customer to approve an extra part or repair",
    responses={**_DRIVER, **_RAISE},
)
def driver_request_extra(
    booking_id: UUID,
    payload: ExtraRequestCreate,
    driver: DriverDep,
    service: ExtraRequestServiceDep,
) -> ExtraRequestOut:
    """Only while the service is in progress. Nothing is billed until the customer approves."""
    return service.request_as_driver(driver, booking_id, payload)


@driver_router.post(
    "/bookings/{booking_id}/extras/{extra_id}/withdraw",
    response_model=ExtraRequestOut,
    summary="Take back a request the customer has not answered",
    responses={**_DRIVER, **_ANSWER},
)
def driver_withdraw_extra(
    booking_id: UUID, extra_id: UUID, driver: DriverDep, service: ExtraRequestServiceDep
) -> ExtraRequestOut:
    return service.withdraw_as_driver(driver, booking_id, extra_id)


# ---- Admin: bill and extras -------------------------------------------------------------


@admin_router.get(
    "/bookings/{booking_id}/bill",
    response_model=BillOut,
    summary="The bill of any booking",
    responses={**_ADMIN, 404: {"description": "No such booking"}},
)
def admin_bill(booking_id: UUID, _admin: AdminDep, service: BillingServiceDep) -> BillOut:
    return service.for_admin(booking_id)


@admin_router.get(
    "/bookings/{booking_id}/extras",
    response_model=list[ExtraRequestOut],
    summary="Extra charge requests on a booking",
    responses={**_ADMIN, 404: {"description": "No such booking"}},
)
def admin_extras(
    booking_id: UUID, _admin: AdminDep, service: ExtraRequestServiceDep
) -> list[ExtraRequestOut]:
    return service.list_for_admin(booking_id)


@admin_router.post(
    "/bookings/{booking_id}/extras",
    response_model=ExtraRequestOut,
    status_code=status.HTTP_201_CREATED,
    summary="Ask the customer to approve an extra part or repair",
    responses={**_ADMIN, **_RAISE, 404: {"description": "No such booking"}},
)
def admin_request_extra(
    booking_id: UUID,
    payload: ExtraRequestCreate,
    admin: AdminDep,
    service: ExtraRequestServiceDep,
) -> ExtraRequestOut:
    return service.request_as_admin(admin, booking_id, payload)


@admin_router.post(
    "/bookings/{booking_id}/extras/{extra_id}/withdraw",
    response_model=ExtraRequestOut,
    summary="Withdraw a request the customer has not answered",
    responses={**_ADMIN, **_ANSWER, 404: {"description": "No such booking or request"}},
)
def admin_withdraw_extra(
    booking_id: UUID, extra_id: UUID, _admin: AdminDep, service: ExtraRequestServiceDep
) -> ExtraRequestOut:
    return service.withdraw_as_admin(booking_id, extra_id)


# ---- Admin: coupons -------------------------------------------------------------------


@admin_router.get(
    "/coupons", response_model=list[CouponOut], summary="All coupons", responses=_ADMIN
)
def list_coupons(_admin: AdminDep, service: CouponServiceDep) -> list[CouponOut]:
    return service.list_all()


@admin_router.post(
    "/coupons",
    response_model=CouponOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a coupon",
    responses={**_ADMIN, 409: {"description": "That code already exists"}},
)
def create_coupon(payload: CouponCreate, admin: AdminDep, service: CouponServiceDep) -> CouponOut:
    return service.create(admin, payload)


@admin_router.patch(
    "/coupons/{coupon_id}",
    response_model=CouponOut,
    summary="Change or switch off a coupon",
    responses={**_ADMIN, 404: {"description": "No such coupon"}},
)
def update_coupon(
    coupon_id: UUID, payload: CouponUpdate, admin: AdminDep, service: CouponServiceDep
) -> CouponOut:
    return service.update(admin, coupon_id, payload)
