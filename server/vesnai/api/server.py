"""FastAPI application factory."""

from __future__ import annotations

import asyncio
import contextlib
import json
import time
import uuid
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI, Request

from vesnai.api.routes import ALL_ROUTERS
from vesnai.app_state import AppState
from vesnai.observability import configure_logging, get_logger, metrics

log = get_logger("vesnai.api")


def _print_pairing_banner(state: AppState) -> None:
    """Print a pairing code + QR on interactive startup (minted in this process)."""
    try:
        import sys

        if not sys.stdout.isatty():
            return
        from vesnai.qr import qr_ascii

        code = state.auth.create_pairing_code()
        url = state.settings.public_base_url()
        payload = json.dumps({"url": url, "code": code})
        already_paired = bool(state.auth.list_devices())
        print("\n" + "=" * 60)  # noqa: T201 - intentional console UX
        if already_paired:
            print("  VesnAI ready — pair another device")  # noqa: T201
        else:
            print("  VesnAI ready — scan in the app or enter manually")  # noqa: T201
        print(f"  Server URL : {url}")  # noqa: T201
        print(f"  Pair code  : {code}  (valid 5 min)")  # noqa: T201
        if already_paired:
            print("  (Fresh code each restart; or POST /v1/auth/pair/code)")  # noqa: T201
        print("=" * 60)  # noqa: T201
        print(qr_ascii(payload))  # noqa: T201
    except Exception as exc:  # noqa: BLE001 - banner must never block startup
        log.warning("pairing_banner_failed", error=str(exc))


async def _print_pairing_banner_when_ready(state: AppState) -> None:
    """Defer the QR until after lifespan startup so the port is accepting traffic."""
    await asyncio.sleep(0)
    _print_pairing_banner(state)


@asynccontextmanager
async def _lifespan(app: FastAPI):
    state: AppState = app.state.vesnai
    # Ensure the host-only pairing bootstrap secret exists (0600 in data_dir);
    # `vesnai pair` reads it to mint codes over HTTP.
    try:
        state.auth.bootstrap_secret()
        log.info(
            "pairing_bootstrap_secret_ready",
            path=str(state.settings.data_dir / "bootstrap_secret"),
            hint="mint pairing codes with `vesnai pair` on this host",
        )
    except Exception as exc:  # noqa: BLE001 - never block startup
        log.warning("pairing_bootstrap_secret_failed", error=str(exc))
    await state.jobs.start()
    try:
        scheduled = state.reconcile_illustrations()
        if scheduled:
            log.info("auto_illustrate_reconcile", scheduled=scheduled)
    except Exception as exc:  # noqa: BLE001
        log.warning("auto_illustrate_reconcile_failed", error=str(exc))
    state.chat_turns.resume_all()
    advertiser = None
    if state.settings.advertise_mdns:
        try:
            from vesnai.discovery import ServiceAdvertiser

            advertiser = ServiceAdvertiser(
                state.settings.service_name,
                state.settings.host,
                state.settings.port,
                https=state.settings.tls_enabled,
            )
            await asyncio.to_thread(advertiser.start)
            log.info("mdns_advertised", name=state.settings.service_name)
        except Exception as exc:  # noqa: BLE001
            log.warning("mdns_failed", error=str(exc))
    banner_task = asyncio.create_task(_print_pairing_banner_when_ready(state))
    try:
        yield
    finally:
        banner_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await banner_task
        if advertiser is not None:
            await asyncio.to_thread(advertiser.stop)
        await state.jobs.stop()


def create_app(state: AppState | None = None) -> FastAPI:
    configure_logging()
    state = state or AppState()

    app = FastAPI(
        title="VesnAI",
        version="0.1.0",
        description="VesnAI second-brain server API.",
        lifespan=_lifespan,
    )
    app.state.vesnai = state

    @app.middleware("http")
    async def request_logging(request: Request, call_next):
        request_id = str(uuid.uuid4())
        structlog.contextvars.bind_contextvars(request_id=request_id, path=request.url.path)
        start = time.monotonic()
        try:
            response = await call_next(request)
        finally:
            structlog.contextvars.clear_contextvars()
        elapsed_ms = (time.monotonic() - start) * 1000
        metrics.inc("vesnai_http_requests_total", method=request.method,
                    status=str(response.status_code))
        log.info("http_request", method=request.method, status=response.status_code,
                 elapsed_ms=round(elapsed_ms, 2))
        response.headers["X-Request-ID"] = request_id
        return response

    for router in ALL_ROUTERS:
        app.include_router(router)

    return app
