from __future__ import annotations

from pathlib import Path
from typing import Any, Dict

import httpx

from ..config import Settings
from ..errors import ProviderUpstreamError


class YouCamClothesProvider:
    id = "youcam-clothes-v3"
    name = "YouCam AI Clothes v3"

    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self.settings = settings
        self.client = client

    @property
    def configured(self) -> bool:
        return bool(self.settings.youcam_api_key)

    @property
    def headers(self) -> Dict[str, str]:
        return {
            "Authorization": "Bearer %s" % self.settings.youcam_api_key,
            "Content-Type": "application/json",
        }

    async def upload_source(self, path: Path) -> str:
        size = path.stat().st_size
        try:
            response = await self.client.post(
                "%s/s2s/v2.0/file/cloth-v3" % self.settings.youcam_base_url.rstrip("/"),
                headers=self.headers,
                json={
                    "files": [
                        {
                            "content_type": "image/jpeg",
                            "file_name": path.name,
                            "file_size": size,
                        }
                    ]
                },
                timeout=self.settings.request_timeout_seconds,
            )
            response.raise_for_status()
            payload = response.json()
            self._validate(payload)
            file_data = payload["data"]["files"][0]
            request_data = file_data["requests"][0]
            upload_headers = {
                str(key): str(value) for key, value in (request_data.get("headers") or {}).items()
            }
            put = await self.client.put(
                request_data["url"],
                headers=upload_headers,
                content=path.read_bytes(),
                timeout=self.settings.job_timeout_seconds,
            )
            put.raise_for_status()
            return str(file_data["file_id"])
        except ProviderUpstreamError:
            raise
        except (httpx.HTTPError, ValueError, KeyError, IndexError, TypeError) as exc:
            raise ProviderUpstreamError("youcam", "YouCam could not upload the person photo.") from exc

    async def create_task(
        self,
        *,
        source_file_id: str,
        reference_url: str,
        garment_category: str,
    ) -> str:
        try:
            response = await self.client.post(
                "%s/s2s/v2.0/task/cloth-v3" % self.settings.youcam_base_url.rstrip("/"),
                headers=self.headers,
                json={
                    "src_file_id": source_file_id,
                    "ref_file_url": reference_url,
                    "garment_category": garment_category,
                },
                timeout=self.settings.request_timeout_seconds,
            )
            response.raise_for_status()
            payload = response.json()
            self._validate(payload)
            return str(payload["data"]["task_id"])
        except ProviderUpstreamError:
            raise
        except (httpx.HTTPError, ValueError, KeyError, TypeError) as exc:
            raise ProviderUpstreamError("youcam", "YouCam could not create the virtual try-on task.") from exc

    async def task(self, task_id: str) -> Dict[str, Any]:
        try:
            response = await self.client.get(
                "%s/s2s/v2.0/task/cloth-v3/%s"
                % (self.settings.youcam_base_url.rstrip("/"), task_id),
                headers=self.headers,
                timeout=self.settings.request_timeout_seconds,
            )
            response.raise_for_status()
            payload = response.json()
            self._validate(payload, allow_task_error=True)
            data = payload.get("data")
            return data if isinstance(data, dict) else {}
        except ProviderUpstreamError:
            raise
        except (httpx.HTTPError, ValueError, TypeError) as exc:
            raise ProviderUpstreamError("youcam", "YouCam task status could not be retrieved.") from exc

    @staticmethod
    def _validate(payload: Dict[str, Any], *, allow_task_error: bool = False) -> None:
        status = payload.get("status")
        if status not in (None, 200):
            message = payload.get("message") or "YouCam returned an API error."
            raise ProviderUpstreamError("youcam", str(message), retryable=False)
        if not allow_task_error and isinstance(payload.get("data"), dict):
            error = payload["data"].get("error")
            if error:
                raise ProviderUpstreamError("youcam", str(error), retryable=False)

