"""Categories, built-in services, delete/duplicate, pictures, per-package advance, models."""

import uuid

import pytest

from tests.phase3_support import Ctx, ctx  # noqa: F401
from tests.test_bookings_api import World, w  # noqa: F401
from tests.test_vehicles_api import GOOD as VEHICLE

API = "/api/v1"
JPEG = b"\xff\xd8\xff\xe0" + b"0" * 200
PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 200
WEBP = b"RIFF\x24\x00\x00\x00WEBP" + b"0" * 200
SOME_ID = str(uuid.uuid4())


def post(ctx, path, body=None, who=None, **kw):
    return ctx.client.post(API + path, headers=who or ctx.as_admin, json=body, **kw)


def patch(ctx, path, body, who=None):
    return ctx.client.patch(API + path, headers=who or ctx.as_admin, json=body)


def category(ctx, name="Brakes", tab="repair", **extra):
    r = post(ctx, "/admin/categories", {"name": name, "tab": tab, **extra})
    assert r.status_code == 201, r.text
    return r.json()


def service(ctx, name="Brake Pads", vehicle="bike", **extra):
    r = post(ctx, "/admin/services", {"name": name, "vehicle_type": vehicle, **extra})
    assert r.status_code == 201, r.text
    return r.json()


def upload(ctx, data, kind="banner", content_type="image/jpeg", who=None):
    return ctx.client.post(
        f"{API}/admin/service-images?kind={kind}",
        headers={**(ctx.as_admin if who is None else who), "Content-Type": content_type},
        content=data,
    )


# ---- Who may do what -------------------------------------------------------------------

ADMIN_ROUTES = [
    ("GET", "/admin/categories", None),
    ("POST", "/admin/categories", {"name": "Brakes"}),
    ("PATCH", f"/admin/categories/{SOME_ID}", {"name": "Brakes"}),
    ("PUT", "/admin/categories/order", {"ids": [SOME_ID]}),
    ("DELETE", f"/admin/services/{SOME_ID}", None),
    ("POST", f"/admin/services/{SOME_ID}/duplicate", None),
]


@pytest.mark.parametrize(("method", "path", "body"), ADMIN_ROUTES)
def test_the_new_admin_routes_reject_everyone_but_admins(ctx, method, path, body) -> None:  # noqa: F811
    for who, expected in ((None, 401), (ctx.as_customer, 403), (ctx.as_driver, 403)):
        r = ctx.client.request(method, API + path, headers=who or {}, json=body)
        assert r.status_code == expected, (who, r.text)
    assert not ctx.catalog.categories and not ctx.catalog.services


def test_only_admins_upload_pictures(ctx: Ctx) -> None:  # noqa: F811
    for who in ({}, ctx.as_customer, ctx.as_driver):
        assert upload(ctx, JPEG, who=who).status_code in (401, 403)
    assert not ctx.storage.files


# ---- Categories ------------------------------------------------------------------------


def test_admin_creates_renames_and_disables_categories(ctx: Ctx) -> None:  # noqa: F811
    a = category(ctx, "Brakes")
    b = category(ctx, "Chain", icon_key="chain")
    assert a["display_order"] < b["display_order"]
    assert a["is_active"] is True and a["tab"] == "repair"

    assert post(ctx, "/admin/categories", {"name": " brakes "}).status_code == 409
    assert patch(ctx, f"/admin/categories/{a['id']}", {"name": "Chain"}).status_code == 409

    r = patch(ctx, f"/admin/categories/{a['id']}", {"name": "Brake Parts", "is_active": False})
    assert r.status_code == 200 and r.json()["name"] == "Brake Parts"
    assert patch(ctx, f"/admin/categories/{SOME_ID}", {"name": "Nope"}).status_code == 404
    assert patch(ctx, f"/admin/categories/{a['id']}", {}).status_code == 422


def test_customers_see_only_active_categories_in_order(ctx: Ctx) -> None:  # noqa: F811
    a, b, c = category(ctx, "Brakes"), category(ctx, "Chain"), category(ctx, "Lights")
    patch(ctx, f"/admin/categories/{b['id']}", {"is_active": False})
    r = ctx.client.get(f"{API}/catalog/categories", headers=ctx.as_customer)
    assert [x["name"] for x in r.json()] == ["Brakes", "Lights"]
    assert ctx.client.get(f"{API}/catalog/categories").status_code == 401
    admin_view = ctx.client.get(f"{API}/admin/categories", headers=ctx.as_admin).json()
    assert len(admin_view) == 3 and c["id"] and a["id"]


def test_reordering_needs_every_category_once(ctx: Ctx) -> None:  # noqa: F811
    a, b, c = category(ctx, "A1"), category(ctx, "B2"), category(ctx, "C3")
    order = [c["id"], a["id"], b["id"]]
    r = ctx.client.put(f"{API}/admin/categories/order", headers=ctx.as_admin, json={"ids": order})
    assert r.status_code == 200
    assert [x["id"] for x in r.json()] == order
    shown = ctx.client.get(f"{API}/catalog/categories", headers=ctx.as_customer).json()
    assert [x["id"] for x in shown] == order
    for bad in ([a["id"], b["id"]], [a["id"], a["id"], b["id"], c["id"]], [SOME_ID, a["id"]]):
        r = ctx.client.put(f"{API}/admin/categories/order", headers=ctx.as_admin, json={"ids": bad})
        assert r.status_code == 422, bad


def test_a_builtin_category_cannot_change_tab(ctx: Ctx) -> None:  # noqa: F811
    made = category(ctx, "Book a Mechanic", tab="mechanic")
    ctx.catalog.categories[uuid.UUID(made["id"])] = ctx.catalog.categories[
        uuid.UUID(made["id"])
    ].model_copy(update={"system_key": "tab_mechanic"})
    assert patch(ctx, f"/admin/categories/{made['id']}", {"tab": "repair"}).status_code == 422
    assert patch(ctx, f"/admin/categories/{made['id']}", {"name": "Mechanic"}).status_code == 200


def test_a_service_follows_its_category(ctx: Ctx) -> None:  # noqa: F811
    cat = category(ctx, "Brakes")
    s = service(ctx, category_id=cat["id"])
    assert (s["category"], s["catalog_tab"], s["repair_group"]) == ("Brakes", "repair", "Brakes")
    assert s["category_id"] == cat["id"]

    patch(ctx, f"/admin/categories/{cat['id']}", {"name": "Brake Parts"})
    again = ctx.client.get(f"{API}/admin/services/{s['id']}", headers=ctx.as_admin).json()
    assert (again["category"], again["repair_group"]) == ("Brake Parts", "Brake Parts")

    engine = category(ctx, "Engine Repair", tab="engine")
    moved = patch(ctx, f"/admin/services/{s['id']}", {"category_id": engine["id"]}).json()
    assert moved["catalog_tab"] == "engine" and moved["repair_group"] is None
    assert patch(ctx, f"/admin/services/{s['id']}", {"category_id": SOME_ID}).status_code == 422


def test_a_service_without_a_category_id_is_matched_by_tab_and_group(ctx: Ctx) -> None:  # noqa: F811
    cat = category(ctx, "Cables")
    s = service(ctx, catalog_tab="repair", repair_group="cables")
    assert s["category_id"] == cat["id"]
    home = category(ctx, "Other Repairs")
    ctx.catalog.categories[uuid.UUID(home["id"])] = ctx.catalog.categories[
        uuid.UUID(home["id"])
    ].model_copy(update={"system_key": "other_repairs"})
    s2 = service(ctx, "Odd Job", catalog_tab="repair", repair_group="Unknown")
    assert s2["category_id"] == home["id"]


def test_services_in_a_disabled_category_are_hidden_from_customers(ctx: Ctx) -> None:  # noqa: F811
    cat = category(ctx, "Lights")
    s = service(ctx, "Headlight", category_id=cat["id"])
    post(ctx, f"/admin/services/{s['id']}/packages", {"name": "Std", "price": "100"})
    url = f"{API}/catalog/services"
    assert len(ctx.client.get(url, headers=ctx.as_customer).json()) == 1
    patch(ctx, f"/admin/categories/{cat['id']}", {"is_active": False})
    assert ctx.client.get(url, headers=ctx.as_customer).json() == []
    assert ctx.client.get(f"{url}/{s['id']}", headers=ctx.as_customer).status_code == 404
    assert len(ctx.client.get(f"{API}/admin/services", headers=ctx.as_admin).json()) == 1


# ---- Service and package fields --------------------------------------------------------


def test_the_new_service_fields_are_stored_and_cleaned(ctx: Ctx) -> None:  # noqa: F811
    s = service(
        ctx,
        short_description="  Quick look  ",
        banner_url="https://x.test/b.jpg",
        thumbnail_url="https://x.test/t.jpg",
        part_image_urls=["https://x.test/p1.jpg", "https://x.test/p1.jpg", "https://x.test/p2.jpg"],
        supported_makes=["Honda", " honda ", "TVS", ""],
        supported_models=["Activa 6G"],
        badge="20% OFF",
    )
    assert s["short_description"] == "Quick look"
    assert s["part_image_urls"] == ["https://x.test/p1.jpg", "https://x.test/p2.jpg"]
    assert s["supported_makes"] == ["Honda", "TVS"]
    assert s["supported_models"] == ["Activa 6G"]
    cleared = patch(ctx, f"/admin/services/{s['id']}", {"banner_url": None, "supported_makes": []})
    assert cleared.json()["banner_url"] is None and cleared.json()["supported_makes"] == []


@pytest.mark.parametrize(
    "bad",
    [
        {"short_description": "x" * 141},
        {"banner_url": "http://x.test/b.jpg"},
        {"thumbnail_url": "https://x.test/a b.jpg"},
        {"part_image_urls": [f"https://x.test/{i}.jpg" for i in range(9)]},
        {"supported_makes": ["x" * 61]},
        {"category_id": "not-a-uuid"},
    ],
)
def test_invalid_service_fields_are_refused(ctx: Ctx, bad) -> None:  # noqa: F811
    r = post(ctx, "/admin/services", {"name": "Bad", "vehicle_type": "bike", **bad})
    assert r.status_code == 422, r.text
    assert not ctx.catalog.services


def test_the_old_picture_is_the_thumbnail_when_there_is_no_new_one(ctx: Ctx) -> None:  # noqa: F811
    s = service(ctx, image_url="https://x.test/old.jpg")
    assert s["thumbnail_url"] == "https://x.test/old.jpg"


def test_package_fields(ctx: Ctx) -> None:  # noqa: F811
    s = service(ctx)
    r = post(
        ctx,
        f"/admin/services/{s['id']}/packages",
        {
            "name": "Std",
            "price": "299",
            "original_price": "399",
            "labour_charge": "199",
            "advance_percent": "30",
            "repeat_interval_days": 90,
            "included_parts": ["Brake pad", " brake pad ", "Cable"],
            "inclusions": ["Check"],
            "exclusions": ["Rotor"],
            "warranty_days": 7,
            "estimated_duration_minutes": 45,
        },
    )
    assert r.status_code == 201, r.text
    p = r.json()
    assert float(p["advance_percent"]) == 30 and float(p["labour_charge"]) == 199
    assert p["repeat_interval_days"] == 90
    assert p["included_parts"] == ["Brake pad", "Cable"]


@pytest.mark.parametrize(
    "bad",
    [
        {"labour_charge": "300"},
        {"advance_percent": "0"},
        {"advance_percent": "100.5"},
        {"repeat_interval_days": 0},
        {"original_price": "100"},
        {"included_parts": [f"part {i}" for i in range(31)]},
    ],
)
def test_invalid_package_fields_are_refused(ctx: Ctx, bad) -> None:  # noqa: F811
    s = service(ctx)
    r = post(ctx, f"/admin/services/{s['id']}/packages", {"name": "Std", "price": "299", **bad})
    assert r.status_code == 422, r.text


def test_a_price_change_is_checked_against_the_stored_labour(ctx: Ctx) -> None:  # noqa: F811
    s = service(ctx)
    p = post(
        ctx, f"/admin/services/{s['id']}/packages",
        {"name": "Std", "price": "299", "labour_charge": "250"},
    ).json()  # fmt: skip
    assert patch(ctx, f"/admin/packages/{p['id']}", {"price": "200"}).status_code == 422
    assert patch(ctx, f"/admin/packages/{p['id']}", {"labour_charge": None}).status_code == 200
    assert patch(ctx, f"/admin/packages/{p['id']}", {"price": "200"}).status_code == 200


# ---- Delete and duplicate --------------------------------------------------------------


def test_an_unbooked_service_can_be_deleted_with_its_packages(ctx: Ctx) -> None:  # noqa: F811
    s = service(ctx)
    post(ctx, f"/admin/services/{s['id']}/packages", {"name": "Std", "price": "100"})
    r = ctx.client.delete(f"{API}/admin/services/{s['id']}", headers=ctx.as_admin)
    assert r.status_code == 204
    assert not ctx.catalog.services and not ctx.catalog.packages
    again = ctx.client.delete(f"{API}/admin/services/{s['id']}", headers=ctx.as_admin)
    assert again.status_code == 404


def test_a_booked_service_cannot_be_deleted(w: World) -> None:  # noqa: F811
    assert w.book().status_code == 201
    r = w.ctx.client.delete(f"{API}/admin/services/{w.service['id']}", headers=w.ctx.as_admin)
    assert r.status_code == 409 and "bookings" in r.json()["detail"]
    assert w.ctx.catalog.services


def test_a_builtin_service_cannot_be_deleted_but_can_be_edited_and_switched_off(
    ctx: Ctx,  # noqa: F811
) -> None:
    s = service(ctx, "Book a Mechanic", "scooter")
    sid = uuid.UUID(s["id"])
    ctx.catalog.services[sid] = ctx.catalog.services[sid].model_copy(
        update={"system_key": "book_mechanic"}
    )
    assert ctx.client.delete(f"{API}/admin/services/{sid}", headers=ctx.as_admin).status_code == 409
    r = patch(ctx, f"/admin/services/{sid}", {"name": "Mechanic Visit", "is_active": False})
    assert r.status_code == 200 and r.json()["name"] == "Mechanic Visit"
    assert r.json()["system_key"] == "book_mechanic"


def test_duplicating_copies_everything_but_is_switched_off(ctx: Ctx) -> None:  # noqa: F811
    s = service(ctx, "Brake Pads", part_image_urls=["https://x.test/p.jpg"], badge="NEW")
    p = post(
        ctx, f"/admin/services/{s['id']}/packages",
        {"name": "Std", "price": "300", "inclusions": ["Fit pads"], "advance_percent": "25"},
    ).json()  # fmt: skip
    post(ctx, f"/admin/services/{s['id']}/extra-charges", {"name": "Oil", "amount": "50"})
    post(
        ctx, f"/admin/services/{s['id']}/extra-charges",
        {"name": "Washer", "amount": "10", "package_id": p["id"]},
    )  # fmt: skip

    r = post(ctx, f"/admin/services/{s['id']}/duplicate")
    assert r.status_code == 201, r.text
    copy = r.json()
    assert copy["name"] == "Brake Pads (Copy)" and copy["is_active"] is False
    assert copy["system_key"] is None and copy["badge"] == "NEW"
    assert copy["part_image_urls"] == ["https://x.test/p.jpg"]
    [pkg] = copy["packages"]
    assert pkg["id"] != p["id"] and float(pkg["advance_percent"]) == 25
    assert [c["name"] for c in pkg["extra_charges"]] == ["Washer"]
    assert [c["name"] for c in copy["extra_charges"]] == ["Oil"]

    second = post(ctx, f"/admin/services/{s['id']}/duplicate").json()
    assert second["name"] == "Brake Pads (Copy 2)"
    assert post(ctx, f"/admin/services/{SOME_ID}/duplicate").status_code == 404
    # The original is untouched, and customers never see the switched-off copy.
    shown = ctx.client.get(f"{API}/catalog/services", headers=ctx.as_customer).json()
    assert [x["id"] for x in shown] == [s["id"]]


# ---- Pictures --------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("data", "content_type", "ext"),
    [(JPEG, "image/jpeg", "jpg"), (PNG, "image/png", "png"), (WEBP, "image/webp", "webp")],
)
def test_pictures_are_checked_by_their_bytes_and_stored(ctx: Ctx, data, content_type, ext) -> None:  # noqa: F811
    r = upload(ctx, data, kind="thumbnail", content_type=content_type)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["kind"] == "thumbnail" and body["url"].endswith(f".{ext}")
    assert ctx.storage.files[body["url"]] == data


@pytest.mark.parametrize(
    "data",
    [b"", b"GIF89a....", b"<html>not a picture</html>", b"%PDF-1.4", b"RIFF1234WAVE0000"],
)
def test_other_files_are_refused_whatever_their_header_says(ctx: Ctx, data) -> None:  # noqa: F811
    assert upload(ctx, data, content_type="image/jpeg").status_code == 422
    assert not ctx.storage.files


def test_a_picture_over_5_mb_is_refused(ctx: Ctx) -> None:  # noqa: F811
    big = JPEG + b"0" * (5 * 1024 * 1024)
    r = upload(ctx, big)
    assert r.status_code == 422 and "too large" in r.json()["detail"]
    assert not ctx.storage.files


def test_an_unknown_kind_is_refused_and_storage_trouble_is_a_503(ctx: Ctx) -> None:  # noqa: F811
    assert upload(ctx, JPEG, kind="logo").status_code == 422
    ctx.storage.fail = True
    r = upload(ctx, JPEG)
    assert r.status_code == 503 and "storage" not in r.text.lower()


def test_replacing_or_removing_a_picture_cleans_up_the_old_one(ctx: Ctx) -> None:  # noqa: F811
    old = upload(ctx, JPEG).json()["url"]
    new = upload(ctx, PNG).json()["url"]
    s = service(ctx, banner_url=old)
    patch(ctx, f"/admin/services/{s['id']}", {"banner_url": new})
    assert ctx.storage.deleted == [old] and old not in ctx.storage.files
    patch(ctx, f"/admin/services/{s['id']}", {"banner_url": None})
    assert ctx.storage.deleted == [old, new]
    assert not ctx.storage.files


def test_pictures_pasted_from_elsewhere_are_never_deleted(ctx: Ctx) -> None:  # noqa: F811
    s = service(ctx, banner_url="https://elsewhere.test/b.jpg")
    patch(ctx, f"/admin/services/{s['id']}", {"banner_url": None})
    assert ctx.storage.deleted == []


def test_a_picture_another_service_uses_is_kept(ctx: Ctx) -> None:  # noqa: F811
    url = upload(ctx, JPEG).json()["url"]
    a, b = service(ctx, "A Service", banner_url=url), service(ctx, "B Service", banner_url=url)
    patch(ctx, f"/admin/services/{a['id']}", {"banner_url": None})
    assert url in ctx.storage.files and ctx.storage.deleted == []
    ctx.client.delete(f"{API}/admin/services/{b['id']}", headers=ctx.as_admin)
    assert url not in ctx.storage.files


def test_deleting_a_service_removes_its_pictures(ctx: Ctx) -> None:  # noqa: F811
    banner, part = upload(ctx, JPEG).json()["url"], upload(ctx, PNG, kind="part").json()["url"]
    s = service(ctx, banner_url=banner, part_image_urls=[part])
    ctx.client.delete(f"{API}/admin/services/{s['id']}", headers=ctx.as_admin)
    assert set(ctx.storage.deleted) == {banner, part}


# ---- Booking: advance and compatibility ------------------------------------------------


def quote(w, **over):
    r = w.ctx.client.post(
        f"{API}/bookings/quote",
        headers=w.ctx.as_customer,
        json={"package_id": w.package["id"], **over},
    )
    assert r.status_code == 200, r.text
    return r.json()


def test_the_default_advance_is_20_percent(w: World) -> None:  # noqa: F811
    q = quote(w)
    assert q["advance_percent"] in ("20", "20.00", 20)
    assert q["advance_amount"] == "99.80"


def test_a_package_can_set_its_own_advance(w: World) -> None:  # noqa: F811
    patch(w.ctx, f"/admin/packages/{w.package['id']}", {"advance_percent": "50"})
    q = quote(w)
    assert q["advance_amount"] == "249.50" and q["total_amount"] == "499.00"
    booked = w.book().json()
    assert booked["advance_amount"] == "249.50" and booked["total_amount"] == "499.00"
    patch(w.ctx, f"/admin/packages/{w.package['id']}", {"advance_percent": "10"})
    # The booking keeps the share it was made with; new quotes use the new one.
    assert quote(w)["advance_amount"] == "49.90"
    still = w.ctx.client.get(f"{API}/bookings/{booked['id']}", headers=w.ctx.as_customer).json()
    assert still["advance_amount"] == "249.50"


def test_the_server_prices_the_advance_whatever_the_client_expects(w: World) -> None:  # noqa: F811
    patch(w.ctx, f"/admin/packages/{w.package['id']}", {"advance_percent": "50"})
    r = w.book(expected_total="1.00")
    assert r.status_code == 409


def _vehicle(w, make, model):
    r = w.ctx.client.post(
        f"{API}/vehicles",
        headers=w.ctx.as_customer,
        json={**VEHICLE, "make": make, "model": model},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_a_service_limited_to_some_models_refuses_other_vehicles(w: World) -> None:  # noqa: F811
    patch(
        w.ctx,
        f"/admin/services/{w.service['id']}",
        {"supported_makes": ["Honda"], "supported_models": ["Activa 6G", "Dio"]},
    )
    wrong_make = _vehicle(w, "TVS", "Jupiter")
    r = w.book(vehicle_id=wrong_make)
    assert r.status_code == 422 and "not available for TVS Jupiter" in r.json()["detail"]

    w.ctx.client.delete(f"{API}/vehicles/{wrong_make}", headers=w.ctx.as_customer)
    wrong_model = _vehicle(w, "Honda", "Shine")
    assert w.book(vehicle_id=wrong_model).status_code == 422
    assert not w.ctx.bookings.rows

    w.ctx.client.delete(f"{API}/vehicles/{wrong_model}", headers=w.ctx.as_customer)
    ok = _vehicle(w, " honda ", "activa 6g")
    assert w.book(vehicle_id=ok).status_code == 201


def test_a_service_with_no_limits_takes_any_vehicle(w: World) -> None:  # noqa: F811
    assert w.book(vehicle_id=_vehicle(w, "Zontes", "Anything")).status_code == 201


# ---- Unsaved pictures ------------------------------------------------------------------


def test_an_unsaved_picture_can_be_thrown_away_but_a_used_one_cannot(ctx: Ctx) -> None:  # noqa: F811
    unused, used = upload(ctx, JPEG).json()["url"], upload(ctx, PNG).json()["url"]
    service(ctx, banner_url=used)
    for url in (unused, used, "https://elsewhere.test/x.jpg"):
        r = ctx.client.delete(
            f"{API}/admin/service-images", headers=ctx.as_admin, params={"url": url}
        )
        assert r.status_code == 204
    assert ctx.storage.deleted == [unused] and used in ctx.storage.files


def test_only_admins_discard_pictures(ctx: Ctx) -> None:  # noqa: F811
    url = upload(ctx, JPEG).json()["url"]
    for who, code in (({}, 401), (ctx.as_customer, 403), (ctx.as_driver, 403)):
        r = ctx.client.delete(f"{API}/admin/service-images", headers=who, params={"url": url})
        assert r.status_code == code
    assert url in ctx.storage.files


def test_the_contact_details_carry_the_default_advance(ctx: Ctx) -> None:  # noqa: F811
    r = ctx.client.get(f"{API}/support/contact", headers=ctx.as_customer)
    assert r.status_code == 200 and float(r.json()["advance_percent"]) == 20
