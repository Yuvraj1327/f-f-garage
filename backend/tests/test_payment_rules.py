"""Pure payment rules: paise conversion and gateway signatures."""

from decimal import Decimal

import pytest

from app.domain import payment as rules

# Independent reference values, computed with `openssl dgst -sha256 -hmac`.
ORDER, PAYMENT, SECRET = "order_IEIaMR65cu6nz3", "pay_IH4NVgf4Dreq1l", "EnLs21M47BllR3X8PSFtjtbd"
CHECKOUT_SIG = "0d4e745a1838664ad6c9c9902212a32d627d68e917290b0ad5f08ff4561bc50f"
WEBHOOK_BODY = b'{"event":"payment.captured"}'
WEBHOOK_SIG = "4f463a57dd128675850163391f0311888616d57bccca75c774c9cdb28134f851"


@pytest.mark.parametrize(
    ("rupees", "paise"),
    [("499", 49900), ("499.00", 49900), ("0.01", 1), ("849.50", 84950), ("1000000", 100_000_000)],
)
def test_to_paise_is_exact(rupees: str, paise: int) -> None:
    assert rules.to_paise(Decimal(rupees)) == paise
    assert rules.from_paise(paise) == Decimal(rupees).quantize(Decimal("0.01"))


def test_to_paise_refuses_fractions_of_a_paisa() -> None:
    with pytest.raises(ValueError):
        rules.to_paise(Decimal("10.005"))


def test_checkout_signature_matches_the_reference_value() -> None:
    assert rules.checkout_signature(ORDER, PAYMENT, SECRET) == CHECKOUT_SIG


def test_checkout_signature_verification() -> None:
    assert rules.verify_checkout_signature(ORDER, PAYMENT, CHECKOUT_SIG, SECRET)
    assert rules.verify_checkout_signature(ORDER, PAYMENT, CHECKOUT_SIG.upper(), SECRET)
    assert rules.verify_checkout_signature(ORDER, PAYMENT, f" {CHECKOUT_SIG} ", SECRET)


@pytest.mark.parametrize(
    ("order", "payment", "signature", "secret"),
    [
        ("order_other", PAYMENT, CHECKOUT_SIG, SECRET),  # order swapped
        (ORDER, "pay_other", CHECKOUT_SIG, SECRET),  # payment swapped
        (ORDER, PAYMENT, CHECKOUT_SIG[:-1] + "0", SECRET),  # one character off
        (ORDER, PAYMENT, "", SECRET),  # missing
        (ORDER, PAYMENT, CHECKOUT_SIG, "wrong-secret"),  # wrong key
        (ORDER, PAYMENT, CHECKOUT_SIG, ""),  # no key configured
        (ORDER, PAYMENT, "not-hex", SECRET),
    ],
)
def test_checkout_signature_rejects_anything_else(order, payment, signature, secret) -> None:
    assert not rules.verify_checkout_signature(order, payment, signature, secret)


def test_webhook_signature_matches_the_reference_value() -> None:
    assert rules.webhook_signature(WEBHOOK_BODY, "whsec_test") == WEBHOOK_SIG
    assert rules.verify_webhook_signature(WEBHOOK_BODY, WEBHOOK_SIG, "whsec_test")


@pytest.mark.parametrize(
    ("body", "signature", "secret"),
    [
        (WEBHOOK_BODY + b" ", WEBHOOK_SIG, "whsec_test"),  # body altered
        (WEBHOOK_BODY, WEBHOOK_SIG, "other"),  # wrong secret
        (WEBHOOK_BODY, None, "whsec_test"),
        (WEBHOOK_BODY, "", "whsec_test"),
        (WEBHOOK_BODY, WEBHOOK_SIG, ""),
    ],
)
def test_webhook_signature_rejects_anything_else(body, signature, secret) -> None:
    assert not rules.verify_webhook_signature(body, signature, secret)
