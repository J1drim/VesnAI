"""In-process async background job queue.

Long-running work (enrichment, image generation, the search agent, retraining)
is submitted as a job with an id, status and progress. Clients poll
``GET /v1/jobs/{id}`` or subscribe via SSE. This is the single-binary backend;
the same interface can be backed by arq+Redis for distributed deployments.
"""

from __future__ import annotations

import asyncio
import traceback
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from enum import Enum
from typing import Any

from vesnai.ids import uuid7
from vesnai.observability import get_logger, metrics

log = get_logger("vesnai.jobs")


class JobStatus(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


@dataclass
class Job:
    id: str
    kind: str
    status: JobStatus = JobStatus.QUEUED
    progress: float = 0.0
    message: str = ""
    result: Any = None
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "status": self.status.value,
            "progress": round(self.progress, 4),
            "message": self.message,
            "result": self.result,
            "error": self.error,
        }


class JobContext:
    """Handle passed to job functions for reporting progress."""

    def __init__(self, job: Job) -> None:
        self._job = job

    def progress(self, value: float, message: str = "") -> None:
        self._job.progress = max(0.0, min(1.0, value))
        if message:
            self._job.message = message


JobFunc = Callable[[JobContext], Awaitable[Any]]


class JobQueue:
    def __init__(self, concurrency: int = 2) -> None:
        self._jobs: dict[str, Job] = {}
        self._queue: asyncio.Queue[tuple[Job, JobFunc]] = asyncio.Queue()
        self._workers: list[asyncio.Task] = []
        self._concurrency = concurrency
        self._listeners: list[Callable[[Job], None]] = []
        self._started = False

    def on_complete(self, callback: Callable[[Job], None]) -> None:
        self._listeners.append(callback)

    async def start(self) -> None:
        if self._started:
            return
        self._started = True
        self._workers = [asyncio.create_task(self._worker()) for _ in range(self._concurrency)]

    async def stop(self) -> None:
        for w in self._workers:
            w.cancel()
        self._workers.clear()
        self._started = False

    def submit(self, kind: str, func: JobFunc) -> Job:
        job = Job(id=uuid7(), kind=kind)
        self._jobs[job.id] = job
        self._queue.put_nowait((job, func))
        metrics.inc("vesnai_jobs_submitted_total", kind=kind)
        return job

    def get(self, job_id: str) -> Job | None:
        return self._jobs.get(job_id)

    def all(self) -> list[Job]:
        return list(self._jobs.values())

    async def run_to_completion(self, kind: str, func: JobFunc) -> Job:
        """Submit and await a single job (handy for tests and synchronous flows)."""
        job = self.submit(kind, func)
        await self._run_one(job, func)
        return job

    async def _worker(self) -> None:
        while True:
            job, func = await self._queue.get()
            await self._run_one(job, func)
            self._queue.task_done()

    async def _run_one(self, job: Job, func: JobFunc) -> None:
        job.status = JobStatus.RUNNING
        try:
            job.result = await func(JobContext(job))
            job.status = JobStatus.SUCCEEDED
            job.progress = 1.0
            metrics.inc("vesnai_jobs_succeeded_total", kind=job.kind)
        except Exception as exc:  # noqa: BLE001 - jobs must never crash the worker
            job.status = JobStatus.FAILED
            job.error = str(exc)
            log.error("job_failed", job_id=job.id, kind=job.kind, error=str(exc),
                      traceback=traceback.format_exc())
            metrics.inc("vesnai_jobs_failed_total", kind=job.kind)
        for cb in self._listeners:
            try:
                cb(job)
            except Exception:  # noqa: BLE001
                log.warning("job_listener_error", job_id=job.id)
