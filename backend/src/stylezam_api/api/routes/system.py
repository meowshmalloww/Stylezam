from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from ... import __version__
from ...container import Container
from ...schemas import CapabilitiesResponse, HealthResponse
from ..dependencies import get_container, require_api_token


router = APIRouter(tags=["system"])


@router.get("/health", response_model=HealthResponse)
async def health(container: Container = Depends(get_container)) -> HealthResponse:
    return HealthResponse(
        status="ok",
        version=__version__,
        environment=container.settings.environment,
        now=datetime.now(timezone.utc),
    )


@router.get("/capabilities", response_model=CapabilitiesResponse)
async def capabilities(
    _: None = Depends(require_api_token),
    container: Container = Depends(get_container),
) -> CapabilitiesResponse:
    return container.capabilities()
