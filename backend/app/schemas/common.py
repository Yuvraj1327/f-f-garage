"""Field types shared by the catalogue, service-area and availability schemas."""

from decimal import Decimal
from typing import Annotated, Any, ClassVar

from pydantic import AfterValidator, BaseModel, Field, model_validator

MAX_MONEY = Decimal("1000000")


def single_line(min_length: int, max_length: int):
    """Trims, collapses inner whitespace and enforces a length range."""

    def check(raw: str) -> str:
        value = " ".join(raw.split())
        if not min_length <= len(value) <= max_length:
            raise ValueError(f"Must be between {min_length} and {max_length} characters")
        return value

    return AfterValidator(check)


def optional_text(max_length: int):
    """Free text: trimmed, blank becomes None, length-limited. Newlines are kept."""

    def check(raw: str | None) -> str | None:
        if raw is None:
            return None
        value = raw.strip()
        if not value:
            return None
        if len(value) > max_length:
            raise ValueError(f"Must be at most {max_length} characters")
        return value

    return AfterValidator(check)


Money = Annotated[Decimal, Field(ge=0, le=MAX_MONEY, max_digits=9, decimal_places=2)]


class PatchModel(BaseModel):
    """Base for PATCH bodies: unknown fields rejected, at least one field required,
    and fields that cannot be cleared (everything except `nullable`) refuse null."""

    nullable: ClassVar[frozenset[str]] = frozenset()

    model_config = {"extra": "forbid"}

    @model_validator(mode="after")
    def _check_fields(self) -> "PatchModel":
        if not self.model_fields_set:
            raise ValueError("Provide at least one field to change")
        for name in self.model_fields_set:
            if getattr(self, name) is None and name not in self.nullable:
                raise ValueError(f"{name} cannot be null")
        return self

    def to_update_values(self) -> dict[str, Any]:
        """Only the fields the client sent, JSON-ready for PostgREST."""
        return self.model_dump(mode="json", include=self.model_fields_set)
