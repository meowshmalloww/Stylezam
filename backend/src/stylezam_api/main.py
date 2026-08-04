from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator, Optional

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from . import __version__
from .api.routes import garments, searches, system, tryons
from .config import Settings, get_settings
from .container import Container
from .errors import StylezamError
from .middleware import RequestBodyLimitMiddleware
from .schemas import ErrorDetail, ErrorResponse


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_app(settings: Optional[Settings] = None) -> FastAPI:
    resolved = settings or get_settings()
    resolved.prepare_directories()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        container = Container(resolved)
        app.state.container = container
        await container.start()
        try:
            yield
        finally:
            await container.close()

    app = FastAPI(
        title="Stylezam API",
        version=__version__,
        description="Stylezam garment capture, on-device model delivery, and bounded crop labeling.",
        lifespan=lifespan,
    )
    app.add_middleware(
        RequestBodyLimitMiddleware,
        max_bytes=resolved.request_body_max_bytes,
    )
    if resolved.allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=resolved.allowed_origins,
            allow_credentials=True,
            allow_methods=["GET", "POST", "DELETE"],
            allow_headers=["*"],
        )

    @app.exception_handler(StylezamError)
    async def stylezam_error_handler(
        request: Request, error: StylezamError
    ) -> JSONResponse:
        body = ErrorResponse(
            error=ErrorDetail(
                code=error.code,
                message=error.message,
                retryable=error.retryable,
                details=error.details,
            )
        )
        return JSONResponse(
            status_code=error.status_code,
            content=body.model_dump(mode="json", by_alias=True),
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(
        request: Request, error: RequestValidationError
    ) -> JSONResponse:
        body = ErrorResponse(
            error=ErrorDetail(
                code="request_validation_failed",
                message="One or more request fields are invalid.",
                details={"issues": error.errors()},
            )
        )
        return JSONResponse(
            status_code=422,
            content=body.model_dump(mode="json", by_alias=True),
        )

    app.include_router(system.router, prefix="/v1")
    app.include_router(garments.router, prefix="/v1")
    app.include_router(searches.router, prefix="/v1")
    app.include_router(tryons.router, prefix="/v1")
    app.mount("/media", StaticFiles(directory=str(resolved.data_dir / "media")), name="media")
    return app


app = create_app()
