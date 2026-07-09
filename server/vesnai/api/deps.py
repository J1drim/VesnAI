"""FastAPI dependencies: app-state access and device authentication."""

from __future__ import annotations

from fastapi import Depends, Header, HTTPException, Request, status

from vesnai.app_state import AppState
from vesnai.auth import Device


def get_state(request: Request) -> AppState:
    return request.app.state.vesnai


def require_device(
    state: AppState = Depends(get_state),
    authorization: str | None = Header(default=None),
) -> Device:
    token = None
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:]
    device = state.auth.verify(token)
    if device is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="unpaired or invalid device token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return device
