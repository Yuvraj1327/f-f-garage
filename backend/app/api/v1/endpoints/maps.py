"""Address lookup for the booking screens (customers only).

The Google key stays on the server: the app sends text or a map point here and gets
addresses back. These endpoints only fill in the form; the booking endpoints still
check the PIN code and the service area themselves.
"""

from typing import Annotated

from fastapi import APIRouter, Query

from app.api.auth import CustomerDep
from app.api.deps import MapsServiceDep
from app.schemas.maps import PlaceSearchOut, SearchText

router = APIRouter(prefix="/maps", tags=["Maps"])

_RESPONSES = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Only customers can use this endpoint"},
    429: {"description": "Too many lookups in a minute"},
    503: {"description": "Address lookup is not configured or Google is unavailable"},
}


@router.get(
    "/geocode",
    response_model=PlaceSearchOut,
    summary="Find addresses from text",
    description=(
        "Up to 5 Indian addresses matching the text, each with coordinates, the PIN "
        "code taken from the address and whether we service that PIN code."
    ),
    responses=_RESPONSES,
)
def geocode(
    customer: CustomerDep,
    maps: MapsServiceDep,
    q: Annotated[SearchText, Query(description="Address, area or landmark")],
) -> PlaceSearchOut:
    return maps.search(customer.id, q)


@router.get(
    "/reverse",
    response_model=PlaceSearchOut,
    summary="Find the address at a map point",
    responses=_RESPONSES,
)
def reverse_geocode(
    customer: CustomerDep,
    maps: MapsServiceDep,
    latitude: Annotated[float, Query(ge=-90, le=90)],
    longitude: Annotated[float, Query(ge=-180, le=180)],
) -> PlaceSearchOut:
    return maps.reverse(customer.id, latitude, longitude)
