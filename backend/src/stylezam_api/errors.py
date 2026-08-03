from __future__ import annotations

from typing import Any, Dict, Optional


class StylezamError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        *,
        status_code: int = 400,
        retryable: bool = False,
        details: Optional[Dict[str, Any]] = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.retryable = retryable
        self.details = details or {}


class ProviderConfigurationError(StylezamError):
    def __init__(self, message: str, missing: list[str]) -> None:
        super().__init__(
            "provider_configuration_required",
            message,
            status_code=503,
            retryable=False,
            details={"missing": missing},
        )


class ProviderUpstreamError(StylezamError):
    def __init__(self, provider: str, message: str, *, retryable: bool = True) -> None:
        super().__init__(
            "provider_upstream_error",
            message,
            status_code=502,
            retryable=retryable,
            details={"provider": provider},
        )

