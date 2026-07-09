"""ASGI entry point: ``uvicorn vesnai.main:app``."""

from __future__ import annotations

from vesnai.api.server import create_app

app = create_app()
