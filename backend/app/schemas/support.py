from decimal import Decimal

from pydantic import BaseModel


class SupportContactOut(BaseModel):
    """The garage's contact details. Empty string = not configured (do not show it)."""

    name: str
    phone: str
    whatsapp: str
    email: str
    address: str
    hours: str
    # The refund policy the garage configured ("" = none: ask the garage).
    refund_policy: str = ""
    # The default share of a booking collected up front (a package can set its own).
    advance_percent: Decimal = Decimal("20")
