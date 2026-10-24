"""Pure payment rules: money units and gateway signatures. No I/O.

Razorpay signs two different things:
  * the checkout callback:  HMAC-SHA256(key_secret,     "<order_id>|<payment_id>")
  * a webhook:              HMAC-SHA256(webhook_secret, <raw request body>)
Both are hex digests and are compared in constant time.
"""

import hashlib
import hmac
from decimal import ROUND_HALF_UP, Decimal

_HUNDRED = Decimal(100)


def to_paise(amount: Decimal) -> int:
    """Rupees to paise, exactly. Refuses amounts with sub-paise precision."""
    paise = amount * _HUNDRED
    if paise != paise.to_integral_value():
        raise ValueError("Amount has more than two decimal places")
    return int(paise.to_integral_value(rounding=ROUND_HALF_UP))


def from_paise(paise: int) -> Decimal:
    return (Decimal(paise) / _HUNDRED).quantize(Decimal("0.01"))


def _hmac_hex(secret: str, message: bytes) -> str:
    return hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()


def checkout_signature(order_id: str, payment_id: str, key_secret: str) -> str:
    return _hmac_hex(key_secret, f"{order_id}|{payment_id}".encode())


def verify_checkout_signature(
    order_id: str, payment_id: str, signature: str, key_secret: str
) -> bool:
    if not key_secret or not signature:
        return False
    expected = checkout_signature(order_id, payment_id, key_secret)
    return hmac.compare_digest(expected, signature.strip().lower())


def webhook_signature(body: bytes, webhook_secret: str) -> str:
    return _hmac_hex(webhook_secret, body)


def verify_webhook_signature(body: bytes, signature: str | None, webhook_secret: str) -> bool:
    if not webhook_secret or not signature:
        return False
    expected = webhook_signature(body, webhook_secret)
    return hmac.compare_digest(expected, signature.strip().lower())
