"""Shared wiring for the Phase 3 API tests."""

from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from app.api.deps import (
    get_assignment_repository,
    get_availability_repository,
    get_availability_service,
    get_booking_repository,
    get_booking_service,
    get_catalog_repository,
    get_coupon_repository,
    get_extra_request_repository,
    get_garage_settings_repository,
    get_image_storage,
    get_notification_repository,
    get_payment_gateway,
    get_payment_repository,
    get_profile_repository,
    get_refund_repository,
    get_service_area_repository,
    get_tracking_repository,
    get_vehicle_repository,
)
from app.domain.enums import UserRole
from app.main import create_app
from app.services.availability_service import AvailabilityService
from app.services.booking_service import BookingService
from app.services.coupon_service import CouponService
from tests.conftest import CONFIGURED_SUPABASE, make_settings
from tests.fakes import FakeProfileRepository, make_profile
from tests.fakes_assignment import FakeAssignmentRepository
from tests.fakes_billing import FakeCoupons, FakeExtraRequests, FakeRefunds
from tests.fakes_booking import FakeBookingRepository
from tests.fakes_catalog import (
    FakeAvailabilityRepository,
    FakeCatalogRepository,
    FakeImageStorage,
    FakeServiceAreaRepository,
)
from tests.fakes_garage import FakeGarageSettings
from tests.fakes_payment import FakeGateway, FakePaymentRepository
from tests.fakes_tracking import FakeTracking
from tests.fakes_vehicles import FakeVehicles
from tests.jwt_helpers import HS256_SECRET, make_token

SETTINGS = make_settings(**CONFIGURED_SUPABASE, supabase_jwt_secret=HS256_SECRET)
ISSUER = f"{SETTINGS.supabase_url}/auth/v1"
IST = ZoneInfo("Asia/Kolkata")
# Monday 19 Oct 2026, 08:00 in India
NOW = datetime(2026, 10, 19, 8, 0, tzinfo=IST)


def headers_for(profile) -> dict[str, str]:
    token = make_token(HS256_SECRET, algorithm="HS256", issuer=ISSUER, sub=str(profile.id))
    return {"Authorization": f"Bearer {token}"}


class Ctx:
    """An app with in-memory repositories and one user of each role."""

    def __init__(self, settings=None) -> None:
        self.settings = settings or SETTINGS
        self.admin = make_profile(UserRole.ADMIN)
        self.customer = make_profile(UserRole.CUSTOMER)
        self.driver = make_profile(UserRole.DRIVER)
        self.profiles = FakeProfileRepository(self.admin, self.customer, self.driver)
        self.catalog = FakeCatalogRepository()
        self.storage = FakeImageStorage()
        self.areas = FakeServiceAreaRepository()
        self.availability = FakeAvailabilityRepository()
        self.bookings = FakeBookingRepository(self.availability)
        self.catalog.bookings = self.bookings
        self.payments = FakePaymentRepository(self.bookings)
        self.gateway = FakeGateway()
        self.coupons = FakeCoupons()
        self.extras = FakeExtraRequests()
        self.refunds = FakeRefunds(self.payments)
        self.bookings.coupons = self.coupons
        self.bookings.on_cancelled.append(self.extras.withdraw_open)
        self.assignments = FakeAssignmentRepository(self.bookings, self.profiles, self.payments)
        self.assignments.extras = self.extras
        self.garage = FakeGarageSettings()
        self.vehicles = FakeVehicles()
        self.tracking = FakeTracking(self.bookings, self.assignments, self.payments, self.profiles)

        app = create_app(self.settings)
        app.dependency_overrides[get_profile_repository] = lambda: self.profiles
        app.dependency_overrides[get_catalog_repository] = lambda: self.catalog
        app.dependency_overrides[get_image_storage] = lambda: self.storage
        app.dependency_overrides[get_garage_settings_repository] = lambda: self.garage
        app.dependency_overrides[get_vehicle_repository] = lambda: self.vehicles
        app.dependency_overrides[get_service_area_repository] = lambda: self.areas
        app.dependency_overrides[get_availability_repository] = lambda: self.availability
        app.dependency_overrides[get_availability_service] = lambda: AvailabilityService(
            self.availability, self.settings, clock=lambda tz: NOW.astimezone(tz)
        )
        self.clock = lambda tz: NOW.astimezone(tz)
        app.dependency_overrides[get_booking_repository] = lambda: self.bookings
        app.dependency_overrides[get_payment_repository] = lambda: self.payments
        app.dependency_overrides[get_coupon_repository] = lambda: self.coupons
        app.dependency_overrides[get_extra_request_repository] = lambda: self.extras
        app.dependency_overrides[get_refund_repository] = lambda: self.refunds
        app.dependency_overrides[get_assignment_repository] = lambda: self.assignments
        app.dependency_overrides[get_tracking_repository] = lambda: self.tracking
        app.dependency_overrides[get_notification_repository] = lambda: self.tracking
        app.dependency_overrides[get_payment_gateway] = lambda: (
            self.gateway if self.settings.payments_enabled else None
        )
        app.dependency_overrides[get_booking_service] = lambda: BookingService(
            self.bookings,
            self.catalog,
            self.areas,
            AvailabilityService(self.availability, self.settings, clock=self.clock),
            self.settings,
            clock=self.clock,
            payments=self.payments,
            assignments=self.assignments,
            profiles=self.profiles,
            tracking=self.tracking,
            vehicles=self.vehicles,
            coupons=CouponService(self.coupons),
            extras=self.extras,
        )
        self.client = TestClient(app)
        self.as_admin = headers_for(self.admin)
        self.as_customer = headers_for(self.customer)
        self.as_driver = headers_for(self.driver)

    def service_with_package(self, name="General Service", vehicle="scooter", **pkg):
        """Create an active service with one active package through the admin API."""
        service = self.client.post(
            "/api/v1/admin/services",
            headers=self.as_admin,
            json={"name": name, "vehicle_type": vehicle},
        ).json()
        package = self.client.post(
            f"/api/v1/admin/services/{service['id']}/packages",
            headers=self.as_admin,
            json={"name": "Basic", "price": "499.00", **pkg},
        ).json()
        return service, package


@pytest.fixture
def ctx() -> Ctx:
    return Ctx()
