"""Query shapes of the new catalogue calls and the Storage adapter (stub clients)."""

import uuid
from datetime import UTC, datetime

import pytest

from app.core.errors import ConflictError, ServiceUnavailableError
from app.db.catalog_repository import SupabaseCatalogRepository
from app.services.image_storage import BUCKET, SupabaseImageStorage, sniff_image
from tests.test_catalog_adapters import api_error
from tests.test_supabase_adapters import StubClient

NOW = datetime.now(UTC).isoformat()
BASE = "https://proj.supabase.co"
PREFIX = f"{BASE}/storage/v1/object/public/{BUCKET}/"


def category_row(**over):
    return {
        "id": str(uuid.uuid4()),
        "name": "Brakes",
        "tab": "repair",
        "icon_key": None,
        "display_order": 40,
        "is_active": True,
        "system_key": None,
        "created_at": NOW,
        "updated_at": NOW,
        **over,
    }


def test_categories_are_read_in_display_order_and_can_be_limited_to_active() -> None:
    client = StubClient([category_row()])
    rows = SupabaseCatalogRepository(client).list_categories(active_only=True)
    assert [c.name for c in rows] == ["Brakes"]
    assert client.tables == ["service_categories"]
    assert client.query.calls == [
        ("select", ("*",), {}),
        ("eq", ("is_active", True), {}),
        ("order", ("display_order",), {}),
        ("order", ("name",), {}),
    ]


def test_a_duplicate_category_name_is_a_conflict() -> None:
    repo = SupabaseCatalogRepository(StubClient(api_error("23505")))
    with pytest.raises(ConflictError) as caught:
        repo.create_category({"name": "Brakes"})
    assert "already exists" in caught.value.detail


def test_updating_a_missing_category_returns_none() -> None:
    assert (
        SupabaseCatalogRepository(StubClient([])).update_category(uuid.uuid4(), {"name": "X"})
        is None
    )


def test_deleting_a_booked_service_says_to_switch_it_off() -> None:
    repo = SupabaseCatalogRepository(StubClient(api_error("23503")))
    with pytest.raises(ConflictError) as caught:
        repo.delete_service(uuid.uuid4())
    assert "Switch it off" in caught.value.detail


def test_delete_service_reports_whether_a_row_went() -> None:
    assert SupabaseCatalogRepository(StubClient([{"id": "x"}])).delete_service(uuid.uuid4())
    assert not SupabaseCatalogRepository(StubClient([])).delete_service(uuid.uuid4())


# ---- Storage ---------------------------------------------------------------------------


class StubBucket:
    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.uploads: list[tuple] = []
        self.removed: list[list[str]] = []

    def upload(self, path, data, options):
        if self.fail:
            raise RuntimeError("secret upstream detail")
        self.uploads.append((path, data, options))

    def remove(self, paths):
        if self.fail:
            raise RuntimeError("boom")
        self.removed.append(paths)


class StubStorageClient:
    def __init__(self, bucket: StubBucket) -> None:
        self.bucket = bucket
        self.names: list[str] = []
        self.storage = self

    def from_(self, name):
        self.names.append(name)
        return self.bucket


def storage(fail=False):
    bucket = StubBucket(fail)
    client = StubStorageClient(bucket)
    return SupabaseImageStorage(client, BASE + "/"), bucket, client


def test_upload_stores_under_a_random_name_and_returns_the_public_link() -> None:
    s, bucket, client = storage()
    url = s.upload("banner", b"data", "image/jpeg", "jpg")
    [(path, data, options)] = bucket.uploads
    assert client.names == [BUCKET] and data == b"data"
    assert path.startswith("banner/") and path.endswith(".jpg") and url == PREFIX + path
    assert options["content-type"] == "image/jpeg" and options["upsert"] == "false"
    assert s.upload("banner", b"data", "image/jpeg", "jpg") != url


def test_a_failed_upload_is_a_generic_503() -> None:
    s, _, _ = storage(fail=True)
    with pytest.raises(ServiceUnavailableError) as caught:
        s.upload("part", b"x", "image/png", "png")
    assert "secret" not in caught.value.detail


def test_only_our_own_links_are_owned_or_deleted() -> None:
    s, bucket, _ = storage()
    assert s.owns(PREFIX + "banner/a.jpg")
    assert not s.owns("https://elsewhere.test/a.jpg")
    assert not s.owns(f"{BASE}/storage/v1/object/public/other-bucket/a.jpg")
    assert s.delete("https://elsewhere.test/a.jpg") is False
    assert s.delete(PREFIX + "../secrets/x.jpg") is False
    assert bucket.removed == []
    assert s.delete(PREFIX + "banner/a%20b.jpg?v=2") is True
    assert bucket.removed == [["banner/a b.jpg"]]


def test_a_failed_delete_never_raises() -> None:
    s, _, _ = storage(fail=True)
    assert s.delete(PREFIX + "banner/a.jpg") is False


def test_pictures_are_recognised_by_their_bytes() -> None:
    assert sniff_image(b"\xff\xd8\xff\xdb....") == ("image/jpeg", "jpg")
    assert sniff_image(b"\x89PNG\r\n\x1a\n....") == ("image/png", "png")
    assert sniff_image(b"RIFF\x00\x00\x00\x00WEBPVP8 ") == ("image/webp", "webp")
    assert sniff_image(b"GIF89a") is None and sniff_image(b"") is None
