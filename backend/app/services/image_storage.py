"""Service pictures in Supabase Storage (bucket `service-images`, public read).

Only the backend writes: the admin app sends the picture here, the backend checks it
really is a JPEG, PNG or WebP image of an allowed size, and stores it under a random
name. Pictures that are replaced, removed or whose service is deleted are cleaned up
with `delete`; links that point somewhere else (an https link an admin pasted) are not
ours and are left alone.
"""

import logging
import secrets
from typing import Literal, Protocol
from urllib.parse import unquote

from supabase import Client

from app.core.errors import ServiceUnavailableError, UnprocessableError

logger = logging.getLogger(__name__)

BUCKET = "service-images"
ImageKind = Literal["banner", "thumbnail", "part"]
MAX_IMAGE_BYTES = 5 * 1024 * 1024

_SIGNATURES: tuple[tuple[bytes, str, str], ...] = (
    (b"\xff\xd8\xff", "image/jpeg", "jpg"),
    (b"\x89PNG\r\n\x1a\n", "image/png", "png"),
)


def sniff_image(data: bytes) -> tuple[str, str] | None:
    """(content type, extension) from the file's own bytes, never from its name."""
    for signature, content_type, extension in _SIGNATURES:
        if data.startswith(signature):
            return content_type, extension
    if len(data) > 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp", "webp"
    return None


def check_image(data: bytes, max_bytes: int = MAX_IMAGE_BYTES) -> tuple[str, str]:
    """Raises a 422 unless `data` is an allowed picture. Returns (content type, extension)."""
    if not data:
        raise UnprocessableError("The picture is empty")
    if len(data) > max_bytes:
        raise UnprocessableError(
            f"The picture is too large (at most {max_bytes // (1024 * 1024)} MB)"
        )
    found = sniff_image(data)
    if found is None:
        raise UnprocessableError("Use a JPG, PNG or WebP picture")
    return found


class ImageStorage(Protocol):
    def upload(self, kind: ImageKind, data: bytes, content_type: str, extension: str) -> str:
        """Stores the picture and returns its public https link."""

    def delete(self, url: str) -> bool:
        """Removes the picture behind `url` if it is one of ours. Never raises."""

    def owns(self, url: str) -> bool: ...


class SupabaseImageStorage:
    def __init__(self, client: Client, supabase_url: str) -> None:
        self._client = client
        self._prefix = f"{supabase_url.rstrip('/')}/storage/v1/object/public/{BUCKET}/"

    def _path(self, url: str) -> str | None:
        if not url.startswith(self._prefix):
            return None
        path = unquote(url[len(self._prefix) :].split("?", 1)[0])
        return path if path and ".." not in path else None

    def owns(self, url: str) -> bool:
        return self._path(url) is not None

    def upload(self, kind: ImageKind, data: bytes, content_type: str, extension: str) -> str:
        path = f"{kind}/{secrets.token_hex(16)}.{extension}"
        try:
            bucket = self._client.storage.from_(BUCKET)
            bucket.upload(path, data, {"content-type": content_type, "upsert": "false"})
            return f"{self._prefix}{path}"
        except Exception as exc:
            raise ServiceUnavailableError(
                "Could not save the picture right now",
                log_message=f"storage upload failed: {type(exc).__name__}",
            ) from exc

    def delete(self, url: str) -> bool:
        path = self._path(url)
        if path is None:
            return False
        try:
            self._client.storage.from_(BUCKET).remove([path])
            return True
        except Exception:
            # A leftover picture is harmless; the admin's change has already been saved.
            logger.warning("could not delete service picture %s", path, exc_info=True)
            return False
