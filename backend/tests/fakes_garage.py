from typing import Any
from uuid import UUID


class FakeGarageSettings:
    def __init__(self) -> None:
        self.row: dict[str, Any] | None = None
        self.saved_by: UUID | None = None

    def get(self) -> dict[str, Any] | None:
        return self.row

    def save(self, values: dict[str, Any], admin_id: UUID) -> dict[str, Any]:
        self.row = {**values, "updated_at": "2026-10-26T10:00:00+00:00"}
        self.saved_by = admin_id
        return self.row
