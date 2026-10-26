"""Shared FastAPI dependencies (settings, data access, services)."""

from typing import Annotated

from fastapi import Depends, Request

from app.core.config import Settings
from app.core.security import TokenVerifier
from app.db.assignment_repository import AssignmentRepository, SupabaseAssignmentRepository
from app.db.auth_admin import AuthAdminGateway, SupabaseAuthAdminGateway
from app.db.availability_repository import (
    AvailabilityRepository,
    SupabaseAvailabilityRepository,
)
from app.db.booking_repository import BookingRepository, SupabaseBookingRepository
from app.db.catalog_repository import CatalogRepository, SupabaseCatalogRepository
from app.db.garage_settings_repository import (
    GarageSettingsRepository,
    SupabaseGarageSettingsRepository,
)
from app.db.payment_repository import PaymentRepository, SupabasePaymentRepository
from app.db.profile_repository import ProfileRepository, SupabaseProfileRepository
from app.db.service_area_repository import ServiceAreaRepository, SupabaseServiceAreaRepository
from app.db.supabase import get_supabase_admin_client
from app.db.tracking_repository import (
    NotificationRepository,
    SupabaseNotificationRepository,
    SupabaseTrackingRepository,
    TrackingRepository,
)
from app.services.assignment_service import AssignmentService
from app.services.availability_service import AvailabilityService
from app.services.booking_service import BookingService
from app.services.catalog_service import CatalogService
from app.services.driver_admin_service import DriverAdminService
from app.services.driver_work_service import DriverWorkService
from app.services.garage_settings_service import GarageSettingsService
from app.services.geocoding_gateway import GeocodingGateway, GoogleGeocodingGateway
from app.services.health_service import HealthService
from app.services.maps_service import MapsService, RateLimiter
from app.services.notification_service import NotificationService
from app.services.payment_gateway import PaymentGateway, RazorpayGateway
from app.services.payment_service import PaymentService
from app.services.profile_service import ProfileService
from app.services.service_area_service import ServiceAreaService


def get_app_settings(request: Request) -> Settings:
    """Settings of the running app (set once in `create_app`)."""
    return request.app.state.settings


SettingsDep = Annotated[Settings, Depends(get_app_settings)]


def get_token_verifier(request: Request) -> TokenVerifier:
    return request.app.state.token_verifier


TokenVerifierDep = Annotated[TokenVerifier, Depends(get_token_verifier)]


def get_health_service(settings: SettingsDep) -> HealthService:
    return HealthService(settings)


HealthServiceDep = Annotated[HealthService, Depends(get_health_service)]


def get_profile_repository(settings: SettingsDep) -> ProfileRepository:
    return SupabaseProfileRepository(get_supabase_admin_client(settings))


ProfileRepositoryDep = Annotated[ProfileRepository, Depends(get_profile_repository)]


def get_auth_admin_gateway(settings: SettingsDep) -> AuthAdminGateway:
    return SupabaseAuthAdminGateway(get_supabase_admin_client(settings))


AuthAdminGatewayDep = Annotated[AuthAdminGateway, Depends(get_auth_admin_gateway)]


def get_profile_service(profiles: ProfileRepositoryDep) -> ProfileService:
    return ProfileService(profiles)


ProfileServiceDep = Annotated[ProfileService, Depends(get_profile_service)]


def get_assignment_repository(settings: SettingsDep) -> AssignmentRepository:
    return SupabaseAssignmentRepository(get_supabase_admin_client(settings))


AssignmentRepositoryDep = Annotated[AssignmentRepository, Depends(get_assignment_repository)]


def get_driver_admin_service(
    profiles: ProfileRepositoryDep,
    auth_admin: AuthAdminGatewayDep,
    settings: SettingsDep,
    assignments: AssignmentRepositoryDep,
) -> DriverAdminService:
    return DriverAdminService(profiles, auth_admin, settings, assignments=assignments)


DriverAdminServiceDep = Annotated[DriverAdminService, Depends(get_driver_admin_service)]


def get_catalog_repository(settings: SettingsDep) -> CatalogRepository:
    return SupabaseCatalogRepository(get_supabase_admin_client(settings))


CatalogRepositoryDep = Annotated[CatalogRepository, Depends(get_catalog_repository)]


def get_service_area_repository(settings: SettingsDep) -> ServiceAreaRepository:
    return SupabaseServiceAreaRepository(get_supabase_admin_client(settings))


ServiceAreaRepositoryDep = Annotated[ServiceAreaRepository, Depends(get_service_area_repository)]


def get_garage_settings_repository(settings: SettingsDep) -> GarageSettingsRepository:
    return SupabaseGarageSettingsRepository(get_supabase_admin_client(settings))


GarageSettingsRepositoryDep = Annotated[
    GarageSettingsRepository, Depends(get_garage_settings_repository)
]


def get_garage_settings_service(
    repository: GarageSettingsRepositoryDep, settings: SettingsDep
) -> GarageSettingsService:
    return GarageSettingsService(repository, settings)


GarageSettingsServiceDep = Annotated[GarageSettingsService, Depends(get_garage_settings_service)]


def get_availability_repository(settings: SettingsDep) -> AvailabilityRepository:
    return SupabaseAvailabilityRepository(get_supabase_admin_client(settings))


AvailabilityRepositoryDep = Annotated[AvailabilityRepository, Depends(get_availability_repository)]


def get_catalog_service(catalog: CatalogRepositoryDep) -> CatalogService:
    return CatalogService(catalog)


CatalogServiceDep = Annotated[CatalogService, Depends(get_catalog_service)]


def get_service_area_service(areas: ServiceAreaRepositoryDep) -> ServiceAreaService:
    return ServiceAreaService(areas)


ServiceAreaServiceDep = Annotated[ServiceAreaService, Depends(get_service_area_service)]


def get_availability_service(
    repo: AvailabilityRepositoryDep, settings: SettingsDep
) -> AvailabilityService:
    return AvailabilityService(repo, settings)


AvailabilityServiceDep = Annotated[AvailabilityService, Depends(get_availability_service)]


def get_booking_repository(settings: SettingsDep) -> BookingRepository:
    return SupabaseBookingRepository(get_supabase_admin_client(settings))


BookingRepositoryDep = Annotated[BookingRepository, Depends(get_booking_repository)]


def get_payment_repository(settings: SettingsDep) -> PaymentRepository:
    return SupabasePaymentRepository(get_supabase_admin_client(settings))


PaymentRepositoryDep = Annotated[PaymentRepository, Depends(get_payment_repository)]


def get_payment_gateway(settings: SettingsDep) -> PaymentGateway | None:
    """None when payments are not configured (the endpoints then answer 503)."""
    if not settings.payments_enabled:
        return None
    return RazorpayGateway(settings)


PaymentGatewayDep = Annotated[PaymentGateway | None, Depends(get_payment_gateway)]


def get_tracking_repository(settings: SettingsDep) -> TrackingRepository:
    return SupabaseTrackingRepository(get_supabase_admin_client(settings))


TrackingRepositoryDep = Annotated[TrackingRepository, Depends(get_tracking_repository)]


def get_notification_repository(settings: SettingsDep) -> NotificationRepository:
    return SupabaseNotificationRepository(get_supabase_admin_client(settings))


NotificationRepositoryDep = Annotated[NotificationRepository, Depends(get_notification_repository)]


def get_notification_service(notifications: NotificationRepositoryDep) -> NotificationService:
    return NotificationService(notifications)


NotificationServiceDep = Annotated[NotificationService, Depends(get_notification_service)]


def get_booking_service(
    bookings: BookingRepositoryDep,
    catalog: CatalogRepositoryDep,
    areas: ServiceAreaRepositoryDep,
    availability: AvailabilityServiceDep,
    settings: SettingsDep,
    payments: PaymentRepositoryDep,
    assignments: AssignmentRepositoryDep,
    profiles: ProfileRepositoryDep,
    tracking: TrackingRepositoryDep,
) -> BookingService:
    return BookingService(
        bookings,
        catalog,
        areas,
        availability,
        settings,
        payments=payments,
        assignments=assignments,
        profiles=profiles,
        tracking=tracking,
    )


BookingServiceDep = Annotated[BookingService, Depends(get_booking_service)]


def get_payment_service(
    payments: PaymentRepositoryDep,
    bookings: BookingRepositoryDep,
    gateway: PaymentGatewayDep,
    settings: SettingsDep,
) -> PaymentService:
    return PaymentService(payments, bookings, gateway, settings)


PaymentServiceDep = Annotated[PaymentService, Depends(get_payment_service)]


def get_assignment_service(
    assignments: AssignmentRepositoryDep,
    bookings: BookingRepositoryDep,
    profiles: ProfileRepositoryDep,
    booking_service: BookingServiceDep,
) -> AssignmentService:
    return AssignmentService(assignments, bookings, profiles, booking_service)


AssignmentServiceDep = Annotated[AssignmentService, Depends(get_assignment_service)]


def get_driver_work_service(
    assignments: AssignmentRepositoryDep, bookings: BookingRepositoryDep
) -> DriverWorkService:
    return DriverWorkService(assignments, bookings)


DriverWorkServiceDep = Annotated[DriverWorkService, Depends(get_driver_work_service)]


def get_geocoding_gateway(settings: SettingsDep) -> GeocodingGateway | None:
    """None when no Google Maps key is configured (lookups then answer 503)."""
    if not settings.maps_enabled:
        return None
    return GoogleGeocodingGateway(settings)


GeocodingGatewayDep = Annotated[GeocodingGateway | None, Depends(get_geocoding_gateway)]


def get_maps_limiter(request: Request) -> RateLimiter:
    """One limiter per running app, so the counts survive from request to request."""
    limiter = getattr(request.app.state, "maps_limiter", None)
    if limiter is None:
        limiter = RateLimiter()
        request.app.state.maps_limiter = limiter
    return limiter


MapsLimiterDep = Annotated[RateLimiter, Depends(get_maps_limiter)]


def get_maps_service(
    gateway: GeocodingGatewayDep,
    areas: ServiceAreaServiceDep,
    limiter: MapsLimiterDep,
    settings: SettingsDep,
) -> MapsService:
    return MapsService(
        gateway, areas, limiter, requests_per_minute=settings.maps_requests_per_minute
    )


MapsServiceDep = Annotated[MapsService, Depends(get_maps_service)]
