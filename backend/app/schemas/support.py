from pydantic import BaseModel


class SupportContactOut(BaseModel):
    """The garage's contact details. Empty string = not configured (do not show it)."""

    name: str
    phone: str
    whatsapp: str
    email: str
    address: str
    hours: str
