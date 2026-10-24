"""Verification of Supabase access tokens (JWTs).

Supabase signs user tokens either with asymmetric keys (ES256 / RS256 / EdDSA,
public keys published at `<SUPABASE_URL>/auth/v1/.well-known/jwks.json`) or,
on older projects, with a shared HS256 secret. Both are supported; the
algorithm is chosen from a fixed allow-list, never trusted blindly from the
token header (no `none`, and an HS256 token can only ever be checked against
the configured secret, never against a public key).

A verified token proves WHO the caller is. What they may DO is decided from the
`profiles` table, never from claims inside the token.
"""

import logging
import ssl
import uuid
from dataclasses import dataclass
from typing import Any, Protocol

import certifi
import jwt
from jwt import PyJWKClient
from jwt.exceptions import PyJWKClientConnectionError, PyJWKClientError

from app.core.config import Settings
from app.core.errors import ServiceUnavailableError

logger = logging.getLogger(__name__)

ASYMMETRIC_ALGORITHMS = frozenset({"RS256", "ES256", "EdDSA"})
HS256 = "HS256"
CLOCK_SKEW_SECONDS = 10


class TokenError(Exception):
    """The token is missing, malformed, expired or otherwise not acceptable (HTTP 401)."""


class _SigningKey(Protocol):
    key: Any


class JwksClient(Protocol):
    def get_signing_key_from_jwt(self, token: str) -> _SigningKey: ...


@dataclass(frozen=True)
class TokenClaims:
    user_id: str
    email: str | None


class TokenVerifier:
    def __init__(self, settings: Settings, jwks_client: JwksClient | None = None) -> None:
        self._settings = settings
        self._jwks_client = jwks_client

    @property
    def _issuer(self) -> str:
        return f"{self._settings.supabase_url}/auth/v1"

    def _get_jwks_client(self) -> JwksClient:
        if self._jwks_client is None:
            self._jwks_client = PyJWKClient(
                f"{self._issuer}/.well-known/jwks.json",
                cache_keys=True,
                timeout=5,
                # Use certifi's CA bundle: some Python installs (e.g. python.org
                # builds on macOS) ship no system CAs and fail TLS verification.
                ssl_context=ssl.create_default_context(cafile=certifi.where()),
            )
        return self._jwks_client

    def verify(self, token: str) -> TokenClaims:
        if not self._settings.supabase_url:
            raise ServiceUnavailableError("Authentication is not configured")

        try:
            algorithm = jwt.get_unverified_header(token).get("alg")
        except jwt.InvalidTokenError as exc:
            raise TokenError("Malformed token") from exc

        key = self._signing_key(token, algorithm)

        try:
            payload = jwt.decode(
                token,
                key,
                algorithms=[algorithm],
                audience=self._settings.supabase_jwt_audience,
                issuer=self._issuer,
                leeway=CLOCK_SKEW_SECONDS,
                options={"require": ["exp", "sub", "aud", "iss"]},
            )
        except jwt.ExpiredSignatureError as exc:
            raise TokenError("Token has expired") from exc
        except jwt.InvalidTokenError as exc:
            raise TokenError("Invalid token") from exc

        # Supabase also issues tokens for the anon/service roles and for
        # anonymous sign-ins; none of those are acceptable here.
        if payload.get("role") != "authenticated":
            raise TokenError("Not a user token")
        if payload.get("is_anonymous") is True:
            raise TokenError("Anonymous users are not supported")
        try:
            user_id = str(uuid.UUID(str(payload["sub"])))
        except ValueError as exc:
            raise TokenError("Invalid token subject") from exc

        email = payload.get("email")
        return TokenClaims(user_id=user_id, email=email if isinstance(email, str) else None)

    def _signing_key(self, token: str, algorithm: object) -> Any:
        if algorithm == HS256:
            secret = self._settings.supabase_jwt_secret.get_secret_value()
            if not secret:
                raise TokenError("Unsupported token algorithm")
            return secret

        if algorithm in ASYMMETRIC_ALGORITHMS:
            try:
                return self._get_jwks_client().get_signing_key_from_jwt(token).key
            except PyJWKClientConnectionError as exc:
                raise ServiceUnavailableError("Authentication keys are unavailable") from exc
            except (PyJWKClientError, jwt.InvalidTokenError) as exc:
                raise TokenError("Unknown signing key") from exc

        raise TokenError("Unsupported token algorithm")
