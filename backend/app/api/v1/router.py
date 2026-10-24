"""Aggregates every v1 router. Add new resource routers here."""

from fastapi import APIRouter

from app.api.v1.endpoints import (
    admin_availability,
    admin_catalog,
    admin_drivers,
    admin_service_areas,
    assignments,
    bookings,
    catalog,
    health,
    notifications,
    payments,
    profiles,
    support,
)

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(profiles.router)
api_router.include_router(admin_drivers.router)
api_router.include_router(catalog.router)
api_router.include_router(admin_catalog.router)
api_router.include_router(admin_service_areas.router)
api_router.include_router(admin_availability.router)
api_router.include_router(bookings.router)
api_router.include_router(bookings.admin_router)
api_router.include_router(payments.router)
api_router.include_router(payments.webhook_router)
api_router.include_router(payments.admin_router)
api_router.include_router(assignments.admin_router)
api_router.include_router(assignments.driver_router)
api_router.include_router(notifications.router)
api_router.include_router(support.router)
