"""Runs a PostgREST query and turns database failures into application errors.

Constraint violations are the database doing its job (a duplicate name, a bad
value, an overlapping slot); they become 409/422 with a fixed message. Anything
else is treated as the database being unavailable, and the details stay in the
server log.
"""

from typing import Any

import httpx
from postgrest.exceptions import APIError

from app.core.errors import ConflictError, ServiceUnavailableError, UnprocessableError

_INVALID_VALUE_CODES = {"23514", "23502", "22P02", "22007", "22008", "22003", "22001"}


def _execute(
    query: Any,
    conflict: str,
    in_use: str,
    conflict_hints: dict[str, str] | None,
) -> Any:
    try:
        return query.execute()
    except APIError as exc:
        code = str(exc.code or "")
        if code in ("23505", "23P01"):
            text = f"{exc.message} {exc.details} {exc.hint}"
            message = next(
                (m for hint, m in (conflict_hints or {}).items() if hint in text), conflict
            )
            raise ConflictError(message, log_message=f"{code}: {exc.message}") from exc
        if code == "23503":
            raise ConflictError(in_use, log_message=f"{code}: {exc.message}") from exc
        if code in _INVALID_VALUE_CODES:
            raise UnprocessableError(
                "Some values are not valid", log_message=f"{code}: {exc.message}"
            ) from exc
        raise ServiceUnavailableError("Database is unavailable") from exc
    except httpx.HTTPError as exc:
        raise ServiceUnavailableError("Database is unavailable") from exc


def run(
    query: Any,
    *,
    conflict: str = "This conflicts with an existing entry",
    in_use: str = "This item is in use or refers to something that no longer exists",
    conflict_hints: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    """Executes `query` and returns its rows (an empty list when there are none).

    `conflict_hints` maps a text found in the database error (a constraint name, a
    marker such as `slot_full`) to a more specific 409 message.
    """
    response = _execute(query, conflict, in_use, conflict_hints)
    data = response.data
    return data if isinstance(data, list) else []


def run_counted(query: Any) -> tuple[list[dict[str, Any]], int]:
    """Like `run` for a query built with `count="exact"`: rows plus the total count."""
    response = _execute(query, "This conflicts with an existing entry", "In use", None)
    data = response.data if isinstance(response.data, list) else []
    count = getattr(response, "count", None)
    return data, int(count) if count is not None else len(data)
