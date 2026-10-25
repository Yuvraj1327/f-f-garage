"""Address lookup for customers: free text or a map point in, addresses out, each
with its PIN code and whether we service it.

Serviceability is decided by our own service-area table (the same check the booking
uses), never by Google. This service only helps fill in the form: the booking
endpoints still validate the PIN code themselves.
"""

import logging
import time
from collections import deque
from collections.abc import Callable
from uuid import UUID

from app.core.errors import ServiceUnavailableError, TooManyRequestsError
from app.schemas.maps import PlaceOut, PlaceSearchOut
from app.services.geocoding_gateway import GeocodedPlace, GeocodingGateway
from app.services.service_area_service import ServiceAreaService

logger = logging.getLogger(__name__)

_WINDOW_SECONDS = 60.0
_NOT_AVAILABLE = "Address lookup is not available right now. You can still type your address."


class RateLimiter:
    """At most `limit` hits per user per minute, counted in this process.

    A coarse guard for the Google quota, not a security boundary: with several worker
    processes each has its own counts, so the real ceiling is limit x workers.
    """

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self._hits: dict[UUID, deque[float]] = {}

    def check(self, user: UUID, limit: int) -> None:
        now = self._clock()
        hits = self._hits.setdefault(user, deque())
        while hits and now - hits[0] >= _WINDOW_SECONDS:
            hits.popleft()
        if len(hits) >= limit:
            raise TooManyRequestsError(
                "You are searching too quickly. Please wait a moment and try again."
            )
        hits.append(now)
        if len(self._hits) > 5000:  # forget users who have gone quiet
            quiet = [k for k, v in self._hits.items() if not v or now - v[-1] >= _WINDOW_SECONDS]
            for key in quiet:
                del self._hits[key]


class MapsService:
    def __init__(
        self,
        gateway: GeocodingGateway | None,
        areas: ServiceAreaService,
        limiter: RateLimiter,
        *,
        requests_per_minute: int,
    ) -> None:
        self._gateway = gateway
        self._areas = areas
        self._limiter = limiter
        self._limit = requests_per_minute

    def search(self, user: UUID, text: str) -> PlaceSearchOut:
        gateway = self._ready(user)
        return PlaceSearchOut(results=[self._place(p) for p in gateway.search(text)])

    def reverse(self, user: UUID, latitude: float, longitude: float) -> PlaceSearchOut:
        gateway = self._ready(user)
        return PlaceSearchOut(
            results=[self._place(p) for p in gateway.reverse(latitude, longitude)]
        )

    def _ready(self, user: UUID) -> GeocodingGateway:
        if self._gateway is None:
            raise ServiceUnavailableError(
                _NOT_AVAILABLE,
                log_message="address lookup requested but GOOGLE_MAPS_API_KEY is not set",
            )
        self._limiter.check(user, self._limit)
        return self._gateway

    def _place(self, place: GeocodedPlace) -> PlaceOut:
        serviceable = None
        area_name = place.area_name
        city = place.city
        state = place.state
        if place.pincode is not None:
            check = self._areas.check_pincode(place.pincode)
            serviceable = check.serviceable
            if check.serviceable:
                # Our own names for the area win: they are what the booking records.
                area_name = check.area_name or area_name
                city = check.city or city
                state = check.state or state
        return PlaceOut(
            formatted_address=place.formatted_address,
            latitude=place.latitude,
            longitude=place.longitude,
            pincode=place.pincode,
            area_name=area_name,
            city=city,
            state=state,
            serviceable=serviceable,
        )
