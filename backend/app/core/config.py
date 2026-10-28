"""Application settings, read from environment variables and an optional `.env` file.

Secrets are `SecretStr`, so they are masked in logs, `repr()` and tracebacks.
Call `.get_secret_value()` only at the point of use.
"""

import re
from decimal import Decimal
from functools import lru_cache
from typing import Annotated, Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

_DOMAIN_LABEL = r"[a-z0-9]([a-z0-9-]*[a-z0-9])?"
_DOMAIN_PATTERN = re.compile(rf"{_DOMAIN_LABEL}(\.{_DOMAIN_LABEL})+")


# What backend/.env.example ships with; treated as "no key configured".
MAPS_KEY_PLACEHOLDER = "your_server_side_maps_key"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- App ---------------------------------------------------------------
    app_name: str = "F&F Two Wheeler Garage API"
    app_version: str = "0.1.0"
    app_env: Literal["development", "test", "staging", "production"] = "development"
    debug: bool = False
    log_level: str = "INFO"
    api_v1_prefix: str = "/api/v1"
    enable_docs: bool = True
    # Comma-separated in the environment (NoDecode stops pydantic-settings from
    # expecting JSON); parsed by the validator below.
    cors_origins: Annotated[list[str], NoDecode] = Field(default_factory=list)
    # Also allow any http://localhost / 127.0.0.1 port (Flutter Web picks a random
    # one in development). Only applies when APP_ENV=development.
    cors_allow_local_dev_origins: bool = True

    # --- Supabase ----------------------------------------------------------
    supabase_url: str = ""
    supabase_anon_key: SecretStr = SecretStr("")
    # Bypasses Row Level Security. Backend only, never shipped to Flutter.
    supabase_service_role_key: SecretStr = SecretStr("")
    # Only for projects that still sign tokens with the legacy shared HS256
    # secret. Projects with asymmetric signing keys leave this blank; tokens are
    # then verified against the project's public JWKS.
    supabase_jwt_secret: SecretStr = SecretStr("")
    supabase_jwt_audience: str = "authenticated"

    # --- Driver accounts ---------------------------------------------------
    # Drivers sign in with an ID + password. Supabase Auth needs an email, so
    # each driver gets <driver_id>@<this domain>. Must match
    # public.driver_email_domain() in the database and the Flutter app.
    driver_email_domain: str = "drivers.ffgarage.invalid"

    # --- Payment gateway (Phase 5) -----------------------------------------
    # "" turns online payments off (bookings still work); "razorpay" turns them on.
    payment_gateway_provider: str = ""
    # Razorpay key id: rzp_test_... (sandbox) or rzp_live_... (real money). Not secret,
    # but still backend configuration; the app receives it with each checkout.
    payment_gateway_key_id: str = ""
    payment_gateway_key_secret: SecretStr = SecretStr("")
    # Secret configured for the webhook in the Razorpay dashboard (not the API secret).
    payment_gateway_webhook_secret: SecretStr = SecretStr("")
    payment_gateway_base_url: str = "https://api.razorpay.com/v1"
    payment_gateway_timeout_seconds: float = Field(default=10.0, gt=0, le=60)
    # Shown in the Razorpay checkout window.
    payment_checkout_name: str = "F&F Two Wheeler Garage"
    # An unfinished payment attempt younger than this is reused instead of creating
    # a second gateway order.
    payment_attempt_reuse_minutes: int = Field(default=30, ge=1, le=1440)
    # Share of the estimated booking total collected when the customer books. The rest
    # (plus any extra charges the customer approved) is paid after the service.
    advance_payment_percent: Decimal = Field(default=Decimal("20"), ge=0, le=100)

    # --- Availability (Phase 3) ---------------------------------------------
    # Wall-clock time in which slots, dates and "today" are interpreted.
    business_timezone: str = "Asia/Kolkata"
    # How many days ahead customers may book (today counts as day 0).
    booking_window_days: int = Field(default=30, ge=1, le=365)
    # A slot stops being bookable this many minutes before it starts.
    booking_lead_minutes: int = Field(default=120, ge=0, le=1440)
    # Customers may cancel or change a confirmed booking until this many hours before
    # the slot starts. (A booking that is still pending payment is always cancellable.)
    booking_cancel_cutoff_hours: int = Field(default=4, ge=0, le=168)

    # --- Garage contact / support (Phase 8) ------------------------------------
    # Shown on the app's Help & support screen. All optional: anything left empty is
    # simply not offered. Change them here, no app release needed.
    garage_name: str = "F&F Two Wheeler Garage"
    garage_phone: str = ""
    garage_whatsapp: str = ""
    garage_email: str = ""
    garage_address: str = ""
    garage_hours: str = ""

    # --- Google Maps (server side) ---------------------------------------------
    # Key for the Geocoding API, called ONLY by this backend (address lookup, reverse
    # geocoding, PIN-code extraction). Restrict it in Google Cloud to "Geocoding API"
    # and to this server's IP address(es). It is NOT what draws maps in the app: the
    # Flutter app needs its own, separately restricted, Maps SDK keys (see README).
    # Empty = address lookup is switched off; booking still works by typing.
    google_maps_api_key: SecretStr = SecretStr("")
    google_maps_base_url: str = "https://maps.googleapis.com/maps/api"
    google_maps_timeout_seconds: float = Field(default=5.0, gt=0, le=30)
    # Lookups one signed-in customer may make per minute (protects the Google quota).
    maps_requests_per_minute: int = Field(default=30, ge=1, le=600)

    # --- Validation --------------------------------------------------------
    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_cors_origins(cls, value: object) -> object:
        if isinstance(value, str):
            value = value.split(",")
        if isinstance(value, (list, tuple)):
            return [str(item).strip().rstrip("/") for item in value if str(item).strip()]
        return value

    @field_validator("supabase_url")
    @classmethod
    def _validate_supabase_url(cls, value: str) -> str:
        value = value.strip().rstrip("/")
        if value and not value.startswith(("http://", "https://")):
            raise ValueError("SUPABASE_URL must start with http:// or https://")
        return value

    @field_validator("business_timezone")
    @classmethod
    def _validate_timezone(cls, value: str) -> str:
        value = value.strip()
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise ValueError("BUSINESS_TIMEZONE must be a valid IANA time zone") from exc
        return value

    @field_validator("driver_email_domain")
    @classmethod
    def _validate_driver_email_domain(cls, value: str) -> str:
        value = value.strip().lower()
        if not _DOMAIN_PATTERN.fullmatch(value):
            raise ValueError("DRIVER_EMAIL_DOMAIN must be a valid domain name")
        return value

    @field_validator("api_v1_prefix")
    @classmethod
    def _validate_prefix(cls, value: str) -> str:
        if not value.startswith("/") or value.endswith("/"):
            raise ValueError("API_V1_PREFIX must start with '/' and must not end with '/'")
        return value

    @field_validator("payment_gateway_provider")
    @classmethod
    def _validate_payment_provider(cls, value: str) -> str:
        value = value.strip().lower()
        if value not in ("", "razorpay"):
            raise ValueError("PAYMENT_GATEWAY_PROVIDER must be empty or 'razorpay'")
        return value

    @field_validator("payment_gateway_key_id")
    @classmethod
    def _validate_payment_key_id(cls, value: str) -> str:
        value = value.strip()
        if value and not re.fullmatch(r"rzp_(test|live)_[A-Za-z0-9]+", value):
            raise ValueError("PAYMENT_GATEWAY_KEY_ID must look like rzp_test_... or rzp_live_...")
        return value

    @field_validator("google_maps_base_url")
    @classmethod
    def _validate_maps_base_url(cls, value: str) -> str:
        value = value.strip().rstrip("/")
        if not value.startswith("https://") and not value.startswith("http://127.0.0.1"):
            raise ValueError("GOOGLE_MAPS_BASE_URL must be an https:// URL")
        return value

    @field_validator("payment_gateway_base_url")
    @classmethod
    def _validate_payment_base_url(cls, value: str) -> str:
        value = value.strip().rstrip("/")
        if not value.startswith("https://") and not value.startswith("http://127.0.0.1"):
            raise ValueError("PAYMENT_GATEWAY_BASE_URL must be an https:// URL")
        return value

    @model_validator(mode="after")
    def _payment_guards(self) -> "Settings":
        if self.payment_gateway_provider == "razorpay":
            if (
                not self.payment_gateway_key_id
                or not self.payment_gateway_key_secret.get_secret_value()
            ):
                raise ValueError(
                    "PAYMENT_GATEWAY_KEY_ID and PAYMENT_GATEWAY_KEY_SECRET are required "
                    "when PAYMENT_GATEWAY_PROVIDER=razorpay"
                )
            if (
                self.app_env == "production"
                and not self.payment_gateway_webhook_secret.get_secret_value()
            ):
                raise ValueError(
                    "PAYMENT_GATEWAY_WEBHOOK_SECRET is required when APP_ENV=production "
                    "and payments are enabled"
                )
        return self

    @model_validator(mode="after")
    def _production_guards(self) -> "Settings":
        if self.app_env == "production":
            if "*" in self.cors_origins:
                raise ValueError("CORS_ORIGINS must not contain '*' when APP_ENV=production")
            if not self.supabase_configured:
                raise ValueError(
                    "SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are "
                    "required when APP_ENV=production"
                )
        return self

    # --- Helpers -----------------------------------------------------------
    @property
    def supabase_configured(self) -> bool:
        return bool(
            self.supabase_url
            and self.supabase_anon_key.get_secret_value()
            and self.supabase_service_role_key.get_secret_value()
        )

    @property
    def cors_origin_regex(self) -> str | None:
        """Regex for local dev origins; None unless enabled and APP_ENV=development."""
        if self.cors_allow_local_dev_origins and self.app_env == "development":
            return r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"
        return None

    @property
    def maps_enabled(self) -> bool:
        key = self.google_maps_api_key.get_secret_value().strip()
        # The value copied straight from .env.example counts as "not set up yet".
        return bool(key) and key != MAPS_KEY_PLACEHOLDER

    @property
    def payments_enabled(self) -> bool:
        return (
            self.payment_gateway_provider == "razorpay"
            and bool(self.payment_gateway_key_id)
            and bool(self.payment_gateway_key_secret.get_secret_value())
        )

    @property
    def payments_live(self) -> bool:
        """True when real money is involved (live keys), False for the sandbox."""
        return self.payment_gateway_key_id.startswith("rzp_live_")

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
