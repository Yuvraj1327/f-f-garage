"""Address lookup (geocoding) for the booking screens."""

from typing import Annotated

from pydantic import BaseModel, Field

from app.schemas.common import single_line

SearchText = Annotated[str, single_line(3, 200)]


class PlaceOut(BaseModel):
    """One address Google found, with what the booking form needs from it.

    `pincode` is the 6-digit Indian PIN code taken from the address (None when the
    result has none, e.g. a district). `serviceable` answers "do we visit this PIN?"
    from our own service areas, never from Google; it is None when there is no PIN.
    """

    formatted_address: str
    latitude: Annotated[float, Field(ge=-90, le=90)]
    longitude: Annotated[float, Field(ge=-180, le=180)]
    pincode: str | None = None
    area_name: str | None = None
    city: str | None = None
    state: str | None = None
    serviceable: bool | None = None


class PlaceSearchOut(BaseModel):
    results: list[PlaceOut]
