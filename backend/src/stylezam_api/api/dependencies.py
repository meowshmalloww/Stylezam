import secrets
from typing import Optional

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from ..container import Container
from ..errors import StylezamError


bearer = HTTPBearer(auto_error=False)


def get_container(request: Request) -> Container:
    return request.app.state.container


def require_api_token(
    container: Container = Depends(get_container),
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer),
) -> None:
    configured = container.settings.api_token
    if configured is None:
        return
    expected = configured.get_secret_value()
    supplied = credentials.credentials if credentials else ""
    if credentials is None or credentials.scheme.lower() != "bearer" or not secrets.compare_digest(
        supplied, expected
    ):
        raise StylezamError(
            "unauthorized",
            "A valid Stylezam service token is required.",
            status_code=401,
        )
