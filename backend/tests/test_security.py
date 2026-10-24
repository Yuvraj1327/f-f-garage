"""Token verification against a REAL local JWKS endpoint (no mocks of PyJWT)."""

import base64
import hashlib
import hmac
import json
import uuid

import jwt
import pytest
from cryptography.hazmat.primitives import serialization

from app.core.errors import ServiceUnavailableError
from app.core.security import TokenError, TokenVerifier
from tests.conftest import make_settings
from tests.jwt_helpers import (
    HS256_SECRET,
    jwks_for,
    jwks_server,
    make_token,
    new_ec_key,
    new_rsa_key,
)

EC_KEY = new_ec_key()
OTHER_EC_KEY = new_ec_key()
RSA_KEY = new_rsa_key()
USER_ID = str(uuid.uuid4())


@pytest.fixture(scope="module")
def base_url():
    document = jwks_for(("ec-1", EC_KEY), ("rsa-1", RSA_KEY))
    with jwks_server(document) as url:
        yield url


def _verifier(base_url: str, **settings_overrides: object) -> TokenVerifier:
    return TokenVerifier(
        make_settings(
            supabase_url=base_url,
            supabase_anon_key="anon",
            supabase_service_role_key="service",
            **settings_overrides,
        )
    )


def _es256(base_url: str, **kwargs: object) -> str:
    return make_token(EC_KEY, algorithm="ES256", kid="ec-1", issuer=f"{base_url}/auth/v1", **kwargs)


# ---- Accepted tokens ----------------------------------------------------------


def test_valid_es256_token_via_jwks(base_url: str) -> None:
    claims = _verifier(base_url).verify(_es256(base_url, sub=USER_ID, email="a@b.com"))
    assert claims.user_id == USER_ID
    assert claims.email == "a@b.com"


def test_valid_rs256_token_via_jwks(base_url: str) -> None:
    token = make_token(
        RSA_KEY, algorithm="RS256", kid="rsa-1", issuer=f"{base_url}/auth/v1", sub=USER_ID
    )
    assert _verifier(base_url).verify(token).user_id == USER_ID


def test_valid_hs256_token_when_secret_configured(base_url: str) -> None:
    token = make_token(HS256_SECRET, algorithm="HS256", issuer=f"{base_url}/auth/v1", sub=USER_ID)
    verifier = _verifier(base_url, supabase_jwt_secret=HS256_SECRET)
    assert verifier.verify(token).user_id == USER_ID


def test_small_clock_skew_is_tolerated(base_url: str) -> None:
    assert _verifier(base_url).verify(_es256(base_url, expires_in=-3))


# ---- Rejected tokens ----------------------------------------------------------


@pytest.mark.parametrize("garbage", ["", "abc", "a.b.c", "Bearer x", "x" * 500])
def test_malformed_tokens_are_rejected(base_url: str, garbage: str) -> None:
    with pytest.raises(TokenError):
        _verifier(base_url).verify(garbage)


def test_expired_token_is_rejected(base_url: str) -> None:
    with pytest.raises(TokenError, match="expired"):
        _verifier(base_url).verify(_es256(base_url, expires_in=-3600))


def test_wrong_audience_is_rejected(base_url: str) -> None:
    with pytest.raises(TokenError):
        _verifier(base_url).verify(_es256(base_url, aud="some-other-service"))


def test_wrong_issuer_is_rejected(base_url: str) -> None:
    token = make_token(EC_KEY, algorithm="ES256", kid="ec-1", issuer="https://evil.example/auth/v1")
    with pytest.raises(TokenError):
        _verifier(base_url).verify(token)


def test_signature_from_a_different_key_is_rejected(base_url: str) -> None:
    forged = make_token(OTHER_EC_KEY, algorithm="ES256", kid="ec-1", issuer=f"{base_url}/auth/v1")
    with pytest.raises(TokenError):
        _verifier(base_url).verify(forged)


def test_unknown_key_id_is_rejected(base_url: str) -> None:
    token = make_token(EC_KEY, algorithm="ES256", kid="not-published", issuer=f"{base_url}/auth/v1")
    with pytest.raises(TokenError):
        _verifier(base_url).verify(token)


def test_tampered_payload_is_rejected(base_url: str) -> None:
    header, _payload, signature = _es256(base_url, sub=USER_ID).split(".")
    forged_payload = _es256(base_url, sub=str(uuid.uuid4())).split(".")[1]
    with pytest.raises(TokenError):
        _verifier(base_url).verify(f"{header}.{forged_payload}.{signature}")


def test_alg_none_is_rejected(base_url: str) -> None:
    token = jwt.encode(
        {
            "iss": f"{base_url}/auth/v1",
            "aud": "authenticated",
            "sub": USER_ID,
            "role": "authenticated",
            "exp": 9999999999,
        },
        key=None,
        algorithm="none",
    )
    with pytest.raises(TokenError):
        _verifier(base_url).verify(token)


def test_hs256_is_rejected_when_no_secret_is_configured(base_url: str) -> None:
    token = make_token("x" * 40, algorithm="HS256", issuer=f"{base_url}/auth/v1")
    with pytest.raises(TokenError, match="algorithm"):
        _verifier(base_url).verify(token)


def test_algorithm_confusion_attack_is_rejected(base_url: str) -> None:
    """HS256 token 'signed' with the public key text as the HMAC secret."""
    public_pem = (
        EC_KEY.public_key()
        .public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
        .decode()
    )

    # PyJWT refuses to create this token, so build it by hand.
    def b64(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    signing_input = (
        b64(json.dumps({"alg": "HS256", "typ": "JWT", "kid": "ec-1"}).encode())
        + "."
        + b64(
            json.dumps(
                {
                    "iss": f"{base_url}/auth/v1",
                    "aud": "authenticated",
                    "sub": USER_ID,
                    "role": "authenticated",
                    "exp": 9999999999,
                }
            ).encode()
        )
    )
    signature = hmac.new(public_pem.encode(), signing_input.encode(), hashlib.sha256).digest()
    forged = f"{signing_input}.{b64(signature)}"
    with pytest.raises(TokenError):
        _verifier(base_url).verify(forged)
    with pytest.raises(TokenError):
        _verifier(base_url, supabase_jwt_secret=HS256_SECRET).verify(forged)


@pytest.mark.parametrize(
    "overrides",
    [
        {"role": "anon"},
        {"role": "service_role"},
        {"is_anonymous": True},
        {"sub": "not-a-uuid"},
    ],
)
def test_non_user_tokens_are_rejected(base_url: str, overrides: dict) -> None:
    with pytest.raises(TokenError):
        _verifier(base_url).verify(_es256(base_url, **overrides))


@pytest.mark.parametrize("missing", ["sub", "exp", "aud", "iss"])
def test_required_claims_must_be_present(base_url: str, missing: str) -> None:
    now_claims = {
        "iss": f"{base_url}/auth/v1",
        "aud": "authenticated",
        "sub": USER_ID,
        "role": "authenticated",
        "exp": 9999999999,
    }
    del now_claims[missing]
    token = jwt.encode(now_claims, EC_KEY, algorithm="ES256", headers={"kid": "ec-1"})
    with pytest.raises(TokenError):
        _verifier(base_url).verify(token)


# ---- Infrastructure failures are 503s, not 401s -------------------------------


def test_unreachable_jwks_is_a_service_error_not_a_401() -> None:
    dead = "http://127.0.0.1:9"  # nothing listens here
    verifier = TokenVerifier(make_settings(supabase_url=dead))
    token = make_token(EC_KEY, algorithm="ES256", kid="ec-1", issuer=f"{dead}/auth/v1")
    with pytest.raises(ServiceUnavailableError):
        verifier.verify(token)


def test_unconfigured_supabase_is_a_service_error() -> None:
    with pytest.raises(ServiceUnavailableError):
        TokenVerifier(make_settings()).verify("a.b.c")
