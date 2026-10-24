"""FastAPI application factory.

Run locally from the `backend/` folder:
    uvicorn app.main:app --reload
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import Settings, get_settings
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging
from app.core.security import TokenVerifier

OPENAPI_TAGS = [
    {"name": "Health", "description": "Liveness and readiness probes."},
    {"name": "Profiles", "description": "The signed-in user's own profile."},
    {"name": "Admin: Drivers", "description": "Admin-only driver account management."},
    {
        "name": "Catalog",
        "description": "Browse active services, check PIN codes and slot availability.",
    },
    {"name": "Admin: Services", "description": "Admin-only services, packages and charges."},
    {"name": "Admin: Service areas", "description": "Admin-only serviceable PIN codes."},
    {"name": "Admin: Availability", "description": "Admin-only time slots and closures."},
    {"name": "Bookings", "description": "Customers create, view, change and cancel bookings."},
    {"name": "Admin: bookings", "description": "Admin-only booking search, details and status."},
    {"name": "Payments", "description": "Pay for a booking (Razorpay) and the payment webhook."},
    {"name": "Admin: payments", "description": "Admin-only, read-only payment records."},
    {
        "name": "Admin: assignments",
        "description": "Admin-only: assign, change or remove a booking's driver.",
    },
    {
        "name": "Notifications",
        "description": "A customer's in-app booking and payment notifications.",
    },
    {
        "name": "Support",
        "description": "The garage's configurable contact details (any signed-in user).",
    },
    {
        "name": "Driver",
        "description": "A driver's own assigned bookings and status steps (drivers only).",
    },
]


def create_app(
    settings: Settings | None = None,
    token_verifier: TokenVerifier | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description="Backend API for the F&F Two Wheeler Garage doorstep servicing app.",
        debug=settings.debug,
        openapi_tags=OPENAPI_TAGS,
        docs_url="/docs" if settings.enable_docs else None,
        redoc_url="/redoc" if settings.enable_docs else None,
        openapi_url="/openapi.json" if settings.enable_docs else None,
    )
    app.state.settings = settings
    app.state.token_verifier = token_verifier or TokenVerifier(settings)
    register_exception_handlers(app)

    # Auth uses a bearer token in the Authorization header, not cookies, so
    # credentials are not needed (which also keeps '*' usable in development).
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_origin_regex=settings.cors_origin_regex,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Accept"],
    )

    app.include_router(api_router, prefix=settings.api_v1_prefix)
    return app


app = create_app()
