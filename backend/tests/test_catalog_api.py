"""Services, packages and extra charges: admin CRUD, customer browsing, validation."""

import uuid

import pytest

from tests.phase3_support import ctx  # noqa: F401 (pytest fixture)

API = "/api/v1"


# ---- Who may do what ---------------------------------------------------------------------

SOME_ID = str(uuid.uuid4())
ADMIN_ROUTES = [
    ("GET", "/admin/services", None),
    ("POST", "/admin/services", {"name": "Brake Service", "vehicle_type": "bike"}),
    ("GET", f"/admin/services/{SOME_ID}", None),
    ("PATCH", f"/admin/services/{SOME_ID}", {"name": "New Name"}),
    ("POST", f"/admin/services/{SOME_ID}/packages", {"name": "Pack", "price": "10"}),
    ("PATCH", f"/admin/packages/{SOME_ID}", {"price": "10"}),
    ("POST", f"/admin/services/{SOME_ID}/extra-charges", {"name": "Oil"}),
    ("PATCH", f"/admin/extra-charges/{SOME_ID}", {"name": "Oil"}),
    ("DELETE", f"/admin/extra-charges/{SOME_ID}", None),
    ("GET", "/admin/service-areas", None),
    (
        "POST",
        "/admin/service-areas",
        {"pincode": "462001", "area_name": "A", "city": "B", "state": "C"},
    ),
    ("GET", f"/admin/service-areas/{SOME_ID}", None),
    ("PATCH", f"/admin/service-areas/{SOME_ID}", {"is_active": False}),
    ("DELETE", f"/admin/service-areas/{SOME_ID}", None),
    ("GET", "/admin/availability/slots", None),
    ("POST", "/admin/availability/slots", {"start_time": "09:00", "end_time": "11:00"}),
    ("PATCH", f"/admin/availability/slots/{SOME_ID}", {"capacity": 2}),
    ("DELETE", f"/admin/availability/slots/{SOME_ID}", None),
    ("GET", "/admin/availability/exceptions?start_date=2026-10-20&end_date=2026-10-30", None),
    ("POST", "/admin/availability/exceptions", {"exception_date": "2026-10-25"}),
    ("PATCH", f"/admin/availability/exceptions/{SOME_ID}", {"reason": "x"}),
    ("DELETE", f"/admin/availability/exceptions/{SOME_ID}", None),
]


@pytest.mark.parametrize(("method", "path", "body"), ADMIN_ROUTES)
def test_every_admin_route_rejects_everyone_but_admins(ctx, method, path, body) -> None:
    for who, expected in ((None, 401), (ctx.as_customer, 403), (ctx.as_driver, 403)):
        response = ctx.client.request(method, API + path, headers=who or {}, json=body)
        assert response.status_code == expected, (who, response.text)
    # Nothing was written by any of the rejected attempts.
    assert not ctx.catalog.services and not ctx.catalog.packages and not ctx.catalog.extras
    assert not ctx.areas.rows and not ctx.availability.slots and not ctx.availability.exceptions


@pytest.mark.parametrize(
    "path",
    [
        "/catalog/services",
        f"/catalog/services/{SOME_ID}",
        "/service-areas/check?pincode=462001",
        "/availability?start_date=2026-10-20",
    ],
)
def test_browsing_routes_require_a_signed_in_user(ctx, path) -> None:
    assert ctx.client.get(API + path).status_code == 401


def test_a_disabled_admin_is_locked_out(ctx) -> None:
    ctx.profiles.rows[str(ctx.admin.id)] = ctx.admin.model_copy(update={"is_active": False})
    assert ctx.client.get(f"{API}/admin/services", headers=ctx.as_admin).status_code == 403


# ---- Services ----------------------------------------------------------------------------


def test_admin_creates_edits_and_disables_a_service(ctx) -> None:
    created = ctx.client.post(
        f"{API}/admin/services",
        headers=ctx.as_admin,
        json={
            "name": "  General   Service ",
            "vehicle_type": "scooter",
            "category": "Maintenance",
            "description": "  Routine service  ",
            "display_order": 2,
        },
    )
    assert created.status_code == 201
    body = created.json()
    assert body["name"] == "General Service" and body["description"] == "Routine service"
    assert body["category"] == "Maintenance" and body["is_active"] is True
    assert body["packages"] == [] and body["extra_charges"] == []

    url = f"{API}/admin/services/{body['id']}"
    edited = ctx.client.patch(
        url, headers=ctx.as_admin, json={"name": "Full Service", "description": None}
    )
    assert edited.status_code == 200
    assert edited.json()["name"] == "Full Service" and edited.json()["description"] is None
    assert edited.json()["category"] == "Maintenance", "untouched fields stay as they were"

    disabled = ctx.client.patch(url, headers=ctx.as_admin, json={"is_active": False})
    assert disabled.json()["is_active"] is False
    enabled = ctx.client.patch(url, headers=ctx.as_admin, json={"is_active": True})
    assert enabled.json()["is_active"] is True


def test_service_defaults_to_the_general_category(ctx) -> None:
    body = ctx.client.post(
        f"{API}/admin/services", headers=ctx.as_admin, json={"name": "Wash", "vehicle_type": "bike"}
    ).json()
    assert body["category"] == "General"


def test_duplicate_service_name_per_vehicle_type_is_a_conflict(ctx) -> None:
    ctx.service_with_package("General Service", "scooter")
    same = ctx.client.post(
        f"{API}/admin/services",
        headers=ctx.as_admin,
        json={"name": "general service", "vehicle_type": "scooter"},
    )
    assert same.status_code == 409
    other_vehicle = ctx.client.post(
        f"{API}/admin/services",
        headers=ctx.as_admin,
        json={"name": "General Service", "vehicle_type": "bike"},
    )
    assert other_vehicle.status_code == 201


def test_vehicle_type_cannot_be_changed(ctx) -> None:
    service, _ = ctx.service_with_package()
    response = ctx.client.patch(
        f"{API}/admin/services/{service['id']}", headers=ctx.as_admin, json={"vehicle_type": "bike"}
    )
    assert response.status_code == 422


def test_unknown_service_is_404(ctx) -> None:
    for call in (
        ctx.client.get(f"{API}/admin/services/{SOME_ID}", headers=ctx.as_admin),
        ctx.client.patch(
            f"{API}/admin/services/{SOME_ID}", headers=ctx.as_admin, json={"name": "Abc"}
        ),
        ctx.client.post(
            f"{API}/admin/services/{SOME_ID}/packages",
            headers=ctx.as_admin,
            json={"name": "Pack", "price": "1"},
        ),
    ):
        assert call.status_code == 404


@pytest.mark.parametrize(
    "body",
    [
        {"name": "A", "vehicle_type": "bike"},  # too short
        {"name": "x" * 81, "vehicle_type": "bike"},
        {"name": "   ", "vehicle_type": "bike"},
        {"name": "Brake", "vehicle_type": "car"},
        {"name": "Brake", "vehicle_type": "bike", "category": ""},
        {"name": "Brake", "vehicle_type": "bike", "display_order": -1},
        {"name": "Brake", "vehicle_type": "bike", "description": "d" * 1001},
        {"name": "Brake", "vehicle_type": "bike", "id": SOME_ID},  # unknown field
        {"name": "Brake", "vehicle_type": "bike", "is_active": "maybe"},
        {"vehicle_type": "bike"},
    ],
)
def test_invalid_service_payloads_are_rejected(ctx, body) -> None:
    response = ctx.client.post(f"{API}/admin/services", headers=ctx.as_admin, json=body)
    assert response.status_code == 422
    assert not ctx.catalog.services


@pytest.mark.parametrize("body", [{}, {"name": None}, {"is_active": None}, {"bogus": 1}])
def test_invalid_service_patches_are_rejected(ctx, body) -> None:
    service, _ = ctx.service_with_package()
    response = ctx.client.patch(
        f"{API}/admin/services/{service['id']}", headers=ctx.as_admin, json=body
    )
    assert response.status_code == 422


def test_admin_list_includes_inactive_and_filters(ctx) -> None:
    ctx.service_with_package("A Scooter Service", "scooter")
    bike, _ = ctx.service_with_package("A Bike Service", "bike")
    ctx.client.patch(
        f"{API}/admin/services/{bike['id']}", headers=ctx.as_admin, json={"is_active": False}
    )
    everything = ctx.client.get(f"{API}/admin/services", headers=ctx.as_admin).json()
    assert len(everything) == 2
    bikes = ctx.client.get(f"{API}/admin/services?vehicle_type=bike", headers=ctx.as_admin).json()
    assert [s["name"] for s in bikes] == ["A Bike Service"]
    assert (
        ctx.client.get(f"{API}/admin/services?vehicle_type=car", headers=ctx.as_admin).status_code
        == 422
    )


# ---- Packages ----------------------------------------------------------------------------


def test_admin_creates_edits_and_disables_a_package(ctx) -> None:
    service, _ = ctx.service_with_package()
    created = ctx.client.post(
        f"{API}/admin/services/{service['id']}/packages",
        headers=ctx.as_admin,
        json={
            "name": "Premium",
            "price": "899.50",
            "inclusions": ["Wash", " wash ", "", "Oil top-up", "Chain lube"],
            "estimated_duration_minutes": 90,
            "description": "Everything in Basic and more",
        },
    )
    assert created.status_code == 201
    package = created.json()
    assert package["price"] == "899.50"
    assert package["inclusions"] == ["Wash", "Oil top-up", "Chain lube"]
    assert package["estimated_duration_minutes"] == 90

    url = f"{API}/admin/packages/{package['id']}"
    edited = ctx.client.patch(
        url,
        headers=ctx.as_admin,
        json={"price": "949", "estimated_duration_minutes": None, "inclusions": ["Wash"]},
    )
    assert edited.status_code == 200
    assert edited.json()["price"] == "949" or edited.json()["price"] == "949.00"
    assert edited.json()["estimated_duration_minutes"] is None
    assert edited.json()["inclusions"] == ["Wash"]
    assert (
        ctx.client.patch(url, headers=ctx.as_admin, json={"is_active": False}).json()["is_active"]
        is False
    )


def test_duplicate_package_name_in_a_service_is_a_conflict(ctx) -> None:
    service, _ = ctx.service_with_package()  # creates "Basic"
    again = ctx.client.post(
        f"{API}/admin/services/{service['id']}/packages",
        headers=ctx.as_admin,
        json={"name": "basic", "price": "100"},
    )
    assert again.status_code == 409


@pytest.mark.parametrize(
    "body",
    [
        {"name": "Pack"},  # price required
        {"name": "Pack", "price": "-1"},
        {"name": "Pack", "price": "10.999"},  # more than 2 decimal places
        {"name": "Pack", "price": "1000000.01"},
        {"name": "Pack", "price": "abc"},
        {"name": "Pack", "price": "10", "estimated_duration_minutes": 0},
        {"name": "Pack", "price": "10", "estimated_duration_minutes": 1441},
        {"name": "Pack", "price": "10", "inclusions": ["x" * 121]},
        {"name": "Pack", "price": "10", "inclusions": [f"item {i}" for i in range(31)]},
        {"name": "P", "price": "10"},
        {"name": "Pack", "price": "10", "service_id": SOME_ID},
    ],
)
def test_invalid_package_payloads_are_rejected(ctx, body) -> None:
    service, _ = ctx.service_with_package()
    response = ctx.client.post(
        f"{API}/admin/services/{service['id']}/packages", headers=ctx.as_admin, json=body
    )
    assert response.status_code == 422, response.text


def test_free_package_is_allowed(ctx) -> None:
    service, _ = ctx.service_with_package()
    response = ctx.client.post(
        f"{API}/admin/services/{service['id']}/packages",
        headers=ctx.as_admin,
        json={"name": "Free Check", "price": "0"},
    )
    assert response.status_code == 201


# ---- Extra charges -----------------------------------------------------------------------


def test_admin_manages_extra_charges(ctx) -> None:
    service, package = ctx.service_with_package()
    oil = ctx.client.post(
        f"{API}/admin/services/{service['id']}/extra-charges",
        headers=ctx.as_admin,
        json={"charge_type": "engine_oil", "name": "Engine oil 10W-30", "amount": "350"},
    )
    assert oil.status_code == 201 and oil.json()["package_id"] is None
    part = ctx.client.post(
        f"{API}/admin/services/{service['id']}/extra-charges",
        headers=ctx.as_admin,
        json={"charge_type": "spare_part", "name": "Air filter", "package_id": package["id"]},
    )
    assert part.status_code == 201 and part.json()["amount"] is None, "at actuals"

    detail = ctx.client.get(f"{API}/admin/services/{service['id']}", headers=ctx.as_admin).json()
    assert [e["name"] for e in detail["extra_charges"]] == ["Engine oil 10W-30"]
    assert [e["name"] for e in detail["packages"][0]["extra_charges"]] == ["Air filter"]

    url = f"{API}/admin/extra-charges/{oil.json()['id']}"
    edited = ctx.client.patch(url, headers=ctx.as_admin, json={"amount": "400", "is_active": False})
    assert edited.status_code == 200 and edited.json()["is_active"] is False
    assert (
        ctx.client.patch(url, headers=ctx.as_admin, json={"amount": None}).json()["amount"] is None
    )
    assert ctx.client.delete(url, headers=ctx.as_admin).status_code == 204
    assert ctx.client.delete(url, headers=ctx.as_admin).status_code == 404


def test_extra_charge_for_another_services_package_is_rejected(ctx) -> None:
    service, _ = ctx.service_with_package("First Service")
    _, other_package = ctx.service_with_package("Second Service")
    response = ctx.client.post(
        f"{API}/admin/services/{service['id']}/extra-charges",
        headers=ctx.as_admin,
        json={"name": "Part", "package_id": other_package["id"]},
    )
    assert response.status_code == 422
    assert not ctx.catalog.extras


@pytest.mark.parametrize(
    "body",
    [
        {"name": "Oil", "amount": "-5"},
        {"name": "Oil", "charge_type": "tax"},
        {"name": "O"},
        {"name": "Oil", "amount": "1.234"},
        {"name": "Oil", "service_id": SOME_ID},
    ],
)
def test_invalid_extra_charges_are_rejected(ctx, body) -> None:
    service, _ = ctx.service_with_package()
    response = ctx.client.post(
        f"{API}/admin/services/{service['id']}/extra-charges", headers=ctx.as_admin, json=body
    )
    assert response.status_code == 422


# ---- What customers see ------------------------------------------------------------------


def test_customers_see_only_active_services_packages_and_charges(ctx) -> None:
    service, basic = ctx.service_with_package("General Service", "scooter")
    premium = ctx.client.post(
        f"{API}/admin/services/{service['id']}/packages",
        headers=ctx.as_admin,
        json={"name": "Premium", "price": "899"},
    ).json()
    ctx.client.patch(
        f"{API}/admin/packages/{premium['id']}", headers=ctx.as_admin, json={"is_active": False}
    )
    for name, active in (("Engine oil", True), ("Old oil", False)):
        ctx.client.post(
            f"{API}/admin/services/{service['id']}/extra-charges",
            headers=ctx.as_admin,
            json={"name": name, "charge_type": "engine_oil", "is_active": active},
        )

    listing = ctx.client.get(f"{API}/catalog/services", headers=ctx.as_customer)
    assert listing.status_code == 200
    (only,) = listing.json()
    assert [p["name"] for p in only["packages"]] == ["Basic"]
    assert [e["name"] for e in only["extra_charges"]] == ["Engine oil"]
    assert (
        ctx.client.get(
            f"{API}/catalog/services/{service['id']}", headers=ctx.as_customer
        ).status_code
        == 200
    )


def test_disabled_services_and_services_without_packages_are_hidden(ctx) -> None:
    hidden, _ = ctx.service_with_package("Hidden Service", "bike")
    ctx.client.patch(
        f"{API}/admin/services/{hidden['id']}", headers=ctx.as_admin, json={"is_active": False}
    )
    empty = ctx.client.post(
        f"{API}/admin/services",
        headers=ctx.as_admin,
        json={"name": "Empty Service", "vehicle_type": "bike"},
    ).json()
    shown, _ = ctx.service_with_package("Shown Service", "bike")

    names = [
        s["name"] for s in ctx.client.get(f"{API}/catalog/services", headers=ctx.as_customer).json()
    ]
    assert names == ["Shown Service"]
    for service_id in (hidden["id"], empty["id"]):
        assert (
            ctx.client.get(
                f"{API}/catalog/services/{service_id}", headers=ctx.as_customer
            ).status_code
            == 404
        )
    assert (
        ctx.client.get(f"{API}/catalog/services/{shown['id']}", headers=ctx.as_driver).status_code
        == 200
    )


def test_customer_filters_by_vehicle_type_and_category(ctx) -> None:
    ctx.service_with_package("Scooter Service", "scooter")
    bike, _ = ctx.service_with_package("Bike Wash", "bike")
    ctx.client.patch(
        f"{API}/admin/services/{bike['id']}", headers=ctx.as_admin, json={"category": "Washing"}
    )
    assert (
        len(
            ctx.client.get(
                f"{API}/catalog/services?vehicle_type=bike", headers=ctx.as_customer
            ).json()
        )
        == 1
    )
    washing = ctx.client.get(
        f"{API}/catalog/services?category=washing", headers=ctx.as_customer
    ).json()
    assert [s["name"] for s in washing] == ["Bike Wash"]


def test_customers_cannot_use_a_write_verb_on_catalog_routes(ctx) -> None:
    for method in ("POST", "PUT", "PATCH", "DELETE"):
        response = ctx.client.request(method, f"{API}/catalog/services", headers=ctx.as_customer)
        assert response.status_code == 405
