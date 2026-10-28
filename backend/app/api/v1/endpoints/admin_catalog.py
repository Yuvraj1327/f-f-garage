"""Admin-only management of services, packages and extra charges."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request, status
from starlette.concurrency import run_in_threadpool

from app.api.auth import AdminDep
from app.api.deps import CatalogServiceDep
from app.core.errors import UnprocessableError
from app.domain.enums import VehicleType
from app.schemas.catalog import (
    CategoryCreate,
    CategoryOut,
    CategoryReorder,
    CategoryUpdate,
    ExtraChargeCreate,
    ExtraChargeOut,
    ExtraChargeUpdate,
    ImageUploadOut,
    PackageCreate,
    PackageDetail,
    PackageUpdate,
    ServiceCreate,
    ServiceDetail,
    ServiceUpdate,
)
from app.services.image_storage import MAX_IMAGE_BYTES, ImageKind  # noqa: E402

router = APIRouter(prefix="/admin", tags=["Admin: Services"])

_ADMIN = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Caller is not an admin"},
}
_CONFLICT = {**_ADMIN, 409: {"description": "Name already in use"}}


@router.get(
    "/services", response_model=list[ServiceDetail], summary="List all services", responses=_ADMIN
)
def list_services(
    _admin: AdminDep,
    service: CatalogServiceDep,
    vehicle_type: VehicleType | None = None,
    category: Annotated[str | None, Query(min_length=1, max_length=60)] = None,
) -> list[ServiceDetail]:
    """Including inactive services, packages and charges."""
    return service.list_all(vehicle_type, category)


@router.post(
    "/services",
    response_model=ServiceDetail,
    status_code=status.HTTP_201_CREATED,
    summary="Create a service",
    responses=_CONFLICT,
)
def create_service(
    payload: ServiceCreate, admin: AdminDep, service: CatalogServiceDep
) -> ServiceDetail:
    return service.create_service(admin, payload)


@router.get(
    "/services/{service_id}",
    response_model=ServiceDetail,
    summary="Get a service",
    responses=_ADMIN,
)
def get_service(service_id: UUID, _admin: AdminDep, service: CatalogServiceDep) -> ServiceDetail:
    return service.get(service_id)


@router.patch(
    "/services/{service_id}",
    response_model=ServiceDetail,
    summary="Edit, enable or disable a service",
    responses=_CONFLICT,
)
def update_service(
    service_id: UUID,
    payload: ServiceUpdate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> ServiceDetail:
    return service.update_service(admin, service_id, payload)


@router.post(
    "/services/{service_id}/packages",
    response_model=PackageDetail,
    status_code=status.HTTP_201_CREATED,
    summary="Add a package to a service",
    responses=_CONFLICT,
)
def create_package(
    service_id: UUID,
    payload: PackageCreate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> PackageDetail:
    return service.create_package(admin, service_id, payload)


@router.patch(
    "/packages/{package_id}",
    response_model=PackageDetail,
    summary="Edit, enable or disable a package",
    responses=_CONFLICT,
)
def update_package(
    package_id: UUID,
    payload: PackageUpdate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> PackageDetail:
    return service.update_package(admin, package_id, payload)


@router.post(
    "/services/{service_id}/extra-charges",
    response_model=ExtraChargeOut,
    status_code=status.HTTP_201_CREATED,
    summary="Add an extra charge (spare part, engine oil, other)",
    responses=_ADMIN,
)
def create_extra_charge(
    service_id: UUID,
    payload: ExtraChargeCreate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> ExtraChargeOut:
    """Leave `package_id` empty for a charge that applies to every package."""
    return service.create_extra_charge(admin, service_id, payload)


@router.patch(
    "/extra-charges/{charge_id}",
    response_model=ExtraChargeOut,
    summary="Edit, enable or disable an extra charge",
    responses=_ADMIN,
)
def update_extra_charge(
    charge_id: UUID,
    payload: ExtraChargeUpdate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> ExtraChargeOut:
    return service.update_extra_charge(admin, charge_id, payload)


@router.delete(
    "/extra-charges/{charge_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an extra charge",
    responses=_ADMIN,
)
def delete_extra_charge(charge_id: UUID, admin: AdminDep, service: CatalogServiceDep) -> None:
    service.delete_extra_charge(admin, charge_id)


@router.delete(
    "/services/{service_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a service that was never booked",
    responses={**_ADMIN, 409: {"description": "Built-in service, or it has bookings"}},
)
def delete_service(service_id: UUID, admin: AdminDep, service: CatalogServiceDep) -> None:
    service.delete_service(admin, service_id)


@router.post(
    "/services/{service_id}/duplicate",
    response_model=ServiceDetail,
    status_code=status.HTTP_201_CREATED,
    summary="Copy a service (switched off) with its packages and extra charges",
    responses=_ADMIN,
)
def duplicate_service(
    service_id: UUID, admin: AdminDep, service: CatalogServiceDep
) -> ServiceDetail:
    return service.duplicate_service(admin, service_id)


# ---- Categories ------------------------------------------------------------------------


@router.get(
    "/categories",
    response_model=list[CategoryOut],
    summary="All categories, including disabled ones",
    responses=_ADMIN,
)
def list_categories(_admin: AdminDep, service: CatalogServiceDep) -> list[CategoryOut]:
    return service.list_categories(active_only=False)


@router.post(
    "/categories",
    response_model=CategoryOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a category",
    responses=_CONFLICT,
)
def create_category(
    payload: CategoryCreate, admin: AdminDep, service: CatalogServiceDep
) -> CategoryOut:
    return service.create_category(admin, payload)


@router.put(
    "/categories/order",
    response_model=list[CategoryOut],
    summary="Set the display order of the categories",
    responses=_ADMIN,
)
def reorder_categories(
    payload: CategoryReorder, admin: AdminDep, service: CatalogServiceDep
) -> list[CategoryOut]:
    return service.reorder_categories(admin, payload)


@router.patch(
    "/categories/{category_id}",
    response_model=CategoryOut,
    summary="Rename, move, enable or disable a category",
    responses=_CONFLICT,
)
def update_category(
    category_id: UUID,
    payload: CategoryUpdate,
    admin: AdminDep,
    service: CatalogServiceDep,
) -> CategoryOut:
    return service.update_category(admin, category_id, payload)


# ---- Pictures --------------------------------------------------------------------------


@router.post(
    "/service-images",
    response_model=ImageUploadOut,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a service picture (the request body is the image itself)",
    responses={**_ADMIN, 422: {"description": "Not a JPG/PNG/WebP picture, or too large"}},
)
async def upload_service_image(
    request: Request, kind: ImageKind, admin: AdminDep, service: CatalogServiceDep
) -> ImageUploadOut:
    """Send the raw picture bytes (Content-Type image/jpeg, image/png or image/webp).
    The bytes themselves are checked, at most 5 MB. Then save the returned `url` on the
    service as its banner, thumbnail or one of its part pictures."""
    declared = request.headers.get("content-length")
    if declared and declared.isdigit() and int(declared) > MAX_IMAGE_BYTES:
        raise UnprocessableError("The picture is too large (at most 5 MB)")
    data = bytearray()
    async for chunk in request.stream():
        data += chunk
        if len(data) > MAX_IMAGE_BYTES:
            raise UnprocessableError("The picture is too large (at most 5 MB)")
    return await run_in_threadpool(service.upload_image, admin, kind, bytes(data))


@router.delete(
    "/service-images",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Throw away a picture that was uploaded but not saved on a service",
    responses=_ADMIN,
)
async def discard_service_image(
    url: Annotated[str, Query(min_length=10, max_length=500)],
    admin: AdminDep,
    service: CatalogServiceDep,
) -> None:
    """Only pictures in this app's own storage that no service uses are removed; anything
    else is left alone (the call still succeeds)."""
    await run_in_threadpool(service.discard_image, admin, url)
