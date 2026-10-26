"""Customers' saved two-wheelers: list, add, change and remove."""

from uuid import UUID

from fastapi import APIRouter, Response, status

from app.api.auth import CustomerDep
from app.api.deps import VehicleServiceDep
from app.schemas.vehicle import VehicleCreate, VehicleOut, VehicleUpdate

router = APIRouter(prefix="/vehicles", tags=["Vehicles"])

_AUTH = {
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Caller is not a customer"},
}
_MISSING = {404: {"description": "No such vehicle among yours"}}


@router.get("", response_model=list[VehicleOut], summary="My vehicles", responses=_AUTH)
def list_vehicles(customer: CustomerDep, service: VehicleServiceDep) -> list[VehicleOut]:
    return service.list(customer)


@router.post(
    "",
    response_model=VehicleOut,
    status_code=status.HTTP_201_CREATED,
    summary="Save a vehicle",
    responses={
        **_AUTH,
        409: {"description": "Already saved, or the limit of 10 vehicles is reached"},
    },
)
def add_vehicle(
    payload: VehicleCreate, customer: CustomerDep, service: VehicleServiceDep
) -> VehicleOut:
    return service.create(customer, payload)


@router.patch(
    "/{vehicle_id}",
    response_model=VehicleOut,
    summary="Change a saved vehicle",
    responses={**_AUTH, **_MISSING, 409: {"description": "Registration already saved"}},
)
def change_vehicle(
    vehicle_id: UUID,
    payload: VehicleUpdate,
    customer: CustomerDep,
    service: VehicleServiceDep,
) -> VehicleOut:
    return service.update(customer, vehicle_id, payload)


@router.delete(
    "/{vehicle_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a saved vehicle",
    responses={**_AUTH, **_MISSING},
)
def remove_vehicle(vehicle_id: UUID, customer: CustomerDep, service: VehicleServiceDep) -> Response:
    """Past bookings keep their own copy of the vehicle details."""
    service.delete(customer, vehicle_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
