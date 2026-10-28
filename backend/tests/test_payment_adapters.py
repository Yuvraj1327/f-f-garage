"""The Razorpay HTTP client (against a mock transport), the Supabase payment repository
(stub clients) and the payment settings. These prove what we send and how we read answers;
they cannot prove the real Razorpay or Supabase accept it."""

import json
import uuid
from datetime import UTC, datetime

import httpx
import pytest
from pydantic import ValidationError

from app.core.errors import ConflictError, ServiceUnavailableError, UpstreamError
from app.db.payment_repository import (
    OPEN_ATTEMPT,
    SupabasePaymentRepository,
    payment_search_filter,
)
from app.domain.enums import BookingStatus, PaymentStatus
from app.services.payment_gateway import RazorpayGateway
from tests.conftest import make_settings
from tests.test_booking_adapters import Client, CountingQuery, api_error

SETTINGS = make_settings(
    payment_gateway_provider="razorpay",
    payment_gateway_key_id="rzp_test_abc123",
    payment_gateway_key_secret="key-secret-xyz",  # noqa: S106
)
NOW = datetime.now(UTC).isoformat()


# ---- Razorpay HTTP client ------------------------------------------------------------------


def gateway(handler) -> RazorpayGateway:
    return RazorpayGateway(SETTINGS, httpx.Client(transport=httpx.MockTransport(handler)))


def test_create_order_sends_the_exact_amount_with_basic_auth() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"id": "order_X1", "amount": 84900, "currency": "INR"})

    order = gateway(handler).create_order(
        amount_paise=84900, currency="INR", receipt="FF-000012", notes={"booking_id": "b"}
    )
    assert (order.id, order.amount_paise, order.currency) == ("order_X1", 84900, "INR")
    request = seen[0]
    assert request.method == "POST" and str(request.url) == "https://api.razorpay.com/v1/orders"
    body = json.loads(request.content)
    assert body == {
        "amount": 84900,
        "currency": "INR",
        "receipt": "FF-000012",
        "notes": {"booking_id": "b"},
        "payment_capture": 1,
    }
    import base64

    assert (
        request.headers["authorization"]
        == "Basic " + base64.b64encode(b"rzp_test_abc123:key-secret-xyz").decode()
    )


def test_create_order_refuses_an_answer_with_a_different_amount() -> None:
    gw = gateway(
        lambda r: httpx.Response(200, json={"id": "order_X1", "amount": 100, "currency": "INR"})
    )
    with pytest.raises(UpstreamError):
        gw.create_order(amount_paise=84900, currency="INR", receipt="r", notes={})


@pytest.mark.parametrize(
    ("response", "error"),
    [
        (
            httpx.Response(400, json={"error": {"code": "BAD_REQUEST", "description": "x"}}),
            UpstreamError,
        ),
        (httpx.Response(200, json={"nope": 1}), UpstreamError),
        (httpx.Response(200, text="<html>"), UpstreamError),
        (
            httpx.Response(401, json={"error": {"description": "Authentication failed"}}),
            ServiceUnavailableError,
        ),
        (httpx.Response(502), ServiceUnavailableError),
        (httpx.Response(503), ServiceUnavailableError),
    ],
)
def test_create_order_failures_map_to_application_errors(response, error) -> None:
    with pytest.raises(error):
        gateway(lambda r: response).create_order(
            amount_paise=100, currency="INR", receipt="r", notes={}
        )


def test_network_failure_is_service_unavailable_and_leaks_nothing() -> None:
    def boom(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("secret-host.internal refused")

    with pytest.raises(ServiceUnavailableError) as info:
        gateway(boom).create_order(amount_paise=100, currency="INR", receipt="r", notes={})
    assert "secret-host" not in info.value.detail
    assert "key-secret-xyz" not in info.value.detail + info.value.log_message


def test_fetch_payment_reads_the_gateway_record() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.method == "GET" and request.url.path == "/v1/payments/pay_1"
        return httpx.Response(
            200,
            json={
                "id": "pay_1",
                "order_id": "order_1",
                "amount": 49900,
                "currency": "INR",
                "status": "captured",
                "method": "upi",
                "email": "someone@example.com",
            },
        )

    payment = gateway(handler).fetch_payment("pay_1")
    assert payment is not None
    assert (payment.order_id, payment.amount_paise, payment.status, payment.method) == (
        "order_1",
        49900,
        "captured",
        "upi",
    )


def test_fetch_payment_unknown_id_is_none() -> None:
    assert gateway(lambda r: httpx.Response(404, json={})).fetch_payment("pay_x") is None
    assert gateway(lambda r: httpx.Response(400, json={})).fetch_payment("pay_x") is None


def test_fetch_payment_outage_and_garbage() -> None:
    with pytest.raises(ServiceUnavailableError):
        gateway(lambda r: httpx.Response(500)).fetch_payment("pay_1")
    with pytest.raises(UpstreamError):
        gateway(lambda r: httpx.Response(200, json={"id": "pay_1"})).fetch_payment("pay_1")


# ---- Supabase repository -------------------------------------------------------------------


def payment_row(**over):
    return {
        "id": str(uuid.uuid4()),
        "booking_id": str(uuid.uuid4()),
        "customer_id": str(uuid.uuid4()),
        "provider": "razorpay",
        "provider_order_id": "order_1",
        "provider_payment_id": None,
        "idempotency_key": None,
        "amount": 849,
        "currency": "INR",
        "status": "pending",
        "failure_reason": None,
        "paid_at": None,
        "method": None,
        "receipt": "FF-000012",
        "livemode": False,
        "needs_review": False,
        "review_reason": None,
        "created_at": NOW,
        "updated_at": NOW,
        **over,
    }


def test_create_attempt_inserts_and_parses_money() -> None:
    client = Client([payment_row()])
    record = SupabasePaymentRepository(client).create_attempt({"booking_id": "b"})
    assert client.tables == ["payments"]
    assert client.queries[0].calls[0] == ("insert", ({"booking_id": "b"},), {})
    assert str(record.amount) == "849.00" and record.status == PaymentStatus.PENDING


def test_a_second_open_attempt_is_a_conflict_with_a_clear_message() -> None:
    err = api_error(
        "23505", 'duplicate key value violates unique constraint "payments_one_pending_per_booking"'
    )
    with pytest.raises(ConflictError) as info:
        SupabasePaymentRepository(Client(err)).create_attempt({})
    assert info.value.detail == OPEN_ATTEMPT


def test_apply_event_calls_the_atomic_function_with_every_argument() -> None:
    paid = {
        "result": "paid",
        "payment_id": str(uuid.uuid4()),
        "payment_status": "successful",
        "booking_id": str(uuid.uuid4()),
        "booking_status": "confirmed",
    }
    client = Client([paid])
    out = SupabasePaymentRepository(client).apply_event(
        provider="razorpay",
        order_id="order_1",
        payment_id="pay_1",
        outcome="captured",
        amount_paise=84900,
        currency="INR",
        method="upi",
        failure=None,
        source="webhook",
        event_id="evt_1",
        event_type="payment.captured",
        detail={"k": 1},
    )
    assert (out.result, out.payment_status, out.booking_status) == (
        "paid",
        PaymentStatus.SUCCESSFUL,
        BookingStatus.CONFIRMED,
    )
    name, params = client.rpcs[0]
    assert name == "apply_payment_event"
    assert params == {
        "p_provider": "razorpay",
        "p_order_id": "order_1",
        "p_payment_id": "pay_1",
        "p_outcome": "captured",
        "p_amount_paise": 84900,
        "p_currency": "INR",
        "p_method": "upi",
        "p_failure": None,
        "p_source": "webhook",
        "p_event_id": "evt_1",
        "p_event_type": "payment.captured",
        "p_detail": {"k": 1},
    }


def test_apply_event_unknown_order_has_no_ids() -> None:
    client = Client(
        [
            {
                "result": "unknown_order",
                "payment_id": None,
                "payment_status": None,
                "booking_id": None,
                "booking_status": None,
            }
        ]
    )
    out = SupabasePaymentRepository(client).apply_event(
        provider="razorpay",
        order_id="o",
        payment_id=None,
        outcome="captured",
        amount_paise=1,
        currency="INR",
        method=None,
        failure=None,
        source="verify",
        event_id=None,
        event_type="x",
        detail=None,
    )
    assert out.result == "unknown_order" and out.payment_id is None


def test_apply_event_without_a_row_is_unavailability() -> None:
    with pytest.raises(ServiceUnavailableError):
        SupabasePaymentRepository(Client([])).apply_event(
            provider="p",
            order_id="o",
            payment_id=None,
            outcome="captured",
            amount_paise=1,
            currency="INR",
            method=None,
            failure=None,
            source="verify",
            event_id=None,
            event_type="x",
            detail=None,
        )


def test_database_failure_during_apply_is_unavailability_not_a_leak() -> None:
    err = api_error("XX000", "secret internal detail")
    with pytest.raises(ServiceUnavailableError) as info:
        SupabasePaymentRepository(Client(err)).apply_event(
            provider="p",
            order_id="o",
            payment_id=None,
            outcome="captured",
            amount_paise=1,
            currency="INR",
            method=None,
            failure=None,
            source="verify",
            event_id=None,
            event_type="x",
            detail=None,
        )
    assert "secret" not in info.value.detail


def test_cancel_open_only_touches_pending_rows() -> None:
    client = Client([payment_row(status="cancelled")])
    record = SupabasePaymentRepository(client).cancel_open(uuid.uuid4())
    calls = client.queries[0].calls
    assert ("update", ({"status": "cancelled"},), {}) in calls
    assert ("eq", ("status", "pending"), {}) in calls
    assert record is not None and record.status == PaymentStatus.CANCELLED
    assert SupabasePaymentRepository(Client([])).cancel_open(uuid.uuid4()) is None


def test_for_bookings_groups_the_attempts_newest_first() -> None:
    b1, b2 = uuid.uuid4(), uuid.uuid4()
    rows = [  # newest first, as the query orders them
        payment_row(booking_id=str(b1), status="failed", id=str(uuid.uuid4())),
        payment_row(
            booking_id=str(b1),
            status="successful",
            provider_payment_id="pay_1",
            paid_at=NOW,
            id=str(uuid.uuid4()),
        ),
        payment_row(booking_id=str(b2), status="pending", id=str(uuid.uuid4())),
        payment_row(booking_id=str(b2), status="failed", id=str(uuid.uuid4())),
    ]
    out = SupabasePaymentRepository(Client(rows)).for_bookings([b1, b2])
    assert [p.status for p in out[b1]] == [PaymentStatus.FAILED, PaymentStatus.SUCCESSFUL]
    assert [p.status for p in out[b2]] == [PaymentStatus.PENDING, PaymentStatus.FAILED]
    assert SupabasePaymentRepository(Client([])).for_bookings([]) == {}


def test_search_builds_the_expected_filters_and_returns_the_count() -> None:
    client = Client([payment_row()])
    client.queries = [CountingQuery([payment_row()])]
    rows, total = SupabasePaymentRepository(client).search(
        statuses=[PaymentStatus.FAILED],
        booking_id=uuid.uuid4(),
        customer_id=uuid.uuid4(),
        needs_review=True,
        created_from=datetime(2026, 10, 1, tzinfo=UTC),
        created_before=datetime(2026, 10, 2, tzinfo=UTC),
        query="pay_1",
        limit=10,
        offset=20,
    )
    assert total == 7 and len(rows) == 1
    names = [c[0] for c in client.queries[0].calls]
    assert names.count("eq") == 3 and {"in_", "gte", "lt", "or_", "order", "range"} <= set(names)
    assert ("range", (20, 29), {}) in client.queries[0].calls


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("pay_ABC123", "provider_order_id.eq.pay_ABC123,provider_payment_id.eq.pay_ABC123"),
        (
            "FF-000012",
            "provider_order_id.eq.FF-000012,provider_payment_id.eq.FF-000012,receipt.eq.FF-000012",
        ),
        ("12", "provider_order_id.eq.12,provider_payment_id.eq.12,receipt.eq.FF-000012"),
        ("%*,()", None),
        ("   ", None),
    ],
)
def test_payment_search_filter(text, expected) -> None:
    assert payment_search_filter(text) == expected


def test_payment_search_filter_drops_everything_that_could_change_its_meaning() -> None:
    result = payment_search_filter("x),or(a.eq.1")
    # Only letters, digits, "_" and "-" survive, so the text stays one exact-match value
    # in each of the two conditions and cannot add a condition of its own.
    assert result == "provider_order_id.eq.xoraeq1,provider_payment_id.eq.xoraeq1"


def test_log_event_inserts_into_the_event_table() -> None:
    client = Client([[]])
    SupabasePaymentRepository(client).log_event(
        provider="razorpay",
        source="verify",
        event_type="checkout.callback",
        outcome="invalid_signature",
        order_id="o",
        payment_id="p",
        payment_uuid=None,
        detail=None,
    )
    assert client.tables == ["payment_events"]
    insert = client.queries[0].calls[0]
    assert insert[0] == "insert" and insert[1][0]["outcome"] == "invalid_signature"


# ---- Settings ------------------------------------------------------------------------------


def test_payments_are_off_by_default() -> None:
    s = make_settings()
    assert not s.payments_enabled and not s.payments_live


def test_razorpay_needs_both_keys() -> None:
    with pytest.raises(ValidationError, match="KEY_ID and PAYMENT_GATEWAY_KEY_SECRET"):
        make_settings(payment_gateway_provider="razorpay", payment_gateway_key_id="rzp_test_abc")
    with pytest.raises(ValidationError):
        make_settings(payment_gateway_provider="razorpay", payment_gateway_key_secret="s")


def test_key_id_must_look_like_a_razorpay_key() -> None:
    with pytest.raises(ValidationError, match="rzp_test_"):
        make_settings(
            payment_gateway_provider="razorpay",
            payment_gateway_key_id="sk_live_x",
            payment_gateway_key_secret="s",
        )


def test_only_razorpay_is_supported() -> None:
    with pytest.raises(ValidationError):
        make_settings(payment_gateway_provider="stripe")


def test_test_and_live_keys_are_told_apart() -> None:
    test = make_settings(
        payment_gateway_provider="razorpay",
        payment_gateway_key_id="rzp_test_a1",
        payment_gateway_key_secret="s",
    )
    live = make_settings(
        payment_gateway_provider="razorpay",
        payment_gateway_key_id="rzp_live_a1",
        payment_gateway_key_secret="s",
    )
    assert test.payments_enabled and not test.payments_live
    assert live.payments_enabled and live.payments_live


def test_production_with_payments_requires_the_webhook_secret() -> None:
    from tests.conftest import CONFIGURED_SUPABASE

    common = dict(
        app_env="production",
        cors_origins="https://admin.example.com",
        **CONFIGURED_SUPABASE,
        payment_gateway_provider="razorpay",
        payment_gateway_key_id="rzp_live_a1",
        payment_gateway_key_secret="s",
    )
    with pytest.raises(ValidationError, match="WEBHOOK_SECRET"):
        make_settings(**common)
    ok = make_settings(**common, payment_gateway_webhook_secret="w")
    assert ok.is_production and ok.payments_live


def test_gateway_url_must_be_https() -> None:
    with pytest.raises(ValidationError):
        make_settings(payment_gateway_base_url="http://evil.example.com/v1")


def test_secrets_are_not_shown_in_the_settings_repr() -> None:
    s = make_settings(
        payment_gateway_provider="razorpay",
        payment_gateway_key_id="rzp_test_a1",
        payment_gateway_key_secret="super-secret-value",
        payment_gateway_webhook_secret="hook-secret-value",
    )
    text = repr(s) + str(s.model_dump())
    assert "super-secret-value" not in text and "hook-secret-value" not in text


def test_rpc_parameter_names_match_the_sql_function() -> None:
    """The adapter's argument names must be exactly the SQL function's parameters."""
    import re
    from pathlib import Path

    migrations = Path(__file__).resolve().parents[2] / "supabase" / "migrations"
    sql = "".join(p.read_text() for p in sorted(migrations.glob("*.sql")))
    match = re.search(
        r"create function public\.apply_payment_event\((.*?)\)\s*returns table", sql, re.S
    )
    assert match, "apply_payment_event not found in the migrations"
    declared = set(re.findall(r"^\s*(p_\w+)\s", match.group(1), re.M))

    client = Client([{"result": "pending"}])
    SupabasePaymentRepository(client).apply_event(
        provider="razorpay",
        order_id="o",
        payment_id=None,
        outcome="authorized",
        amount_paise=None,
        currency=None,
        method=None,
        failure=None,
        source="verify",
        event_id=None,
        event_type="x",
        detail=None,
    )
    assert set(client.rpcs[0][1]) == declared
