"""Address lookup: customers only, PIN code extraction, serviceability from our own
areas, graceful failure, throttling, and the Google key never leaking."""

import logging

import httpx
import pytest

from app.api.deps import get_geocoding_gateway
from app.services.geocoding_gateway import GeocodedPlace, GoogleGeocodingGateway, parse_place
from tests.conftest import CONFIGURED_SUPABASE, make_settings
from tests.jwt_helpers import HS256_SECRET
from tests.phase3_support import Ctx, ctx  # noqa: F401

GEOCODE = "/api/v1/maps/geocode"
REVERSE = "/api/v1/maps/reverse"
SECRET_KEY = "AIzaSy-super-secret-server-key"


class FakeGeocoder:
    def __init__(self, places: list[GeocodedPlace] | None = None) -> None:
        self.places = places if places is not None else []
        self.searches: list[str] = []
        self.reverses: list[tuple[float, float]] = []

    def search(self, text):
        self.searches.append(text)
        return self.places

    def reverse(self, latitude, longitude):
        self.reverses.append((latitude, longitude))
        return self.places


def place(pincode: str | None = "462001", **kw) -> GeocodedPlace:
    values = {
        "formatted_address": "12 MG Road, New Market, Bhopal 462001, India",
        "latitude": 23.2599,
        "longitude": 77.4126,
        "pincode": pincode,
        "area_name": "New Market (Google)",
        "city": "Bhopal",
        "state": "Madhya Pradesh",
    }
    values.update(kw)
    return GeocodedPlace(**values)


def with_geocoder(c: Ctx, geocoder: FakeGeocoder | None) -> FakeGeocoder | None:
    c.client.app.dependency_overrides[get_geocoding_gateway] = lambda: geocoder
    return geocoder


# ---- access -----------------------------------------------------------------------------


def test_requires_sign_in(ctx: Ctx):  # noqa: F811
    with_geocoder(ctx, FakeGeocoder())
    assert ctx.client.get(GEOCODE, params={"q": "MG Road"}).status_code == 401
    assert ctx.client.get(REVERSE, params={"latitude": 1, "longitude": 1}).status_code == 401


@pytest.mark.parametrize("who", ["as_driver", "as_admin"])
def test_only_customers_may_look_up(ctx: Ctx, who):  # noqa: F811
    geocoder = with_geocoder(ctx, FakeGeocoder([place()]))
    headers = getattr(ctx, who)
    assert ctx.client.get(GEOCODE, params={"q": "MG Road"}, headers=headers).status_code == 403
    r = ctx.client.get(REVERSE, params={"latitude": 23.2, "longitude": 77.4}, headers=headers)
    assert r.status_code == 403
    assert geocoder.searches == [] and geocoder.reverses == []


# ---- results ----------------------------------------------------------------------------


def test_search_returns_places_with_pin_and_serviceability(ctx: Ctx):  # noqa: F811
    ctx.areas.add("462001")
    with_geocoder(
        ctx,
        FakeGeocoder([place("462001"), place("110001", formatted_address="Delhi"), place(None)]),
    )
    r = ctx.client.get(GEOCODE, params={"q": "MG Road Bhopal"}, headers=ctx.as_customer)
    assert r.status_code == 200
    first, second, third = r.json()["results"]
    assert first["pincode"] == "462001" and first["serviceable"] is True
    # Our own area name wins over Google's for a serviceable PIN.
    assert first["area_name"] == "New Market"
    assert second["pincode"] == "110001" and second["serviceable"] is False
    assert third["pincode"] is None and third["serviceable"] is None


def test_an_inactive_area_is_not_serviceable(ctx: Ctx):  # noqa: F811
    ctx.areas.add("462001", is_active=False)
    with_geocoder(ctx, FakeGeocoder([place("462001")]))
    body = ctx.client.get(GEOCODE, params={"q": "MG Road"}, headers=ctx.as_customer).json()
    assert body["results"][0]["serviceable"] is False


def test_reverse_geocode_passes_the_point(ctx: Ctx):  # noqa: F811
    ctx.areas.add("462001")
    geocoder = with_geocoder(ctx, FakeGeocoder([place()]))
    r = ctx.client.get(
        REVERSE, params={"latitude": 23.2599, "longitude": 77.4126}, headers=ctx.as_customer
    )
    assert r.status_code == 200
    assert geocoder.reverses == [(23.2599, 77.4126)]
    assert r.json()["results"][0]["serviceable"] is True


def test_no_match_is_an_empty_list_not_an_error(ctx: Ctx):  # noqa: F811
    with_geocoder(ctx, FakeGeocoder([]))
    r = ctx.client.get(GEOCODE, params={"q": "zzzzzz nowhere"}, headers=ctx.as_customer)
    assert r.status_code == 200 and r.json() == {"results": []}


@pytest.mark.parametrize("params", [{"q": "ab"}, {"q": "x" * 201}, {}])
def test_bad_text_is_rejected_before_google_is_called(ctx: Ctx, params):  # noqa: F811
    geocoder = with_geocoder(ctx, FakeGeocoder([place()]))
    r = ctx.client.get(GEOCODE, params=params, headers=ctx.as_customer)
    assert r.status_code == 422
    assert geocoder.searches == []


@pytest.mark.parametrize(
    "params",
    [{"latitude": 91, "longitude": 0}, {"latitude": 0, "longitude": 181}, {"latitude": 1}],
)
def test_bad_coordinates_are_rejected(ctx: Ctx, params):  # noqa: F811
    geocoder = with_geocoder(ctx, FakeGeocoder([place()]))
    assert ctx.client.get(REVERSE, params=params, headers=ctx.as_customer).status_code == 422
    assert geocoder.reverses == []


# ---- not configured / throttled ---------------------------------------------------------


def test_without_a_key_lookup_says_unavailable(ctx: Ctx):  # noqa: F811
    # No override: the real dependency sees no key in the settings.
    r = ctx.client.get(GEOCODE, params={"q": "MG Road"}, headers=ctx.as_customer)
    assert r.status_code == 503
    assert "type your address" in r.json()["detail"]
    assert "GOOGLE_MAPS_API_KEY" not in r.text


def test_the_placeholder_from_env_example_counts_as_not_configured():
    settings = make_settings(google_maps_api_key="your_server_side_maps_key")
    assert settings.maps_enabled is False
    assert make_settings(google_maps_api_key="real-key").maps_enabled is True
    assert make_settings().maps_enabled is False


def test_lookups_are_limited_per_customer():
    settings = make_settings(
        **CONFIGURED_SUPABASE, supabase_jwt_secret=HS256_SECRET, maps_requests_per_minute=3
    )
    c = Ctx(settings)
    geocoder = with_geocoder(c, FakeGeocoder([place()]))
    codes = [
        c.client.get(GEOCODE, params={"q": "MG Road"}, headers=c.as_customer).status_code
        for _ in range(5)
    ]
    assert codes == [200, 200, 200, 429, 429]
    assert len(geocoder.searches) == 3  # throttled calls never reach Google


# ---- the Google adapter -----------------------------------------------------------------

GOOGLE_OK = {
    "status": "OK",
    "results": [
        {
            "formatted_address": "12, MG Road, New Market, Bhopal, Madhya Pradesh 462001, India",
            "geometry": {"location": {"lat": 23.2599, "lng": 77.4126}},
            "address_components": [
                {"long_name": "New Market", "types": ["sublocality_level_1", "sublocality"]},
                {"long_name": "Bhopal", "types": ["locality", "political"]},
                {"long_name": "Madhya Pradesh", "types": ["administrative_area_level_1"]},
                {"long_name": "462 001", "types": ["postal_code"]},
            ],
        },
        {"formatted_address": "no position", "geometry": {}},
    ],
}


def gateway_for(handler, **settings) -> GoogleGeocodingGateway:
    client = httpx.Client(transport=httpx.MockTransport(handler))
    return GoogleGeocodingGateway(
        make_settings(google_maps_api_key=SECRET_KEY, **settings), client=client
    )


def test_adapter_parses_pin_and_skips_results_without_a_position():
    seen: list[httpx.Request] = []

    def handler(request):
        seen.append(request)
        return httpx.Response(200, json=GOOGLE_OK)

    places = gateway_for(handler).search("MG Road Bhopal")
    assert len(places) == 1
    assert places[0].pincode == "462001"  # space removed
    assert (places[0].area_name, places[0].city, places[0].state) == (
        "New Market",
        "Bhopal",
        "Madhya Pradesh",
    )
    query = dict(seen[0].url.params)
    assert query["components"] == "country:IN" and query["region"] == "in"
    assert query["key"] == SECRET_KEY and query["address"] == "MG Road Bhopal"


def test_adapter_reverse_sends_the_point():
    seen: list[httpx.Request] = []

    def handler(request):
        seen.append(request)
        return httpx.Response(200, json=GOOGLE_OK)

    gateway_for(handler).reverse(23.2599, 77.4126)
    assert dict(seen[0].url.params)["latlng"] == "23.259900,77.412600"


def test_a_postal_code_that_is_not_a_valid_pin_is_dropped():
    raw = {
        "formatted_address": "Somewhere",
        "geometry": {"location": {"lat": 1.0, "lng": 2.0}},
        "address_components": [{"long_name": "012345", "types": ["postal_code"]}],
    }
    assert parse_place(raw).pincode is None


def test_zero_results_is_empty():
    gateway = gateway_for(lambda r: httpx.Response(200, json={"status": "ZERO_RESULTS"}))
    assert gateway.search("nowhere") == []


@pytest.mark.parametrize("status", ["REQUEST_DENIED", "OVER_QUERY_LIMIT", "INVALID_REQUEST"])
def test_google_refusals_become_503_without_leaking(ctx: Ctx, status, caplog):  # noqa: F811
    def handler(request):
        return httpx.Response(
            200, json={"status": status, "error_message": f"bad key {SECRET_KEY}"}
        )

    ctx.client.app.dependency_overrides[get_geocoding_gateway] = lambda: gateway_for(handler)
    with caplog.at_level(logging.DEBUG):
        r = ctx.client.get(GEOCODE, params={"q": "MG Road"}, headers=ctx.as_customer)
    assert r.status_code == 503
    assert SECRET_KEY not in r.text
    assert SECRET_KEY not in caplog.text


def test_network_failure_becomes_503_and_the_key_is_not_logged(ctx: Ctx, caplog):  # noqa: F811
    def handler(request):
        raise httpx.ConnectError(f"cannot reach {request.url}")  # the URL holds the key

    ctx.client.app.dependency_overrides[get_geocoding_gateway] = lambda: gateway_for(handler)
    with caplog.at_level(logging.DEBUG):
        r = ctx.client.get(REVERSE, params={"latitude": 1, "longitude": 1}, headers=ctx.as_customer)
    assert r.status_code == 503
    assert SECRET_KEY not in r.text
    assert SECRET_KEY not in caplog.text


@pytest.mark.parametrize(
    "response",
    [httpx.Response(500), httpx.Response(200, content=b"<html>nope</html>")],
)
def test_http_errors_and_garbage_become_503(ctx: Ctx, response):  # noqa: F811
    ctx.client.app.dependency_overrides[get_geocoding_gateway] = lambda: gateway_for(
        lambda r: response
    )
    r = ctx.client.get(GEOCODE, params={"q": "MG Road"}, headers=ctx.as_customer)
    assert r.status_code == 503


def test_the_key_is_masked_in_settings_repr():
    assert SECRET_KEY not in repr(make_settings(google_maps_api_key=SECRET_KEY))
