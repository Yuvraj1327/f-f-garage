"""Application errors and their HTTP mapping.

Services raise these; the handlers registered here turn them into JSON
`{"detail": ...}` responses (the shape the Flutter app already parses).

Two rules:
  * `detail` is what the client sees: keep it generic. Operational specifics (env
    var names, upstream messages) go in `log_message` / the exception cause and
    only ever reach the server log.
  * Validation errors never echo the submitted value, so a rejected password is
    not sent back in the response body.
"""

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)


class AppError(Exception):
    status_code = 500
    default_detail = "Internal server error"

    def __init__(self, detail: str | None = None, *, log_message: str | None = None) -> None:
        self.detail = detail or self.default_detail
        self.log_message = log_message or self.detail
        super().__init__(self.log_message)


class BadRequestError(AppError):
    """The request itself is invalid (for example a webhook with a bad signature)."""

    status_code = 400
    default_detail = "Bad request"


class ForbiddenError(AppError):
    """The caller is signed in but may not do this."""

    status_code = 403
    default_detail = "You do not have permission to perform this action"


class NotFoundError(AppError):
    status_code = 404
    default_detail = "Not found"


class ConflictError(AppError):
    status_code = 409
    default_detail = "Conflict"


class UnprocessableError(AppError):
    """The request is well-formed but breaks a business or database rule."""

    status_code = 422
    default_detail = "The request could not be processed"


class UpstreamError(AppError):
    """A dependency (Supabase Auth, ...) failed or answered unexpectedly."""

    status_code = 502
    default_detail = "An upstream service returned an error"


class ServiceUnavailableError(AppError):
    """A dependency is unreachable or not configured."""

    status_code = 503
    default_detail = "Service temporarily unavailable"


def sanitize_validation_errors(errors: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Keep where and why a field failed, but drop the submitted value and context."""
    return [
        {
            "loc": list(error.get("loc", ())),
            "msg": error.get("msg", ""),
            "type": error.get("type", ""),
        }
        for error in errors
    ]


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(_request: Request, exc: AppError) -> JSONResponse:
        if exc.status_code >= 500:
            logger.warning("%s: %s", type(exc).__name__, exc.log_message, exc_info=exc.__cause__)
        return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(
        _request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={"detail": sanitize_validation_errors(list(exc.errors()))},
        )
