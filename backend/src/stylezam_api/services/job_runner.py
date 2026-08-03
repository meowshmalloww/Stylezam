from __future__ import annotations

import asyncio
import logging
from typing import Awaitable, Callable, Dict

from ..database import Database
from ..errors import StylezamError
from .search_pipeline import SearchPipeline
from .tryon_service import TryOnService


logger = logging.getLogger(__name__)


class JobRunner:
    def __init__(
        self,
        *,
        database: Database,
        search_pipeline: SearchPipeline,
        tryon_service: TryOnService,
        concurrency: int = 3,
    ) -> None:
        self.database = database
        self.search_pipeline = search_pipeline
        self.tryon_service = tryon_service
        self._semaphore = asyncio.Semaphore(concurrency)
        self._tasks: Dict[str, asyncio.Task[None]] = {}

    async def start(self) -> None:
        for job_id in self.database.list_recoverable_searches():
            self.enqueue_search(job_id)
        for job_id in self.database.list_recoverable_tryons():
            self.enqueue_tryon(job_id)

    async def stop(self) -> None:
        tasks = list(self._tasks.values())
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        self._tasks.clear()

    def enqueue_search(self, job_id: str) -> None:
        self._spawn(
            "search:%s" % job_id,
            lambda: self.search_pipeline.run(job_id),
            lambda error: self._fail_search(job_id, error),
        )

    def enqueue_tryon(self, job_id: str) -> None:
        self._spawn(
            "tryon:%s" % job_id,
            lambda: self.tryon_service.run(job_id),
            lambda error: self._fail_tryon(job_id, error),
        )

    async def cancel_search(self, job_id: str) -> None:
        await self._cancel("search:%s" % job_id)

    async def cancel_tryon(self, job_id: str) -> None:
        await self._cancel("tryon:%s" % job_id)

    async def _cancel(self, key: str) -> None:
        task = self._tasks.get(key)
        if not task:
            return
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)

    def _spawn(
        self,
        key: str,
        operation: Callable[[], Awaitable[None]],
        failure: Callable[[BaseException], None],
    ) -> None:
        existing = self._tasks.get(key)
        if existing and not existing.done():
            return

        async def wrapped() -> None:
            try:
                async with self._semaphore:
                    await operation()
            except asyncio.CancelledError:
                raise
            except BaseException as exc:
                logger.exception("Background job %s failed", key)
                failure(exc)
            finally:
                self._tasks.pop(key, None)

        self._tasks[key] = asyncio.create_task(wrapped(), name=key)

    def _fail_search(self, job_id: str, error: BaseException) -> None:
        if isinstance(error, StylezamError):
            code, message = error.code, error.message
        else:
            code, message = "internal_error", "The search job failed unexpectedly."
        self.database.update_search(
            job_id,
            status="failed",
            phase="failed",
            error_code=code,
            error_message=message,
        )

    def _fail_tryon(self, job_id: str, error: BaseException) -> None:
        if isinstance(error, StylezamError):
            code, message = error.code, error.message
        else:
            code, message = "internal_error", "The virtual try-on failed unexpectedly."
        self.database.update_tryon(
            job_id,
            status="failed",
            phase="failed",
            error_code=code,
            error_message=message,
        )
