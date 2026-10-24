"""What the booking repository asks Supabase for (stub clients), and the search filter's
handling of hostile text. These cannot prove a real Supabase accepts the queries."""

import uuid
from datetime import UTC, date, datetime

import pytest
from postgrest.exceptions import APIError

from app.core.config import Settings
from app.core.errors import ConflictError, ServiceUnavailableError
from app.db.booking_repository import (
    ALREADY_BOOKED,
    SLOT_FULL,
    SupabaseBookingRepository,
    search_filter,
)
from app.db.postgrest import run, run_counted
from app.domain.enums import BookingStatus, VehicleType
from tests.test_supabase_adapters import StubQuery

NOW = datetime.now(UTC).isoformat()


def booking_row(**over):
    return {
        "id": str(uuid.uuid4()),
        "booking_number": 12,
        "customer_id": str(uuid.uuid4()),
        "service_id": str(uuid.uuid4()),
        "package_id": str(uuid.uuid4()),
        "vehicle_type": "scooter",
        "status": "pending_payment",
        "customer_name": "Asha",
        "customer_phone": "+919876543210",
        "address_line": "12 MG Road",
        "landmark": None,
        "city": "Bhopal",
        "state": "Madhya Pradesh",
        "pincode": "462001",
        "service_area_id": None,
        "latitude": None,
        "longitude": None,
        "scheduled_date": "2026-10-21",
        "slot_start": "09:00:00",
        "slot_end": "11:00:00",
        "service_name": "General Service",
        "package_name": "Basic",
        "package_inclusions": ["Wash"],
        "estimated_duration_minutes": 90,
        "package_price": 499,
        "extra_charges_total": 350.0,
        "total_amount": 849.0,
        "customer_notes": None,
        "cancellation_reason": None,
        "cancelled_by": None,
        "client_request_id": None,
        "confirmed_at": None,
        "completed_at": None,
        "cancelled_at": None,
        "created_at": NOW,
        "updated_at": NOW,
        "booking_extra_charges": [
            {
                "id": str(uuid.uuid4()),
                "extra_charge_id": None,
                "charge_type": "engine_oil",
                "name": "Engine oil",
                "amount": 350,
                "included_in_total": True,
            }
        ],
        **over,
    }


class Client:
    def __init__(self, *results) -> None:
        self.queries = [StubQuery(r) for r in results]
        self.tables: list[str] = []
        self.rpcs: list[tuple[str, dict]] = []
        self._i = 0

    def _next(self) -> StubQuery:
        q = self.queries[min(self._i, len(self.queries) - 1)]
        self._i += 1
        return q

    def table(self, name):
        self.tables.append(name)
        return self._next()

    def rpc(self, name, params):
        self.rpcs.append((name, params))
        return self._next()


class CountingQuery(StubQuery):
    def execute(self):
        r = super().execute()
        r.count = 7
        return r


def api_error(code, message="boom", details=""):
    return APIError({"code": code, "message": message, "details": details, "hint": ""})


# ---- Rows become records -----------------------------------------------------------------


def test_rows_are_parsed_with_embedded_charges_and_two_decimal_money() -> None:
    client = Client([booking_row()])
    record = SupabaseBookingRepository(client).get(uuid.uuid4())
    assert record is not None
    assert str(record.package_price) == "499.00"
    assert str(record.total_amount) == "849.00"
    assert [c.name for c in record.extra_charges] == ["Engine oil"]
    assert client.tables == ["bookings"]
    calls = client.queries[0].calls
    assert calls[0] == ("select", ("*, booking_extra_charges(*)",), {})


def test_get_returns_none_for_no_rows() -> None:
    assert SupabaseBookingRepository(Client([])).get(uuid.uuid4()) is None


# ---- create ------------------------------------------------------------------------------


def test_create_calls_the_atomic_function_then_reads_the_booking_back() -> None:
    row = booking_row()
    client = Client([{"id": row["id"]}], [row])
    values = {"customer_id": "c", "package_price": "499.00"}
    charges = [{"name": "Engine oil", "included_in_total": True}]
    record = SupabaseBookingRepository(client).create(values, charges)
    assert client.rpcs == [("create_booking", {"p_booking": values, "p_charges": charges})]
    assert str(record.id) == row["id"]


def test_create_without_a_row_is_unavailability() -> None:
    with pytest.raises(ServiceUnavailableError):
        SupabaseBookingRepository(Client([])).create({}, [])


@pytest.mark.parametrize(
    ("message", "details", "expected"),
    [
        ("slot_full: that time slot has no places left", "", SLOT_FULL),
        (
            "duplicate key value violates unique constraint",
            'Key ... "bookings_one_active_per_customer_slot"',
            ALREADY_BOOKED,
        ),
    ],
)
def test_create_conflicts_have_specific_messages(message, details, expected) -> None:
    code = "23P01" if "slot_full" in message else "23505"
    client = Client(api_error(code, message, details))
    with pytest.raises(ConflictError) as caught:
        SupabaseBookingRepository(client).create({}, [])
    assert caught.value.detail == expected


def test_an_unknown_conflict_uses_the_default_message() -> None:
    with pytest.raises(ConflictError) as caught:
        run(StubQuery(api_error("23505", "mystery")))
    assert caught.value.detail == "This conflicts with an existing entry"


# ---- search ------------------------------------------------------------------------------


def test_search_builds_every_filter_and_pages() -> None:
    client = Client([booking_row()])
    client.queries = [CountingQuery([booking_row()])]
    customer = uuid.uuid4()
    records, total = SupabaseBookingRepository(client).search(
        statuses=[BookingStatus.CONFIRMED, BookingStatus.CANCELLED],
        vehicle_type=VehicleType.BIKE,
        date_from=date(2026, 10, 20),
        date_to=date(2026, 10, 25),
        pincode="462001",
        customer_id=customer,
        query="FF-000012",
        limit=10,
        offset=20,
    )
    assert (len(records), total) == (1, 7)
    calls = client.queries[0].calls
    assert calls[0] == ("select", ("*, booking_extra_charges(*)",), {"count": "exact"})
    names = [c[0] for c in calls]
    assert names == [
        "select",
        "eq",
        "in_",
        "eq",
        "gte",
        "lte",
        "eq",
        "or_",
        "order",
        "order",
        "range",
    ]
    assert ("eq", ("customer_id", str(customer)), {}) in calls
    assert ("in_", ("status", ["confirmed", "cancelled"]), {}) in calls
    assert ("eq", ("vehicle_type", "bike"), {}) in calls
    assert ("gte", ("scheduled_date", "2026-10-20"), {}) in calls
    assert ("lte", ("scheduled_date", "2026-10-25"), {}) in calls
    assert ("eq", ("pincode", "462001"), {}) in calls
    assert ("order", ("created_at",), {"desc": True}) in calls
    assert ("range", (20, 29), {}) in calls


def test_search_without_filters_only_sorts_and_pages() -> None:
    client = Client([])
    client.queries = [CountingQuery([])]
    SupabaseBookingRepository(client).search(limit=25, offset=0)
    assert [c[0] for c in client.queries[0].calls] == ["select", "order", "order", "range"]


def test_customer_history_is_filtered_by_customer() -> None:
    client = Client([])
    client.queries = [CountingQuery([])]
    customer = uuid.uuid4()
    SupabaseBookingRepository(client).list_for_customer(customer, statuses=None, limit=20, offset=0)
    assert ("eq", ("customer_id", str(customer)), {}) in client.queries[0].calls


def test_run_counted_falls_back_to_the_row_count() -> None:
    assert run_counted(StubQuery([1, 2, 3])) == ([1, 2, 3], 3)
    assert run_counted(StubQuery(None)) == ([], 0)


# ---- update ------------------------------------------------------------------------------


def test_update_is_conditional_on_the_current_status() -> None:
    row = booking_row()
    client = Client([row], [row])
    repo = SupabaseBookingRepository(client)
    repo.update(
        uuid.UUID(row["id"]),
        {"status": "cancelled"},
        only_statuses=[BookingStatus.PENDING_PAYMENT, BookingStatus.CONFIRMED],
    )
    calls = client.queries[0].calls
    assert calls[0] == ("update", ({"status": "cancelled"},), {})
    assert ("eq", ("id", row["id"]), {}) in calls
    assert ("in_", ("status", ["pending_payment", "confirmed"]), {}) in calls


def test_update_returns_none_when_the_status_moved_on() -> None:
    assert (
        SupabaseBookingRepository(Client([])).update(
            uuid.uuid4(), {"x": 1}, only_statuses=[BookingStatus.CONFIRMED]
        )
        is None
    )


# ---- The admin search box ----------------------------------------------------------------


def test_search_filter_recognises_booking_numbers_and_phones() -> None:
    assert search_filter("FF-000012") == "booking_number.eq.12,customer_name.ilike.*FF-000012*"
    assert search_filter("ff12") == "booking_number.eq.12,customer_name.ilike.*ff12*"
    assert search_filter("12") == "booking_number.eq.12,customer_name.ilike.*12*"
    phone = search_filter("98765 43210")
    assert "customer_phone.ilike.*9876543210*" in phone
    assert "booking_number" not in phone, "a phone number is not a booking number"
    assert search_filter("Ravi Kumar") == "customer_name.ilike.*Ravi Kumar*"


@pytest.mark.parametrize("hostile", ["a,b", "x)(", "*", "%_", "name.eq.1,or(id.gt.0)", "\\", ";--"])
def test_search_filter_drops_characters_that_could_change_the_filter(hostile) -> None:
    result = search_filter(hostile)
    if result is None:
        return
    # One ilike on the name (plus an optional number match); the user text cannot add
    # clauses, parentheses or wildcards.
    assert all(c not in result.replace(",customer_name", "").replace("*", "") for c in "()%\\")
    parts = result.split(",")
    assert parts[-1].startswith("customer_name.ilike.*") and parts[-1].endswith("*")
    assert len(parts) <= 2


def test_blank_search_adds_no_filter() -> None:
    assert search_filter("   ") is None
    assert search_filter("%,()") is None


# ---- Settings ----------------------------------------------------------------------------


def test_cancel_cutoff_setting_defaults_and_bounds() -> None:
    assert Settings(_env_file=None).booking_cancel_cutoff_hours == 4
    assert Settings(_env_file=None, booking_cancel_cutoff_hours=0).booking_cancel_cutoff_hours == 0
    for bad in (-1, 169):
        with pytest.raises(ValueError):
            Settings(_env_file=None, booking_cancel_cutoff_hours=bad)
