"""Helpers to mint Supabase-style tokens and serve a real local JWKS endpoint."""

import json
import threading
import time
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any

import jwt
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from jwt.algorithms import ECAlgorithm, RSAAlgorithm

HS256_SECRET = "unit-test-hs256-secret-with-more-than-thirty-two-bytes"


def new_ec_key() -> ec.EllipticCurvePrivateKey:
    return ec.generate_private_key(ec.SECP256R1())


def new_rsa_key() -> rsa.RSAPrivateKey:
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def jwks_for(*keys: tuple[str, Any]) -> dict[str, Any]:
    """[(kid, private_key), ...] -> a JWKS document with only the public halves."""
    entries = []
    for kid, private_key in keys:
        public_key = private_key.public_key()
        if isinstance(private_key, ec.EllipticCurvePrivateKey):
            jwk = json.loads(ECAlgorithm.to_jwk(public_key))
            jwk["alg"] = "ES256"
        else:
            jwk = json.loads(RSAAlgorithm.to_jwk(public_key))
            jwk["alg"] = "RS256"
        jwk.update({"kid": kid, "use": "sig"})
        entries.append(jwk)
    return {"keys": entries}


@contextmanager
def jwks_server(document: dict[str, Any]) -> Iterator[str]:
    """Serves `document` at /auth/v1/.well-known/jwks.json; yields the base URL."""

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/auth/v1/.well-known/jwks.json":
                body = json.dumps(document).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, *_args: object) -> None:
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        server.server_close()


def make_token(
    key: Any,
    *,
    algorithm: str,
    issuer: str,
    kid: str | None = None,
    sub: str | None = None,
    expires_in: int = 3600,
    **claim_overrides: Any,
) -> str:
    now = int(time.time())
    claims: dict[str, Any] = {
        "iss": issuer,
        "aud": "authenticated",
        "sub": sub or str(uuid.uuid4()),
        "role": "authenticated",
        "email": "someone@example.com",
        "iat": now,
        "exp": now + expires_in,
    }
    claims.update(claim_overrides)
    claims = {k: v for k, v in claims.items() if v is not None}
    headers = {"kid": kid} if kid else None
    return jwt.encode(claims, key, algorithm=algorithm, headers=headers)
