"""Payment API: order creation, checkout verification, webhooks, duplicates, amounts,
ownership and admin access. The gateway is a fake; signatures are computed here with the
same secrets the app is configured with."""

import json
import uuid
from datetime import UTC, datetime, timedelta

import pytest

from app.domain import payment as rules
from app.domain.enums import BookingStatus, PaymentStatus, UserRole
from app.services.payment_gateway import GatewayPayment
from tests.conftest import CONFIGURED_SUPABASE, make_settings
from tests.fakes import make_profile
from tests.jwt_helpers import HS256_SECRET
from tests.phase3_support import NOW, Ctx, headers_for
from tests.test_bookings_api import API, World

KEY_SECRET = "key-secret-xyz"  # noqa: S105
WEBHOOK_SECRET = "webhook-secret-xyz"  # noqa: S105
PAY_SETTINGS = make_settings(
    **CONFIGURED_SUPABASE,
    supabase_jwt_secret=HS256_SECRET,
    payment_gateway_provider="razorpay",
    payment_gateway_key_id="rzp_test_abc123",
    payment_gateway_key_secret=KEY_SECRET,
    payment_gateway_webhook_secret=WEBHOOK_SECRET,
)


class PayWorld(World):
    """A bookable catalogue plus a payments-enabled app."""

    def __init__(self) -> None:
        super().__init__(Ctx(PAY_SETTINGS))
        self.client = self.ctx.client
        self.cust = self.ctx.as_customer

    def booking(self, with_oil: bool = False, **over) -> dict:
        extra = {"extra_charge_ids": [self.oil["id"]]} if with_oil else {}
        r = self.book(**extra, **over)
        assert r.status_code == 201, r.text
        return r.json()

    def start(self, booking_id: str, headers=None):
        return self.client.post(
            f"{API}/bookings/{booking_id}/payments", headers=headers or self.cust
        )

    def started(self, booking: dict) -> dict:
        r = self.start(booking["id"])
        assert r.status_code == 201, r.text
        return r.json()

    def verify(self, payment_id, order_id, pay_id, signature=None, headers=None, **over):
        body = {
            "razorpay_order_id": order_id,
            "razorpay_payment_id": pay_id,
            "razorpay_signature": signature
            or rules.checkout_signature(order_id, pay_id, KEY_SECRET),
            **over,
        }
        return self.client.post(
            f"{API}/payments/{payment_id}/verify", headers=headers or self.cust, json=body
        )

    def gateway_reports(
        self, started: dict, pay_id="pay_ok1", status="captured", paise=None, **over
    ):
        order = started["checkout"]["order_id"]
        self.ctx.gateway.will_report(
            pay_id,
            order,
            paise if paise is not None else started["checkout"]["amount_paise"],
            status=status,
            **over,
        )

    def booking_status(self, booking_id: str) -> str:
        return self.client.get(f"{API}/bookings/{booking_id}", headers=self.cust).json()["status"]

    def webhook(
        self,
        event: str,
        order: str,
        pay_id: str,
        paise: int,
        *,
        event_id="evt_1",
        signature=None,
        secret=WEBHOOK_SECRET,
        currency="INR",
        extra=None,
    ):
        entity = {
            "id": pay_id,
            "order_id": order,
            "amount": paise,
            "currency": currency,
            "method": "card",
            **(extra or {}),
        }
        body = json.dumps({"event": event, "payload": {"payment": {"entity": entity}}}).encode()
        headers = {"Content-Type": "application/json"}
        if event_id:
            headers["X-Razorpay-Event-Id"] = event_id
        sig = signature if signature is not None else rules.webhook_signature(body, secret)
        headers["X-Razorpay-Signature"] = sig
        return self.client.post(f"{API}/webhooks/razorpay", content=body, headers=headers)


@pytest.fixture
def pw() -> PayWorld:
    return PayWorld()


# ---- Order creation ------------------------------------------------------------------------


def test_starting_a_payment_creates_an_order_for_the_server_total(pw: PayWorld) -> None:
    b = pw.booking(with_oil=True)  # 499 + 350
    r = pw.start(b["id"])
    assert r.status_code == 201, r.text
    out = r.json()
    assert out["payment"]["status"] == "pending"
    assert out["payment"]["amount"] == "169.80" and out["payment"]["currency"] == "INR"
    assert out["payment"]["booking_id"] == b["id"]
    c = out["checkout"]
    assert c["amount_paise"] == 16980 and c["currency"] == "INR"
    assert c["key_id"] == "rzp_test_abc123" and c["mode"] == "test"
    assert c["order_id"] == out["payment"]["gateway_order_id"]
    assert c["prefill_name"] == pw.ctx.customer.full_name
    assert "FF-000001" in c["description"]
    # What the gateway was asked for: the booking's own total, tied to the booking code.
    order = pw.ctx.gateway.orders[0]
    assert (order["amount"], order["currency"], order["receipt"]) == (16980, "INR", "FF-000001")
    assert order["notes"]["booking_id"] == b["id"]


def test_the_secret_never_appears_in_any_response(pw: PayWorld) -> None:
    b = pw.booking()
    started = pw.start(b["id"])
    for secret in (KEY_SECRET, WEBHOOK_SECRET):
        assert secret not in started.text
        assert secret not in pw.client.get(f"{API}/bookings/{b['id']}", headers=pw.cust).text


def test_the_app_cannot_choose_the_amount(pw: PayWorld) -> None:
    b = pw.booking()
    r = pw.client.post(
        f"{API}/bookings/{b['id']}/payments", headers=pw.cust, json={"amount": "1.00"}
    )
    # The body is ignored: the amount is always the booking total.
    assert r.status_code == 201
    assert r.json()["checkout"]["amount_paise"] == 9980


def test_starting_twice_reuses_the_open_attempt(pw: PayWorld) -> None:
    b = pw.booking()
    first, second = pw.started(b), pw.started(b)
    assert first["payment"]["id"] == second["payment"]["id"]
    assert first["checkout"]["order_id"] == second["checkout"]["order_id"]
    assert len(pw.ctx.gateway.orders) == 1


def test_a_stale_attempt_is_cancelled_and_replaced(pw: PayWorld) -> None:
    b = pw.booking()
    first = pw.started(b)
    old = pw.ctx.payments.rows[uuid.UUID(first["payment"]["id"])]
    pw.ctx.payments.rows[old.id] = old.model_copy(
        update={"created_at": datetime.now(UTC) - timedelta(minutes=45)}
    )
    second = pw.started(b)
    assert second["payment"]["id"] != first["payment"]["id"]
    assert pw.ctx.payments.rows[old.id].status == PaymentStatus.CANCELLED
    assert len(pw.ctx.gateway.orders) == 2


def test_only_the_owner_can_pay_for_a_booking(pw: PayWorld) -> None:
    b = pw.booking()
    other = pw.ctx.profiles.add(make_profile(UserRole.CUSTOMER))
    r = pw.start(b["id"], headers=headers_for(other))
    assert r.status_code == 404
    assert pw.ctx.gateway.orders == []
    assert pw.start(str(uuid.uuid4())).status_code == 404


def test_only_customers_can_start_payments(pw: PayWorld) -> None:
    b = pw.booking()
    for headers in (pw.ctx.as_admin, pw.ctx.as_driver):
        assert pw.start(b["id"], headers=headers).status_code == 403
    assert pw.client.post(f"{API}/bookings/{b['id']}/payments").status_code == 401


def test_a_cancelled_or_confirmed_booking_cannot_be_paid(pw: PayWorld) -> None:
    b = pw.booking()
    pw.ctx.bookings.force_status(uuid.UUID(b["id"]), BookingStatus.CONFIRMED)
    assert pw.start(b["id"]).status_code == 409
    c = pw.booking(time_slot_id=str(pw.slot2.id))
    pw.client.post(f"{API}/bookings/{c['id']}/cancel", headers=pw.cust, json={})
    r = pw.start(c["id"])
    assert r.status_code == 409 and "cancelled" in r.json()["detail"]
    assert pw.ctx.gateway.orders == []


def test_a_paid_booking_cannot_be_paid_again(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pw.gateway_reports(s)
    assert pw.verify(s["payment"]["id"], s["checkout"]["order_id"], "pay_ok1").status_code == 200
    r = pw.start(b["id"])
    assert r.status_code == 409 and "already paid" in r.json()["detail"]


def test_a_zero_total_booking_has_nothing_to_pay(pw: PayWorld) -> None:
    b = pw.booking()
    row = pw.ctx.bookings.rows[uuid.UUID(b["id"])]
    row["package_price"] = row["package_price"] * 0
    row["advance_amount"] = row["advance_amount"] * 0
    assert pw.start(b["id"]).status_code == 422


def test_payments_unavailable_when_not_configured() -> None:
    off = Ctx()  # default settings: no gateway
    w = World(off)
    b = w.book().json()
    assert b["can_pay"] is False
    r = off.client.post(f"{API}/bookings/{b['id']}/payments", headers=off.as_customer)
    assert r.status_code == 503
    assert "not available" in r.json()["detail"]


def test_gateway_outage_is_a_503_and_leaves_no_attempt(pw: PayWorld) -> None:
    from app.core.errors import ServiceUnavailableError

    b = pw.booking()
    pw.ctx.gateway.fail_with = ServiceUnavailableError("Payments are temporarily unavailable.")
    assert pw.start(b["id"]).status_code == 503
    assert pw.ctx.payments.rows == {}
    pw.ctx.gateway.fail_with = None
    assert pw.start(b["id"]).status_code == 201


# ---- Verifying the checkout result -----------------------------------------------------------


def test_valid_signature_and_gateway_confirmation_marks_paid_and_confirms(pw: PayWorld) -> None:
    b = pw.booking(with_oil=True)
    s = pw.started(b)
    pw.gateway_reports(s)
    r = pw.verify(s["payment"]["id"], s["checkout"]["order_id"], "pay_ok1")
    assert r.status_code == 200, r.text
    out = r.json()
    assert out["paid"] is True and out["outcome"] == "paid" and out["booking_status"] == "confirmed"
    p = out["payment"]
    assert p["status"] == "successful" and p["transaction_id"] == "pay_ok1"
    assert p["method"] == "upi" and p["paid_at"] is not None and p["amount"] == "169.80"
    mine = pw.client.get(f"{API}/bookings/{b['id']}", headers=pw.cust).json()
    assert mine["status"] == "confirmed" and mine["confirmed_at"] is not None
    assert mine["is_paid"] is True and mine["can_pay"] is False
    assert mine["payment"]["transaction_id"] == "pay_ok1"


def test_an_invalid_signature_is_rejected_and_changes_nothing(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pw.gateway_reports(s)  # even if the gateway says captured...
    r = pw.verify(s["payment"]["id"], s["checkout"]["order_id"], "pay_ok1", signature="0" * 64)
    assert r.status_code == 422
    assert pw.ctx.gateway.fetch_calls == []  # never even asked the gateway
    assert pw.booking_status(b["id"]) == "pending_payment"
    assert pw.ctx.payments.rows[uuid.UUID(s["payment"]["id"])].status == PaymentStatus.PENDING
    assert [e["outcome"] for e in pw.ctx.payments.events] == ["invalid_signature"]


def test_a_signature_made_with_another_secret_is_rejected(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    forged = rules.checkout_signature(order, "pay_ok1", "attacker-secret")
    assert pw.verify(s["payment"]["id"], order, "pay_ok1", signature=forged).status_code == 422
    assert pw.booking_status(b["id"]) == "pending_payment"


def test_the_app_claiming_success_is_not_enough_without_the_gateway(pw: PayWorld) -> None:
    """A correct signature for a payment the gateway does not know or has not captured."""
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    # unknown to the gateway
    assert pw.verify(s["payment"]["id"], order, "pay_ghost").status_code == 422
    assert pw.booking_status(b["id"]) == "pending_payment"
    # known but only authorized (not captured): pending, booking not confirmed
    pw.gateway_reports(s, pay_id="pay_auth", status="authorized")
    r = pw.verify(s["payment"]["id"], order, "pay_auth")
    assert r.status_code == 200
    assert r.json()["outcome"] == "pending" and r.json()["paid"] is False
    assert pw.booking_status(b["id"]) == "pending_payment"


def test_a_payment_of_another_order_is_refused(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    # the gateway says pay_x was captured, but for a different order
    pw.ctx.gateway.payments["pay_x"] = GatewayPayment(
        "pay_x", "order_other", 9980, "INR", "captured"
    )
    assert pw.verify(s["payment"]["id"], order, "pay_x").status_code == 422
    assert pw.booking_status(b["id"]) == "pending_payment"
    # and a callback that names a different order than this payment's
    r = pw.verify(s["payment"]["id"], "order_other", "pay_x")
    assert r.status_code == 422


def test_amount_must_match_the_order_exactly(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    for paise, currency in ((100, "INR"), (99900, "INR"), (9980, "USD")):
        pw.ctx.gateway.will_report("pay_bad", order, paise, currency=currency)
        r = pw.verify(s["payment"]["id"], order, "pay_bad")
        assert r.status_code == 200
        assert r.json()["paid"] is False and r.json()["outcome"] == "amount_mismatch"
        assert pw.booking_status(b["id"]) == "pending_payment"
    rec = pw.ctx.payments.rows[uuid.UUID(s["payment"]["id"])]
    assert rec.status == PaymentStatus.FAILED and rec.needs_review


def test_a_failed_payment_is_recorded_and_can_be_retried(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    pw.gateway_reports(s, pay_id="pay_f1", status="failed", error_description="Card declined")
    r = pw.verify(s["payment"]["id"], order, "pay_f1")
    assert r.status_code == 200
    assert r.json()["payment"]["status"] == "failed"
    assert r.json()["payment"]["failure_reason"] == "Card declined"
    assert pw.booking_status(b["id"]) == "pending_payment"
    # A new attempt is possible and gets its own order...
    s2 = pw.started(b)
    assert s2["payment"]["id"] != s["payment"]["id"]
    pw.gateway_reports(s2, pay_id="pay_ok2")
    assert pw.verify(s2["payment"]["id"], s2["checkout"]["order_id"], "pay_ok2").json()["paid"]
    attempts = pw.client.get(f"{API}/bookings/{b['id']}/payments", headers=pw.cust).json()
    assert [a["status"] for a in attempts] == ["successful", "failed"]


def test_verifying_twice_is_idempotent(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pw.gateway_reports(s)
    first = pw.verify(s["payment"]["id"], s["checkout"]["order_id"], "pay_ok1").json()
    calls = len(pw.ctx.gateway.fetch_calls)
    second = pw.verify(s["payment"]["id"], s["checkout"]["order_id"], "pay_ok1")
    assert second.status_code == 200
    assert second.json()["outcome"] == "already_processed" and second.json()["paid"] is True
    assert second.json()["payment"]["paid_at"] == first["payment"]["paid_at"]
    assert len(pw.ctx.gateway.fetch_calls) == calls  # no second gateway call
    assert sum(p.status == PaymentStatus.SUCCESSFUL for p in pw.ctx.payments.rows.values()) == 1


def test_verify_checks_ownership_and_input(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pid, order = s["payment"]["id"], s["checkout"]["order_id"]
    pw.gateway_reports(s)
    assert pw.verify(pid, order, "pay_ok1", headers=pw.ctx.as_admin).status_code == 403
    assert pw.verify(str(uuid.uuid4()), order, "pay_ok1").status_code == 404
    assert pw.verify(pid, order, "pay_ok1", extra="x").status_code == 422  # unknown field
    assert pw.verify(pid, order, "pay|x").status_code == 422  # '|' cannot smuggle a second id
    assert pw.verify(pid, order, "pay_ok1", signature="short").status_code == 422
    assert pw.booking_status(b["id"]) == "pending_payment"


def test_gateway_outage_during_verify_changes_nothing(pw: PayWorld) -> None:
    from app.core.errors import ServiceUnavailableError

    b = pw.booking()
    s = pw.started(b)
    pw.gateway_reports(s)
    pw.ctx.gateway.fail_with = ServiceUnavailableError("down")
    assert pw.verify(s["payment"]["id"], s["checkout"]["order_id"], "pay_ok1").status_code == 503
    assert pw.booking_status(b["id"]) == "pending_payment"
    pw.ctx.gateway.fail_with = None
    assert pw.verify(s["payment"]["id"], s["checkout"]["order_id"], "pay_ok1").json()["paid"]


# ---- Cancelling a checkout --------------------------------------------------------------------


def test_closing_the_checkout_cancels_the_attempt_and_allows_a_new_one(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    r = pw.client.post(f"{API}/payments/{s['payment']['id']}/cancel", headers=pw.cust)
    assert r.status_code == 200 and r.json()["status"] == "cancelled"
    assert pw.booking_status(b["id"]) == "pending_payment"
    again = pw.client.post(f"{API}/payments/{s['payment']['id']}/cancel", headers=pw.cust)
    assert again.status_code == 200 and again.json()["status"] == "cancelled"  # idempotent
    s2 = pw.started(b)
    assert s2["payment"]["id"] != s["payment"]["id"]


def test_cancelling_never_undoes_a_successful_payment(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pw.gateway_reports(s)
    pw.verify(s["payment"]["id"], s["checkout"]["order_id"], "pay_ok1")
    r = pw.client.post(f"{API}/payments/{s['payment']['id']}/cancel", headers=pw.cust)
    assert r.status_code == 200 and r.json()["status"] == "successful"


def test_money_that_arrives_after_cancel_is_still_honoured(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pw.client.post(f"{API}/payments/{s['payment']['id']}/cancel", headers=pw.cust)
    r = pw.webhook("payment.captured", s["checkout"]["order_id"], "pay_late", 9980)
    assert r.status_code == 200 and r.json()["status"] == "paid"
    assert pw.booking_status(b["id"]) == "confirmed"


def test_cancelling_a_booking_closes_its_open_payment(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pw.client.post(f"{API}/bookings/{b['id']}/cancel", headers=pw.cust, json={})
    assert pw.ctx.payments.rows[uuid.UUID(s["payment"]["id"])].status == PaymentStatus.CANCELLED


def test_payment_after_the_booking_was_cancelled_is_flagged_for_refund(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pw.client.post(f"{API}/bookings/{b['id']}/cancel", headers=pw.cust, json={})
    r = pw.webhook("payment.captured", s["checkout"]["order_id"], "pay_late", 9980)
    assert r.json()["status"] == "paid_review"
    rec = pw.ctx.payments.rows[uuid.UUID(s["payment"]["id"])]
    assert rec.status == PaymentStatus.SUCCESSFUL and rec.needs_review
    assert pw.booking_status(b["id"]) == "cancelled"


def test_cancelling_a_paid_booking_flags_the_payment(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pw.gateway_reports(s)
    pw.verify(s["payment"]["id"], s["checkout"]["order_id"], "pay_ok1")
    assert (
        pw.client.post(f"{API}/bookings/{b['id']}/cancel", headers=pw.cust, json={}).status_code
        == 200
    )
    rec = pw.ctx.payments.rows[uuid.UUID(s["payment"]["id"])]
    assert rec.status == PaymentStatus.SUCCESSFUL and rec.needs_review


# ---- Webhooks ----------------------------------------------------------------------------------


def test_webhook_captured_confirms_the_booking(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    r = pw.webhook("payment.captured", s["checkout"]["order_id"], "pay_w1", 9980)
    assert r.status_code == 200 and r.json() == {"status": "paid"}
    assert pw.booking_status(b["id"]) == "confirmed"
    rec = pw.ctx.payments.rows[uuid.UUID(s["payment"]["id"])]
    assert (rec.status, rec.provider_payment_id, rec.method) == (
        PaymentStatus.SUCCESSFUL,
        "pay_w1",
        "card",
    )


def test_webhook_order_paid_is_handled_too(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    r = pw.webhook("order.paid", s["checkout"]["order_id"], "pay_w1", 9980, event_id="evt_op")
    assert r.json()["status"] == "paid"


def test_webhook_with_a_bad_signature_is_rejected(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    for kwargs in (
        {"signature": "0" * 64},
        {"secret": "attacker-secret"},
        {"signature": ""},
    ):
        r = pw.webhook("payment.captured", order, "pay_w1", 9980, **kwargs)
        assert r.status_code == 400, kwargs
    assert pw.booking_status(b["id"]) == "pending_payment"
    assert pw.ctx.payments.events == []


def test_webhook_signature_covers_the_exact_body(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    body = json.dumps(
        {
            "event": "payment.captured",
            "payload": {
                "payment": {
                    "entity": {
                        "id": "pay_w1",
                        "order_id": s["checkout"]["order_id"],
                        "amount": 9980,
                        "currency": "INR",
                    }
                }
            },
        }
    ).encode()
    sig = rules.webhook_signature(body, WEBHOOK_SECRET)
    tampered = body.replace(b"9980", b"100")
    r = pw.client.post(
        f"{API}/webhooks/razorpay", content=tampered, headers={"X-Razorpay-Signature": sig}
    )
    assert r.status_code == 400


def test_webhook_without_a_signature_header_is_rejected(pw: PayWorld) -> None:
    r = pw.client.post(f"{API}/webhooks/razorpay", content=b'{"event":"payment.captured"}')
    assert r.status_code == 400


def test_webhook_needs_no_login(pw: PayWorld) -> None:
    # (no Authorization header anywhere in the helper) - a signed call from the gateway works
    b = pw.booking()
    s = pw.started(b)
    assert (
        pw.webhook("payment.captured", s["checkout"]["order_id"], "pay_w1", 9980).status_code == 200
    )


def test_the_same_webhook_delivered_twice_is_applied_once(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    first = pw.webhook("payment.captured", order, "pay_w1", 9980, event_id="evt_same")
    second = pw.webhook("payment.captured", order, "pay_w1", 9980, event_id="evt_same")
    assert (first.status_code, second.status_code) == (200, 200)
    assert first.json()["status"] == "paid" and second.json()["status"] == "duplicate_event"
    assert sum(p.status == PaymentStatus.SUCCESSFUL for p in pw.ctx.payments.rows.values()) == 1
    assert len([e for e in pw.ctx.payments.events if e["event_id"] == "evt_same"]) == 1


def test_a_new_event_for_the_same_payment_changes_nothing(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    pw.webhook("payment.captured", order, "pay_w1", 9980, event_id="evt_a")
    again = pw.webhook("order.paid", order, "pay_w1", 9980, event_id="evt_b")
    assert again.json()["status"] == "already_processed"


def test_a_webhook_without_an_event_id_is_still_deduplicated(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    # same body twice -> same derived key
    first = pw.webhook("payment.captured", order, "pay_w1", 9980, event_id=None)
    second = pw.webhook("payment.captured", order, "pay_w1", 9980, event_id=None)
    assert first.json()["status"] == "paid" and second.json()["status"] == "duplicate_event"


def test_verify_then_webhook_then_verify_all_agree(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pw.gateway_reports(s)
    order = s["checkout"]["order_id"]
    assert pw.verify(s["payment"]["id"], order, "pay_ok1").json()["outcome"] == "paid"
    assert (
        pw.webhook("payment.captured", order, "pay_ok1", 9980).json()["status"]
        == "already_processed"
    )
    assert pw.verify(s["payment"]["id"], order, "pay_ok1").json()["outcome"] == "already_processed"
    assert sum(p.status == PaymentStatus.SUCCESSFUL for p in pw.ctx.payments.rows.values()) == 1


def test_webhook_amount_mismatch_is_not_accepted(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    r = pw.webhook("payment.captured", order, "pay_w1", 100)
    assert r.status_code == 200 and r.json()["status"] == "amount_mismatch"
    assert pw.booking_status(b["id"]) == "pending_payment"
    assert pw.ctx.payments.rows[uuid.UUID(s["payment"]["id"])].needs_review
    r = pw.webhook("payment.captured", order, "pay_w2", 9980, currency="USD", event_id="evt_usd")
    assert r.json()["status"] == "amount_mismatch"


def test_webhook_failed_marks_the_attempt_failed_and_a_retry_can_still_succeed(
    pw: PayWorld,
) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    r = pw.webhook(
        "payment.failed",
        order,
        "pay_w1",
        9980,
        event_id="evt_f",
        extra={"error_description": "Insufficient funds"},
    )
    assert r.json()["status"] == "failed"
    rec = pw.ctx.payments.rows[uuid.UUID(s["payment"]["id"])]
    assert rec.status == PaymentStatus.FAILED and rec.failure_reason == "Insufficient funds"
    assert pw.booking_status(b["id"]) == "pending_payment"
    # The customer retried inside the same Razorpay checkout and it worked.
    assert (
        pw.webhook("payment.captured", order, "pay_w2", 9980, event_id="evt_ok").json()["status"]
        == "paid"
    )
    assert pw.booking_status(b["id"]) == "confirmed"


def test_a_late_failure_never_undoes_success(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    pw.webhook("payment.captured", order, "pay_w1", 9980, event_id="evt_ok")
    r = pw.webhook("payment.failed", order, "pay_w0", 9980, event_id="evt_late_fail")
    assert r.json()["status"] == "ignored"
    assert pw.booking_status(b["id"]) == "confirmed"


def test_a_second_payment_for_a_paid_booking_is_flagged_not_accepted(pw: PayWorld) -> None:
    b = pw.booking()
    s1 = pw.started(b)
    pw.webhook("payment.captured", s1["checkout"]["order_id"], "pay_1", 9980, event_id="e1")
    # A second order exists (e.g. created from another device before the first finished).
    second = pw.ctx.payments.create_attempt(
        {
            "booking_id": b["id"],
            "customer_id": str(pw.ctx.customer.id),
            "provider": "razorpay",
            "provider_order_id": "order_second",
            "amount": "99.80",
        }
    )
    r = pw.webhook("payment.captured", "order_second", "pay_2", 9980, event_id="e2")
    assert r.json()["status"] == "duplicate_payment"
    rec = pw.ctx.payments.rows[second.id]
    assert rec.status == PaymentStatus.FAILED and rec.needs_review
    assert sum(p.status == PaymentStatus.SUCCESSFUL for p in pw.ctx.payments.rows.values()) == 1


def test_a_second_capture_on_the_same_order_is_flagged(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    order = s["checkout"]["order_id"]
    pw.webhook("payment.captured", order, "pay_1", 9980, event_id="e1")
    r = pw.webhook("payment.captured", order, "pay_2", 9980, event_id="e2")
    assert r.json()["status"] == "duplicate_payment"
    rec = pw.ctx.payments.rows[uuid.UUID(s["payment"]["id"])]
    assert rec.provider_payment_id == "pay_1" and rec.needs_review


def test_webhook_for_an_unknown_order_is_acknowledged_not_retried(pw: PayWorld) -> None:
    r = pw.webhook("payment.captured", "order_nobody", "pay_x", 9980)
    assert r.status_code == 200 and r.json()["status"] == "unknown_order"


def test_other_webhook_events_are_ignored(pw: PayWorld) -> None:
    body = json.dumps({"event": "refund.processed", "payload": {}}).encode()
    sig = rules.webhook_signature(body, WEBHOOK_SECRET)
    r = pw.client.post(
        f"{API}/webhooks/razorpay", content=body, headers={"X-Razorpay-Signature": sig}
    )
    assert r.status_code == 200 and r.json()["status"] == "ignored"
    assert pw.ctx.payments.events == []


def test_malformed_signed_webhooks_are_a_400(pw: PayWorld) -> None:
    for body in (b"not json", b'{"no_event": 1}', b'{"event": "payment.captured", "payload": {}}'):
        sig = rules.webhook_signature(body, WEBHOOK_SECRET)
        r = pw.client.post(
            f"{API}/webhooks/razorpay", content=body, headers={"X-Razorpay-Signature": sig}
        )
        assert r.status_code == 400, body


def test_webhook_is_503_until_a_webhook_secret_is_configured() -> None:
    settings = make_settings(
        **CONFIGURED_SUPABASE,
        supabase_jwt_secret=HS256_SECRET,
        payment_gateway_provider="razorpay",
        payment_gateway_key_id="rzp_test_abc123",
        payment_gateway_key_secret=KEY_SECRET,
    )
    ctx = Ctx(settings)
    r = ctx.client.post(
        f"{API}/webhooks/razorpay", content=b"{}", headers={"X-Razorpay-Signature": "x"}
    )
    assert r.status_code == 503
    # And with payments off entirely:
    off = Ctx()
    assert off.client.post(f"{API}/webhooks/razorpay", content=b"{}").status_code == 503


# ---- Reading payments --------------------------------------------------------------------------


def test_customer_sees_only_their_own_payments(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pid = s["payment"]["id"]
    assert pw.client.get(f"{API}/payments/{pid}", headers=pw.cust).json()["id"] == pid
    assert (
        pw.client.get(f"{API}/bookings/{b['id']}/payments", headers=pw.cust).json()[0]["id"] == pid
    )
    other = pw.ctx.profiles.add(make_profile(UserRole.CUSTOMER))
    theirs = headers_for(other)
    assert pw.client.get(f"{API}/payments/{pid}", headers=theirs).status_code == 404
    assert pw.client.get(f"{API}/bookings/{b['id']}/payments", headers=theirs).status_code == 404
    assert pw.client.post(f"{API}/payments/{pid}/cancel", headers=theirs).status_code == 404
    assert pw.verify(pid, s["checkout"]["order_id"], "pay_x", headers=theirs).status_code == 404
    assert pw.client.get(f"{API}/payments/{pid}", headers=pw.ctx.as_driver).status_code == 403


def test_customer_payment_output_hides_internal_review_fields(pw: PayWorld) -> None:
    b = pw.booking()
    s = pw.started(b)
    pw.webhook("payment.captured", s["checkout"]["order_id"], "pay_1", 100)  # mismatch -> flagged
    out = pw.client.get(f"{API}/payments/{s['payment']['id']}", headers=pw.cust).json()
    assert "needs_review" not in out and "review_reason" not in out and "customer_id" not in out


def test_booking_history_carries_payment_status_and_transaction(pw: PayWorld) -> None:
    unpaid = pw.booking()
    paid = pw.booking(time_slot_id=str(pw.slot2.id))
    s = pw.started(paid)
    pw.gateway_reports(s)
    pw.verify(s["payment"]["id"], s["checkout"]["order_id"], "pay_ok1")
    failed_b = pw.booking(scheduled_date=(NOW.date() + timedelta(days=5)).isoformat())
    f = pw.started(failed_b)
    pw.gateway_reports(f, pay_id="pay_f", status="failed")
    pw.verify(f["payment"]["id"], f["checkout"]["order_id"], "pay_f")

    items = {i["id"]: i for i in pw.client.get(f"{API}/bookings", headers=pw.cust).json()["items"]}
    assert items[unpaid["id"]]["payment"] is None and items[unpaid["id"]]["can_pay"] is True
    assert items[paid["id"]]["is_paid"] is True and items[paid["id"]]["can_pay"] is False
    assert items[paid["id"]]["payment"]["transaction_id"] == "pay_ok1"
    assert items[paid["id"]]["payment"]["status"] == "successful"
    assert items[failed_b["id"]]["payment"]["status"] == "failed"
    assert items[failed_b["id"]]["can_pay"] is True and items[failed_b["id"]]["is_paid"] is False


def test_can_pay_is_false_when_cancelled(pw: PayWorld) -> None:
    b = pw.booking()
    out = pw.client.post(f"{API}/bookings/{b['id']}/cancel", headers=pw.cust, json={}).json()
    assert out["can_pay"] is False and out["is_paid"] is False


# ---- Admin -------------------------------------------------------------------------------------


@pytest.fixture
def admin_world(pw: PayWorld):
    b1 = pw.booking()
    s1 = pw.started(b1)
    pw.gateway_reports(s1, pay_id="pay_adm1")
    pw.verify(s1["payment"]["id"], s1["checkout"]["order_id"], "pay_adm1")
    b2 = pw.booking(time_slot_id=str(pw.slot2.id))
    s2 = pw.started(b2)
    pw.webhook("payment.captured", s2["checkout"]["order_id"], "pay_adm2", 100)  # flagged
    return pw, (b1, s1), (b2, s2)


def test_admin_lists_and_filters_payments(admin_world) -> None:
    pw, (b1, s1), (b2, s2) = admin_world
    admin = pw.ctx.as_admin
    page = pw.client.get(f"{API}/admin/payments", headers=admin).json()
    assert page["total"] == 2 and {i["id"] for i in page["items"]} == {
        s1["payment"]["id"],
        s2["payment"]["id"],
    }
    only = lambda **q: pw.client.get(f"{API}/admin/payments", headers=admin, params=q).json()  # noqa: E731
    assert [i["id"] for i in only(status="successful")["items"]] == [s1["payment"]["id"]]
    assert [i["id"] for i in only(needs_review="true")["items"]] == [s2["payment"]["id"]]
    assert only(status=["successful", "failed"])["total"] == 2
    assert [i["id"] for i in only(booking_id=b1["id"])["items"]] == [s1["payment"]["id"]]
    assert only(customer_id=str(uuid.uuid4()))["total"] == 0
    assert [i["id"] for i in only(q="pay_adm1")["items"]] == [s1["payment"]["id"]]
    assert [i["id"] for i in only(q=s2["checkout"]["order_id"])["items"]] == [s2["payment"]["id"]]
    assert [i["id"] for i in only(q="FF-000002")["items"]] == [s2["payment"]["id"]]
    assert only(q="pay_nothing")["total"] == 0
    assert only(limit=1)["items"].__len__() == 1 and only(limit=1, offset=1)["items"].__len__() == 1
    row = next(i for i in page["items"] if i["id"] == s2["payment"]["id"])
    assert row["needs_review"] is True and row["review_reason"] and row["receipt"] == "FF-000002"


def test_admin_payment_search_is_safe_against_hostile_text(admin_world) -> None:
    pw, *_ = admin_world
    get = lambda q: pw.client.get(f"{API}/admin/payments", headers=pw.ctx.as_admin, params={"q": q})  # noqa: E731
    # Letters and digits that remain are matched exactly, so nothing is widened ...
    for q in ("x),or(1.eq.1", "a,b.c(d)", "'; drop table payments;--"):
        r = get(q)
        assert r.status_code == 200 and r.json()["total"] == 0, q
    # ... and text with nothing searchable left is just "no search".
    for q in ("%", "*", ",()"):
        assert get(q).status_code == 200


def test_admin_payment_date_filters(admin_world) -> None:
    pw, *_ = admin_world
    today = datetime.now(UTC).date()
    get = lambda **q: pw.client.get(f"{API}/admin/payments", headers=pw.ctx.as_admin, params=q)  # noqa: E731
    assert (
        get(
            date_from=(today - timedelta(days=1)).isoformat(),
            date_to=(today + timedelta(days=1)).isoformat(),
        ).json()["total"]
        == 2
    )
    assert get(date_from=(today + timedelta(days=2)).isoformat()).json()["total"] == 0
    assert get(date_from="2026-12-02", date_to="2026-12-01").status_code == 422


def test_admin_payment_detail_includes_the_event_log(admin_world) -> None:
    pw, (b1, s1), _ = admin_world
    pw.webhook("payment.captured", s1["checkout"]["order_id"], "pay_adm1", 9980, event_id="evt_dup")
    out = pw.client.get(
        f"{API}/admin/payments/{s1['payment']['id']}", headers=pw.ctx.as_admin
    ).json()
    assert out["id"] == s1["payment"]["id"] and out["customer_id"] == str(pw.ctx.customer.id)
    assert [e["source"] for e in out["events"]] == ["verify", "webhook"]
    assert [e["outcome"] for e in out["events"]] == ["paid", "already_processed"]
    assert (
        pw.client.get(f"{API}/admin/payments/{uuid.uuid4()}", headers=pw.ctx.as_admin).status_code
        == 404
    )


def test_only_admins_can_read_admin_payments(admin_world) -> None:
    pw, (b1, s1), _ = admin_world
    for path in ("/admin/payments", f"/admin/payments/{s1['payment']['id']}"):
        assert pw.client.get(f"{API}{path}", headers=pw.cust).status_code == 403
        assert pw.client.get(f"{API}{path}", headers=pw.ctx.as_driver).status_code == 403
        assert pw.client.get(f"{API}{path}").status_code == 401


def test_there_is_no_way_to_edit_a_payment_through_the_api(admin_world) -> None:
    pw, (b1, s1), _ = admin_world
    url = f"{API}/admin/payments/{s1['payment']['id']}"
    for method in ("patch", "put", "delete", "post"):
        r = pw.client.request(
            method.upper(), url, headers=pw.ctx.as_admin, json={"status": "failed"}
        )
        assert r.status_code == 405
    assert (
        pw.client.post(f"{API}/admin/payments", headers=pw.ctx.as_admin, json={}).status_code == 405
    )


def test_admin_booking_view_shows_the_payment_and_cannot_confirm_by_hand(admin_world) -> None:
    pw, (b1, s1), (b2, s2) = admin_world
    paid = pw.client.get(f"{API}/admin/bookings/{b1['id']}", headers=pw.ctx.as_admin).json()
    assert paid["is_paid"] is True and paid["payment"]["transaction_id"] == "pay_adm1"
    unpaid = pw.client.patch(
        f"{API}/admin/bookings/{b2['id']}/status",
        headers=pw.ctx.as_admin,
        json={"status": "confirmed"},
    )
    assert unpaid.status_code == 422
    assert pw.booking_status(b2["id"]) == "pending_payment"
