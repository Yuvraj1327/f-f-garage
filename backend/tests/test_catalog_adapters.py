"""Query shapes and error mapping of the Phase 3 Supabase adapters (stub clients).

They prove what we ASK the database for, not that a real Supabase accepts it.
"""

import uuid
from datetime import UTC, date, datetime, time

import httpx
import pytest
from postgrest.exceptions import APIError

from app.core.config import Settings
from app.core.errors import (
    ConflictError,
    ServiceUnavailableError,
    UnprocessableError,
)
from app.db.availability_repository import SupabaseAvailabilityRepository
from app.db.catalog_repository import SupabaseCatalogRepository
from app.db.postgrest import run
from app.db.service_area_repository import SupabaseServiceAreaRepository
from app.domain.enums import VehicleType
from tests.conftest import make_settings
from tests.test_supabase_adapters import StubClient, StubQuery

NOW = datetime.now(UTC).isoformat()


def service_row(**over):
    return {
        "id": str(uuid.uuid4()),
        "name": "General Service",
        "vehicle_type": "scooter",
        "category": "General",
        "description": None,
        "display_order": 0,
        "is_active": True,
        "created_at": NOW,
        "updated_at": NOW,
        **over,
    }


def api_error(code: str) -> APIError:
    return APIError({"code": code, "message": "boom", "details": "", "hint": ""})


# ---- run(): error mapping ----------------------------------------------------------------


@pytest.mark.parametrize(
    ("code", "expected"),
    [
        ("23505", ConflictError),
        ("23P01", ConflictError),
        ("23503", ConflictError),
        ("23514", UnprocessableError),
        ("22P02", UnprocessableError),
        ("23502", UnprocessableError),
        ("42501", ServiceUnavailableError),
        ("PGRST000", ServiceUnavailableError),
    ],
)
def test_database_errors_map_to_application_errors(code, expected) -> None:
    with pytest.raises(expected) as caught:
        run(StubQuery(api_error(code)))
    assert "boom" not in caught.value.detail, "database messages must not reach clients"


def test_network_failures_are_unavailability() -> None:
    with pytest.raises(ServiceUnavailableError):
        run(StubQuery(httpx.ConnectError("down")))


def test_a_custom_conflict_message_is_used() -> None:
    with pytest.raises(ConflictError) as caught:
        run(StubQuery(api_error("23505")), conflict="Already there")
    assert caught.value.detail == "Already there"


def test_non_list_data_is_treated_as_empty() -> None:
    assert run(StubQuery(None)) == []


# ---- Catalogue ---------------------------------------------------------------------------


def test_list_services_filters_and_orders() -> None:
    client = StubClient([service_row()])
    repo = SupabaseCatalogRepository(client)
    repo.list_services(vehicle_type=VehicleType.BIKE, category="50%_off", active_only=True)
    assert client.tables == ["services"]
    assert client.query.calls == [
        ("select", ("*",), {}),
        ("eq", ("vehicle_type", "bike"), {}),
        ("ilike", ("category", "50\\%\\_off"), {}),
        ("eq", ("is_active", True), {}),
        ("order", ("vehicle_type",), {}),
        ("order", ("display_order",), {}),
        ("order", ("name",), {}),
    ]


def test_public_service_lookup_filters_on_active() -> None:
    client = StubClient([])
    assert SupabaseCatalogRepository(client).get_service(uuid.uuid4(), active_only=True) is None
    assert ("eq", ("is_active", True), {}) in client.query.calls


def test_create_service_inserts_and_maps_a_duplicate_to_a_conflict() -> None:
    repo = SupabaseCatalogRepository(StubClient([service_row()]))
    assert repo.create_service({"name": "General Service", "vehicle_type": "scooter"}).name
    with pytest.raises(ConflictError) as caught:
        SupabaseCatalogRepository(StubClient(api_error("23505"))).create_service({})
    assert "already exists" in caught.value.detail


def test_list_packages_with_no_services_makes_no_query() -> None:
    client = StubClient([])
    assert SupabaseCatalogRepository(client).list_packages([]) == []
    assert client.tables == []


def test_list_packages_uses_in_filter() -> None:
    client = StubClient([])
    ids = [uuid.uuid4(), uuid.uuid4()]
    SupabaseCatalogRepository(client).list_packages(ids, active_only=True)
    assert ("in_", ("service_id", [str(i) for i in ids]), {}) in client.query.calls


def test_create_package_adds_the_service_id() -> None:
    client = StubClient([])
    service_id = uuid.uuid4()
    with pytest.raises(IndexError):  # the stub returns no row; we only inspect the call
        SupabaseCatalogRepository(client).create_package(service_id, {"name": "Basic"})
    assert client.query.calls[0] == (
        "insert",
        ({"name": "Basic", "service_id": str(service_id)},),
        {},
    )


def test_delete_extra_charge_reports_whether_a_row_was_removed() -> None:
    assert SupabaseCatalogRepository(StubClient([{"id": "x"}])).delete_extra_charge(uuid.uuid4())
    assert not SupabaseCatalogRepository(StubClient([])).delete_extra_charge(uuid.uuid4())


# ---- Service areas -----------------------------------------------------------------------


def test_pincode_lookup_shape() -> None:
    client = StubClient([])
    assert SupabaseServiceAreaRepository(client).get_by_pincode("462001") is None
    assert client.tables == ["service_areas"]
    assert client.query.calls == [
        ("select", ("*",), {}),
        ("eq", ("pincode", "462001"), {}),
        ("limit", (1,), {}),
    ]


def test_duplicate_pincode_maps_to_a_helpful_conflict() -> None:
    repo = SupabaseServiceAreaRepository(StubClient(api_error("23505")))
    with pytest.raises(ConflictError) as caught:
        repo.create({"pincode": "462001"})
    assert "PIN code" in caught.value.detail


# ---- Availability ------------------------------------------------------------------------


def test_slot_overlap_maps_to_a_conflict_with_a_clear_message() -> None:
    repo = SupabaseAvailabilityRepository(StubClient(api_error("23P01")))
    with pytest.raises(ConflictError) as caught:
        repo.create_slot({"start_time": "09:00", "end_time": "11:00"})
    assert "overlaps" in caught.value.detail


def test_exceptions_are_listed_by_inclusive_date_range() -> None:
    client = StubClient([])
    SupabaseAvailabilityRepository(client).list_exceptions(date(2026, 10, 1), date(2026, 10, 31))
    assert client.tables == ["availability_exceptions"]
    assert client.query.calls == [
        ("select", ("*",), {}),
        ("gte", ("exception_date", "2026-10-01"), {}),
        ("lte", ("exception_date", "2026-10-31"), {}),
        ("order", ("exception_date",), {}),
    ]


class RpcClient:
    def __init__(self, result) -> None:
        self.query = StubQuery(result)
        self.calls: list[tuple[str, dict]] = []

    def rpc(self, name, params):
        self.calls.append((name, params))
        return self.query


def test_booked_counts_call_the_database_function_and_parse_rows() -> None:
    client = RpcClient(
        [
            {
                "scheduled_date": "2026-10-20",
                "slot_start": "09:00:00",
                "slot_end": "11:00:00",
                "booked": 2,
            }
        ]
    )
    counts = SupabaseAvailabilityRepository(client).booked_counts(
        date(2026, 10, 20), date(2026, 10, 21)
    )
    assert client.calls == [("slot_booking_counts", {"p_from": "2026-10-20", "p_to": "2026-10-21"})]
    assert counts == {(date(2026, 10, 20), time(9, 0), time(11, 0)): 2}


def test_malformed_booked_counts_are_reported_as_unavailable() -> None:
    client = RpcClient([{"scheduled_date": "nonsense"}])
    with pytest.raises(ServiceUnavailableError):
        SupabaseAvailabilityRepository(client).booked_counts(date(2026, 10, 20), date(2026, 10, 21))


# ---- Settings ----------------------------------------------------------------------------


def test_availability_settings_have_sensible_defaults() -> None:
    settings = make_settings()
    assert settings.business_timezone == "Asia/Kolkata"
    assert settings.booking_window_days == 30 and settings.booking_lead_minutes == 120


@pytest.mark.parametrize(
    "overrides",
    [
        {"business_timezone": "Mars/Olympus"},
        {"business_timezone": ""},
        {"booking_window_days": 0},
        {"booking_window_days": 366},
        {"booking_lead_minutes": -1},
    ],
)
def test_invalid_availability_settings_are_refused(overrides) -> None:
    with pytest.raises(ValueError):
        Settings(_env_file=None, app_env="test", **overrides)
