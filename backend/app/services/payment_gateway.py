"""The payment gateway, behind a small interface so the rest of the app (and the
tests) never talk to Razorpay directly.

Only two gateway calls are needed: create an order for an exact amount, and fetch a
payment to confirm what really happened. Credentials come from `Settings` and never
appear in logs or responses.
"""

import logging
from dataclasses import dataclass
from typing import Any, Protocol

import httpx

from app.core.config import Settings
from app.core.errors import ServiceUnavailableError, UpstreamError

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class GatewayOrder:
    id: str
    amount_paise: int
    currency: str


@dataclass(frozen=True)
class GatewayPayment:
    id: str
    order_id: str | None
    amount_paise: int
    currency: str
    status: str  # created | authorized | captured | refunded | failed
    method: str | None = None
    error_description: str | None = None


class PaymentGateway(Protocol):
    def create_order(
        self, *, amount_paise: int, currency: str, receipt: str, notes: dict[str, str]
    ) -> GatewayOrder: ...

    def fetch_payment(self, payment_id: str) -> GatewayPayment | None:
        """The payment as the gateway knows it, or None when the gateway has no such payment."""
        ...


class RazorpayGateway:
    def __init__(self, settings: Settings, client: httpx.Client | None = None) -> None:
        self._base = settings.payment_gateway_base_url
        self._auth = (
            settings.payment_gateway_key_id,
            settings.payment_gateway_key_secret.get_secret_value(),
        )
        self._client = client or httpx.Client(timeout=settings.payment_gateway_timeout_seconds)

    def _request(self, method: str, path: str, **kwargs: Any) -> httpx.Response:
        try:
            response = self._client.request(
                method, f"{self._base}{path}", auth=self._auth, **kwargs
            )
        except httpx.HTTPError as exc:
            raise ServiceUnavailableError(
                "Payments are temporarily unavailable. Please try again.",
                log_message=f"payment gateway unreachable: {type(exc).__name__}",
            ) from exc
        if response.status_code >= 500:
            raise ServiceUnavailableError(
                "Payments are temporarily unavailable. Please try again.",
                log_message=f"payment gateway error {response.status_code}",
            )
        if response.status_code == 401:
            raise ServiceUnavailableError(
                "Payments are temporarily unavailable. Please try again.",
                log_message="payment gateway rejected our credentials (401)",
            )
        return response

    @staticmethod
    def _error_text(response: httpx.Response) -> str:
        try:
            error = response.json().get("error", {})
            return f"{error.get('code')}: {error.get('description')}"
        except (ValueError, AttributeError):
            return f"HTTP {response.status_code}"

    def create_order(
        self, *, amount_paise: int, currency: str, receipt: str, notes: dict[str, str]
    ) -> GatewayOrder:
        response = self._request(
            "POST",
            "/orders",
            json={
                "amount": amount_paise,
                "currency": currency,
                "receipt": receipt,
                "notes": notes,
                "payment_capture": 1,
            },
        )
        if response.status_code >= 400:
            raise UpstreamError(
                "The payment provider could not start this payment",
                log_message=f"create order refused: {self._error_text(response)}",
            )
        try:
            body = response.json()
            order = GatewayOrder(str(body["id"]), int(body["amount"]), str(body["currency"]))
        except (ValueError, KeyError, TypeError) as exc:
            raise UpstreamError(
                "The payment provider sent an unexpected answer",
                log_message="create order: malformed response",
            ) from exc
        if order.amount_paise != amount_paise or order.currency != currency:
            raise UpstreamError(
                "The payment provider sent an unexpected answer",
                log_message=f"create order: gateway changed the amount or currency ({order})",
            )
        return order

    def fetch_payment(self, payment_id: str) -> GatewayPayment | None:
        response = self._request("GET", f"/payments/{payment_id}")
        if response.status_code in (400, 404):
            return None
        if response.status_code >= 400:
            raise UpstreamError(
                "The payment provider could not confirm this payment",
                log_message=f"fetch payment refused: {self._error_text(response)}",
            )
        try:
            body = response.json()
            return GatewayPayment(
                id=str(body["id"]),
                order_id=body.get("order_id"),
                amount_paise=int(body["amount"]),
                currency=str(body["currency"]),
                status=str(body["status"]),
                method=body.get("method"),
                error_description=body.get("error_description"),
            )
        except (ValueError, KeyError, TypeError) as exc:
            raise UpstreamError(
                "The payment provider sent an unexpected answer",
                log_message="fetch payment: malformed response",
            ) from exc
