from fastapi import APIRouter, Response, status

from app.api.deps import HealthServiceDep
from app.schemas.health import HealthResponse, ReadinessResponse

router = APIRouter(prefix="/health", tags=["Health"])


@router.get("", response_model=HealthResponse, summary="Liveness check")
def liveness(service: HealthServiceDep) -> HealthResponse:
    """Returns 200 whenever the API process is running."""
    return service.liveness()


@router.get(
    "/ready",
    response_model=ReadinessResponse,
    summary="Readiness check",
    responses={503: {"model": ReadinessResponse, "description": "A dependency is unavailable"}},
)
def readiness(response: Response, service: HealthServiceDep) -> ReadinessResponse:
    """Returns 200 when the database is configured and reachable, otherwise 503."""
    result = service.readiness()
    if result.status != "ready":
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return result
