"""Serviceable PIN codes: admin management and the customer PIN check."""

import uuid

import pytest

from tests.phase3_support import ctx  # noqa: F401 (pytest fixture)

API = "/api/v1"
NEW_AREA = {
    "pincode": "462001",
    "area_name": "  New   Market ",
    "city": "Bhopal",
    "state": "Madhya Pradesh",
}


def test_admin_adds_edits_deactivates_and_removes_an_area(ctx) -> None:
    created = ctx.client.post(f"{API}/admin/service-areas", headers=ctx.as_admin, json=NEW_AREA)
    assert created.status_code == 201
    area = created.json()
    assert area["area_name"] == "New Market" and area["is_active"] is True

    url = f"{API}/admin/service-areas/{area['id']}"
    assert ctx.client.get(url, headers=ctx.as_admin).json()["pincode"] == "462001"
    edited = ctx.client.patch(url, headers=ctx.as_admin, json={"area_name": "Old Market"})
    assert edited.json()["area_name"] == "Old Market" and edited.json()["pincode"] == "462001"
    off = ctx.client.patch(url, headers=ctx.as_admin, json={"is_active": False})
    assert off.json()["is_active"] is False
    assert ctx.client.delete(url, headers=ctx.as_admin).status_code == 204
    assert ctx.client.get(url, headers=ctx.as_admin).status_code == 404
    assert ctx.client.delete(url, headers=ctx.as_admin).status_code == 404


def test_pincode_whitespace_is_stripped(ctx) -> None:
    body = {**NEW_AREA, "pincode": " 462 001 "}
    assert (
        ctx.client.post(f"{API}/admin/service-areas", headers=ctx.as_admin, json=body).json()[
            "pincode"
        ]
        == "462001"
    )


def test_duplicate_pincode_is_a_conflict_on_create_and_edit(ctx) -> None:
    ctx.client.post(f"{API}/admin/service-areas", headers=ctx.as_admin, json=NEW_AREA)
    again = ctx.client.post(f"{API}/admin/service-areas", headers=ctx.as_admin, json=NEW_AREA)
    assert again.status_code == 409
    other = ctx.client.post(
        f"{API}/admin/service-areas", headers=ctx.as_admin, json={**NEW_AREA, "pincode": "462002"}
    ).json()
    clash = ctx.client.patch(
        f"{API}/admin/service-areas/{other['id']}", headers=ctx.as_admin, json={"pincode": "462001"}
    )
    assert clash.status_code == 409


@pytest.mark.parametrize(
    "pincode", ["46200", "4620011", "062001", "abcdef", "46 2001x", "", "٤٦٢٠٠١"]
)
def test_invalid_pincodes_are_rejected(ctx, pincode) -> None:
    response = ctx.client.post(
        f"{API}/admin/service-areas", headers=ctx.as_admin, json={**NEW_AREA, "pincode": pincode}
    )
    assert response.status_code == 422
    assert not ctx.areas.rows


@pytest.mark.parametrize(
    "patch",
    [{}, {"city": None}, {"is_active": None}, {"city": " "}, {"state": "x" * 81}, {"extra": 1}],
)
def test_invalid_area_patches_are_rejected(ctx, patch) -> None:
    area = ctx.areas.add()
    response = ctx.client.patch(
        f"{API}/admin/service-areas/{area.id}", headers=ctx.as_admin, json=patch
    )
    assert response.status_code == 422


def test_unknown_area_is_404(ctx) -> None:
    url = f"{API}/admin/service-areas/{uuid.uuid4()}"
    assert ctx.client.get(url, headers=ctx.as_admin).status_code == 404
    assert ctx.client.patch(url, headers=ctx.as_admin, json={"is_active": True}).status_code == 404


def test_admin_list_shows_inactive_areas_and_filters_by_city(ctx) -> None:
    ctx.areas.add("462001")
    ctx.areas.add("462002", is_active=False)
    ctx.areas.add("560001", city="Bengaluru")
    everything = ctx.client.get(f"{API}/admin/service-areas", headers=ctx.as_admin).json()
    assert [a["pincode"] for a in everything] == ["462001", "462002", "560001"]
    bhopal = ctx.client.get(f"{API}/admin/service-areas?city=bhopal", headers=ctx.as_admin).json()
    assert [a["pincode"] for a in bhopal] == ["462001", "462002"]


# ---- Customer PIN check ------------------------------------------------------------------


def test_customer_checks_a_serviceable_pincode(ctx) -> None:
    ctx.areas.add("462001")
    response = ctx.client.get(f"{API}/service-areas/check?pincode=462001", headers=ctx.as_customer)
    assert response.status_code == 200
    assert response.json() == {
        "pincode": "462001",
        "serviceable": True,
        "area_name": "New Market",
        "city": "Bhopal",
        "state": "Madhya Pradesh",
    }


def test_unknown_and_inactive_pincodes_look_identical(ctx) -> None:
    ctx.areas.add("462002", is_active=False)
    inactive = ctx.client.get(
        f"{API}/service-areas/check?pincode=462002", headers=ctx.as_customer
    ).json()
    unknown = ctx.client.get(
        f"{API}/service-areas/check?pincode=999999", headers=ctx.as_customer
    ).json()
    assert inactive == {**unknown, "pincode": "462002"}
    assert inactive["serviceable"] is False and inactive["city"] is None


@pytest.mark.parametrize("pincode", ["", "1234", "0123456", "abcdef", "46200 1"])
def test_pincode_check_validates_the_format(ctx, pincode) -> None:
    response = ctx.client.get(
        f"{API}/service-areas/check", params={"pincode": pincode}, headers=ctx.as_customer
    )
    assert response.status_code == 422


def test_pincode_check_requires_a_pincode(ctx) -> None:
    assert ctx.client.get(f"{API}/service-areas/check", headers=ctx.as_customer).status_code == 422


def test_pincode_check_is_open_to_drivers_and_admins_too(ctx) -> None:
    ctx.areas.add("462001")
    for who in (ctx.as_driver, ctx.as_admin):
        assert ctx.client.get(f"{API}/service-areas/check?pincode=462001", headers=who).json()[
            "serviceable"
        ]
