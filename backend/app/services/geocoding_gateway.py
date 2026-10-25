"""Google Geocoding API, behind a small interface so the app and the tests never
talk to Google directly.

The API key is sent as a query parameter (that is how the Geocoding API works), so
no URL, request or raw exception text from here may ever be logged or returned:
only the exception class and Google's status code are.
"""

import logging
import re
from dataclasses import dataclass
from typing import Any, Protocol

import httpx

from app.core.config import Settings
from app.core.errors import ServiceUnavailableError

logger = logging.getLogger(__name__)

_PIN = re.compile(r"[1-9][0-9]{5}")
_UNAVAILABLE = "Address lookup is not available right now. You can still type your address."

# Google statuses that mean "we are misconfigured or out of quota", not "bad input".
_OUR_FAULT = {"REQUEST_DENIED", "OVER_QUERY_LIMIT", "OVER_DAILY_LIMIT", "UNKNOWN_ERROR"}


@dataclass(frozen=True)
class GeocodedPlace:
    formatted_address: str
    latitude: float
    longitude: float
    pincode: str | None = None
    area_name: str | None = None
    city: str | None = None
    state: str | None = None


class GeocodingGateway(Protocol):
    def search(self, text: str) -> list[GeocodedPlace]:
        """Addresses matching free text, best first. Empty when nothing matches."""
        ...

    def reverse(self, latitude: float, longitude: float) -> list[GeocodedPlace]:
        """Addresses at a point, most specific first. Empty when nothing is there."""
        ...


def _component(components: list[dict[str, Any]], *kinds: str) -> str | None:
    for kind in kinds:
        for item in components:
            if kind in item.get("types", []):
                name = item.get("long_name")
                if isinstance(name, str) and name.strip():
                    return name.strip()
    return None


def parse_place(raw: dict[str, Any]) -> GeocodedPlace | None:
    """One Google result as a place; None when it lacks an address or a position."""
    try:
        location = raw["geometry"]["location"]
        latitude = float(location["lat"])
        longitude = float(location["lng"])
        address = str(raw["formatted_address"]).strip()
    except (KeyError, TypeError, ValueError):
        return None
    if not address or not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return None
    components = raw.get("address_components") or []
    pin = _component(components, "postal_code")
    if pin is not None:
        pin = pin.replace(" ", "")
        if not _PIN.fullmatch(pin):
            pin = None
    return GeocodedPlace(
        formatted_address=address,
        latitude=latitude,
        longitude=longitude,
        pincode=pin,
        area_name=_component(
            components, "sublocality_level_1", "sublocality", "neighborhood", "locality"
        ),
        city=_component(components, "locality", "administrative_area_level_2"),
        state=_component(components, "administrative_area_level_1"),
    )


class GoogleGeocodingGateway:
    def __init__(self, settings: Settings, client: httpx.Client | None = None) -> None:
        self._base = settings.google_maps_base_url
        self._key = settings.google_maps_api_key.get_secret_value().strip()
        self._client = client or httpx.Client(timeout=settings.google_maps_timeout_seconds)

    def search(self, text: str) -> list[GeocodedPlace]:
        # India only: this garage serves Indian PIN codes.
        return self._geocode({"address": text, "components": "country:IN"})

    def reverse(self, latitude: float, longitude: float) -> list[GeocodedPlace]:
        return self._geocode({"latlng": f"{latitude:.6f},{longitude:.6f}"})

    def _geocode(self, params: dict[str, str]) -> list[GeocodedPlace]:
        query = {**params, "region": "in", "language": "en", "key": self._key}
        try:
            response = self._client.get(f"{self._base}/geocode/json", params=query)
        except httpx.HTTPError as exc:
            raise ServiceUnavailableError(
                _UNAVAILABLE,
                log_message=f"geocoding unreachable: {type(exc).__name__}",
            ) from None
        if response.status_code != 200:
            raise ServiceUnavailableError(
                _UNAVAILABLE, log_message=f"geocoding HTTP {response.status_code}"
            )
        try:
            body = response.json()
            status = str(body.get("status", ""))
        except (ValueError, AttributeError):
            raise ServiceUnavailableError(
                _UNAVAILABLE, log_message="geocoding answered with something unreadable"
            ) from None
        if status == "ZERO_RESULTS":
            return []
        if status != "OK":
            # INVALID_REQUEST is our bug or odd input; the rest is key/quota trouble.
            level = logging.ERROR if status in _OUR_FAULT else logging.WARNING
            logger.log(level, "geocoding refused: status %s", status)
            raise ServiceUnavailableError(_UNAVAILABLE, log_message=f"geocoding status {status}")
        places = (parse_place(item) for item in body.get("results", [])[:5])
        return [place for place in places if place is not None]
