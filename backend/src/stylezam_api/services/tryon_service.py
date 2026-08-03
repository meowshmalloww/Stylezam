from __future__ import annotations

import asyncio
import time
from pathlib import Path

import httpx

from ..config import Settings
from ..database import Database
from ..errors import ProviderConfigurationError, ProviderUpstreamError, StylezamError
from ..providers.youcam import YouCamClothesProvider
from ..storage import MediaStorage


class TryOnService:
    def __init__(
        self,
        *,
        settings: Settings,
        database: Database,
        storage: MediaStorage,
        provider: YouCamClothesProvider,
        client: httpx.AsyncClient,
    ) -> None:
        self.settings = settings
        self.database = database
        self.storage = storage
        self.provider = provider
        self.client = client

    async def run(self, job_id: str) -> None:
        job = self.database.get_tryon(job_id)
        if not job:
            return
        try:
            await self._run(job_id, job)
        except asyncio.CancelledError:
            # A delete request removes the media after cancellation; a graceful server shutdown
            # keeps it so the persisted job can resume on the next startup.
            raise
        except BaseException:
            self.storage.delete_path(job.get("person_media_path"))
            raise
        else:
            self.storage.delete_path(job.get("person_media_path"))

    async def _run(self, job_id: str, job: dict) -> None:
        if not self.provider.configured:
            raise ProviderConfigurationError(
                "YouCam is required for virtual try-on.", ["STYLEZAM_YOUCAM_API_KEY"]
            )
        if not self.database.claim_provider_call(
            "youcam", self.settings.youcam_monthly_cap
        ):
            raise StylezamError(
                "monthly_cap_reached",
                "The Stylezam monthly cap for YouCam try-on jobs has been reached.",
                status_code=429,
            )
        source_path = Path(job["person_media_path"])
        self.database.update_tryon(
            job_id, status="processing", phase="uploading", progress=0.16
        )
        source_file_id = await self.provider.upload_source(source_path)
        task_id = await self.provider.create_task(
            source_file_id=source_file_id,
            reference_url=job["product_image_url"],
            garment_category=job["garment_category"],
        )
        self.database.update_tryon(
            job_id,
            phase="generating",
            progress=0.55,
            provider_task_id=task_id,
        )
        deadline = time.monotonic() + self.settings.job_timeout_seconds
        result_url = None
        while time.monotonic() < deadline:
            task = await self.provider.task(task_id)
            status = str(task.get("task_status") or task.get("status") or "").lower()
            error = task.get("error")
            if error or status in {"failed", "error", "cancelled"}:
                raise ProviderUpstreamError(
                    "youcam",
                    "YouCam could not generate this try-on: %s" % (error or status),
                    retryable=False,
                )
            if status in {"success", "completed", "done"}:
                results = task.get("results")
                if isinstance(results, dict):
                    result_url = results.get("url")
                elif isinstance(results, list) and results and isinstance(results[0], dict):
                    result_url = results[0].get("url")
                if result_url:
                    break
            await asyncio.sleep(3)
        if not result_url:
            raise ProviderUpstreamError(
                "youcam", "The virtual try-on did not finish before the job timeout."
            )
        self.database.update_tryon(job_id, phase="saving", progress=0.88)
        try:
            response = await self.client.get(
                str(result_url),
                follow_redirects=True,
                timeout=self.settings.request_timeout_seconds,
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise ProviderUpstreamError(
                "youcam", "The generated try-on image could not be downloaded."
            ) from exc
        stored = self.storage.save_image_bytes(response.content, prefix="tryon")
        base_url = str(job["person_image_url"]).split("media/", 1)[0]
        saved_url = "%smedia/%s" % (base_url, stored.relative_name)
        self.database.update_tryon(
            job_id,
            status="completed",
            phase="completed",
            progress=1.0,
            result_image_url=saved_url,
            error_code=None,
            error_message=None,
        )
