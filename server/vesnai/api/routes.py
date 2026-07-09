"""All HTTP routers for the VesnAI API."""

from __future__ import annotations

import json
import time
from collections import defaultdict, deque

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Form,
    Header,
    HTTPException,
    Query,
    Request,
    Response,
    UploadFile,
)
from fastapi.responses import PlainTextResponse, StreamingResponse

from vesnai.api.deps import get_state, require_device
from vesnai.api.schemas import (
    BackupRequest,
    ChatAttachmentOut,
    ChatMessageOut,
    ChatRequest,
    ChatResponse,
    ChatSessionDetail,
    ChatSessionOut,
    CreateSessionRequest,
    DeviceOut,
    DueNoteOut,
    EnrichRequest,
    NoteCreate,
    NoteOut,
    NoteUpdate,
    NotificationAck,
    NotificationOut,
    PairCodeResponse,
    PairRequest,
    PairResponse,
    PushRequest,
    ResurfacedResponse,
    RetryChatActionRequest,
    RetryChatActionResponse,
    SaveChatAttachmentToNoteRequest,
    SaveChatAttachmentToNoteResponse,
    SearchRequest,
    SecretSet,
    SettingsOut,
    TagFeedbackRequest,
    TagSuggestRequest,
    TagSuggestResponse,
    VoiceRegistrationIn,
    VoiceRegistrationOut,
)
from vesnai.app_state import AppState
from vesnai.notes import NoteInput
from vesnai.observability import metrics
from vesnai.okf.model import Concept, Origin
from vesnai.security import (
    rate_limit_pair_redeem,
    read_upload_bounded,
    sanitize_attachment_stored_rel,
)
from vesnai.sync import Change

# --------------------------------------------------------------------------- #
# System (unauthenticated health/metrics)
# --------------------------------------------------------------------------- #
system_router = APIRouter(tags=["system"])


@system_router.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


@system_router.get("/readyz")
def readyz(state: AppState = Depends(get_state)) -> dict:
    # Deliberately reports no data details (note counts etc.) — this endpoint
    # is unauthenticated.
    return {"status": "ready"}


@system_router.get("/metrics", response_class=PlainTextResponse)
def metrics_endpoint() -> str:
    return metrics.render()


# --------------------------------------------------------------------------- #
# Auth / pairing
# --------------------------------------------------------------------------- #
auth_router = APIRouter(prefix="/v1/auth", tags=["auth"])

# Simple in-process rate limiter for the (otherwise sensitive) code endpoint.
_PAIR_CODE_RATE = 5
_PAIR_CODE_WINDOW = 60.0
_pair_code_hits: dict[str, deque[float]] = defaultdict(deque)


def _rate_limit(key: str) -> None:
    now = time.monotonic()
    hits = _pair_code_hits[key]
    while hits and now - hits[0] > _PAIR_CODE_WINDOW:
        hits.popleft()
    if len(hits) >= _PAIR_CODE_RATE:
        raise HTTPException(status_code=429, detail="too many pairing-code requests")
    hits.append(now)


def _client_host(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _require_paired_or_bootstrap(
    state: AppState, authorization: str | None, bootstrap: str | None
) -> None:
    """Gate code minting: a paired device token or the bootstrap secret.

    There is deliberately no IP-based (loopback) trust and no "open while
    unpaired" window: tunnel agents (pinggy/ngrok/cloudflared) forward from
    the same machine, so every tunneled request arrives as 127.0.0.1. The
    bootstrap secret lives in ``data_dir`` (0600) on the server host; the
    ``vesnai pair`` command reads it, so local UX stays one command.
    """
    if bootstrap and state.auth.verify_bootstrap_secret(bootstrap):
        return
    token = None
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:]
    if state.auth.verify(token) is not None:
        return
    raise HTTPException(
        status_code=403,
        detail="pairing requires a paired device token or the bootstrap secret "
        "(run `vesnai pair` on the server host)",
    )


@auth_router.post("/pair", response_model=PairResponse)
def pair(
    req: PairRequest,
    request: Request,
    state: AppState = Depends(get_state),
) -> PairResponse:
    rate_limit_pair_redeem(_client_host(request))
    try:
        token = state.auth.redeem_pairing_code(req.code, req.device_name)
    except PermissionError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc
    device = state.auth.verify(token)
    assert device is not None
    return PairResponse(token=token, device_id=device.device_id)


@auth_router.post("/pair/code", response_model=PairCodeResponse)
def create_pair_code(
    request: Request,
    state: AppState = Depends(get_state),
    authorization: str | None = Header(default=None),
    x_vesnai_bootstrap: str | None = Header(default=None),
) -> PairCodeResponse:
    """Mint a short-lived pairing code in the live server process.

    Requires a paired device token or the host-only bootstrap secret
    (``X-VesnAI-Bootstrap`` header; see ``vesnai pair``).
    """
    from vesnai.auth import PAIRING_TTL_SECONDS, TooManyPendingCodesError
    from vesnai.qr import qr_svg

    _require_paired_or_bootstrap(state, authorization, x_vesnai_bootstrap)
    _rate_limit(_client_host(request))
    try:
        code = state.auth.create_pairing_code()
    except TooManyPendingCodesError as exc:
        raise HTTPException(status_code=429, detail=str(exc)) from exc
    url = state.settings.public_base_url()
    payload = json.dumps({"url": url, "code": code})
    return PairCodeResponse(
        code=code, expires_in=PAIRING_TTL_SECONDS, url=url, qr_svg=qr_svg(payload)
    )


@auth_router.get("/devices", response_model=list[DeviceOut])
def list_devices(
    state: AppState = Depends(get_state), _=Depends(require_device)
) -> list[DeviceOut]:
    return [
        DeviceOut(device_id=d.device_id, name=d.name, created=d.created)
        for d in state.auth.list_devices()
    ]


@auth_router.delete("/devices/{device_id}")
def revoke_device(
    device_id: str, state: AppState = Depends(get_state), _=Depends(require_device)
) -> dict:
    state.auth.revoke(device_id)
    return {"device_id": device_id, "revoked": True}


# --------------------------------------------------------------------------- #
# Notes
# --------------------------------------------------------------------------- #
notes_router = APIRouter(prefix="/v1/notes", tags=["notes"])


def _to_out(path: str, concept: Concept) -> NoteOut:
    raw_atts = concept.vesnai.get("attachments") or []
    attachments = [str(a) for a in raw_atts] if isinstance(raw_atts, list) else []
    return NoteOut(
        path=path,
        title=concept.title,
        type=concept.type,
        tags=concept.tags,
        origin=concept.origin.value,
        body=concept.body,
        links=concept.links(),
        attachments=attachments,
        source=concept.source,
        version=int(concept.vesnai.get("version", 1)),
        updated=str(concept.vesnai.get("updated", concept.timestamp or "")),
        done=concept.done,
        done_at=concept.done_at,
    )


@notes_router.get("", response_model=list[NoteOut])
def list_notes(state: AppState = Depends(get_state), _=Depends(require_device)) -> list[NoteOut]:
    return [_to_out(p, c) for p, c in sorted(state.notes.list().items())]


@notes_router.post("", response_model=NoteOut)
def create_note(
    req: NoteCreate, state: AppState = Depends(get_state), _=Depends(require_device)
) -> NoteOut:
    rel, concept = state.notes.create(
        NoteInput(title=req.title, body=req.body, type=req.type, tags=req.tags, origin=Origin.USER)
    )
    return _to_out(rel, concept)


@notes_router.get("/due", response_model=list[DueNoteOut])
def list_due_notes(
    state: AppState = Depends(get_state), _=Depends(require_device)
) -> list[DueNoteOut]:
    due_paths = state.resurfacing.due(state.notes.list())[:20]
    out: list[DueNoteOut] = []
    for path in due_paths:
        if state.store.exists(path):
            c = state.notes.get(path)
            out.append(DueNoteOut(path=path, title=c.title))
    return out


@notes_router.post("/{path:path}/resurfaced", response_model=ResurfacedResponse)
def mark_note_resurfaced(
    path: str, state: AppState = Depends(get_state), _=Depends(require_device)
) -> ResurfacedResponse:
    if not state.store.exists(path):
        raise HTTPException(status_code=404, detail="note not found")
    concept = state.notes.get(path)
    count = int(concept.vesnai.get("resurface_count", 0)) + 1
    concept.vesnai["resurface_count"] = count
    concept.vesnai["last_resurfaced"] = state.clock.now().isoformat()
    state.notes.store.write_concept(path, concept, message="mark resurfaced")
    return ResurfacedResponse(path=path, resurface_count=count)


@notes_router.get("/{path:path}", response_model=NoteOut)
def get_note(
    path: str, state: AppState = Depends(get_state), _=Depends(require_device)
) -> NoteOut:
    if not state.store.exists(path):
        raise HTTPException(status_code=404, detail="note not found")
    return _to_out(path, state.notes.get(path))


@notes_router.put("/{path:path}", response_model=NoteOut)
def update_note(
    path: str, req: NoteUpdate, state: AppState = Depends(get_state), _=Depends(require_device)
) -> NoteOut:
    if not state.store.exists(path):
        raise HTTPException(status_code=404, detail="note not found")
    concept = state.notes.update(
        path, title=req.title, body=req.body, tags=req.tags, type=req.type,
        done=req.done, device=req.device
    )
    return _to_out(path, concept)


@notes_router.delete("/{path:path}")
def delete_note(
    path: str, state: AppState = Depends(get_state), _=Depends(require_device)
) -> dict:
    state.notes.delete(path)
    return {"deleted": path}


@notes_router.post("/suggest-tags", response_model=TagSuggestResponse)
def suggest_note_tags(
    req: TagSuggestRequest, state: AppState = Depends(get_state), _=Depends(require_device)
) -> TagSuggestResponse:
    from vesnai.ai.tagging import suggest_tags

    known: list[str] = []
    for _path, concept in state.notes.list().items():
        known.extend(concept.tags)
    known = sorted(set(known))[:40]
    result = suggest_tags(
        state.providers.reasoning,
        title=req.title,
        body=req.body,
        known_tags=known or None,
        tag_classifier=state.tag_classifier,
    )
    tags = result["tags"]
    return TagSuggestResponse(
        type=str(result["type"]),
        tags=list(tags) if isinstance(tags, list) else [],
    )


feedback_router = APIRouter(prefix="/v1/feedback", tags=["feedback"])


@feedback_router.post("/tags")
def record_tag_feedback(
    req: TagFeedbackRequest,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> dict:
    state.record_tag_feedback(req.text, req.tags, req.action)
    return {"recorded": True}


@notes_router.post("/{path:path}/attachments")
async def upload_attachment(
    path: str,
    file: UploadFile,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> dict:
    data = await read_upload_bounded(file)
    rel = sanitize_attachment_stored_rel(file.filename)
    state.store.save_attachment(rel, data)
    # Record the attachment on the note so it syncs, renders in-app, and photo
    # captioning / auto-illustrate see it.
    if state.store.exists(path):
        concept = state.store.read_concept(path)
        attachments = concept.vesnai.setdefault("attachments", [])
        if rel not in attachments:
            attachments.append(rel)
            state.store.write_concept(path, concept, message=f"attach {rel}")
    return {"attachment": rel}


# --------------------------------------------------------------------------- #
# Attachments (serve uploaded / generated files for in-note rendering)
# --------------------------------------------------------------------------- #
attachments_router = APIRouter(prefix="/v1/attachments", tags=["attachments"])


@attachments_router.get("/{path:path}")
def get_attachment(
    path: str, state: AppState = Depends(get_state), _=Depends(require_device)
) -> Response:
    import mimetypes

    from vesnai.okf.bundle import PathTraversalError

    try:
        resolved = state.store._resolve(path)
    except PathTraversalError as exc:
        raise HTTPException(status_code=400, detail="invalid path") from exc
    if not resolved.is_file():
        raise HTTPException(status_code=404, detail="attachment not found")
    media_type = mimetypes.guess_type(resolved.name)[0] or "application/octet-stream"
    return Response(content=resolved.read_bytes(), media_type=media_type)


# --------------------------------------------------------------------------- #
# Sync
# --------------------------------------------------------------------------- #
sync_router = APIRouter(prefix="/v1/sync", tags=["sync"])


@sync_router.get("/pull")
def pull(since: int = 0, state: AppState = Depends(get_state), _=Depends(require_device)) -> dict:
    return state.sync.pull(since=since)


@sync_router.post("/push")
def push(
    req: PushRequest, state: AppState = Depends(get_state), _=Depends(require_device)
) -> dict:
    changes = [Change(path=c.path, deleted=c.deleted, doc=c.doc) for c in req.changes]
    result = state.sync.push(changes, device=req.device)
    if result.applied:
        # New/edited notes just arrived; give Marena a chance to critique them.
        state.maybe_run_marena_review()
    return {"applied": result.applied, "conflicts": result.conflicts, "cursor": result.cursor}


# --------------------------------------------------------------------------- #
# Backup / restore
# --------------------------------------------------------------------------- #
backup_router = APIRouter(prefix="/v1/backup", tags=["backup"])


def _backup_response(data: bytes, *, encrypted: bool) -> Response:
    if encrypted:
        return Response(
            content=data,
            media_type="application/octet-stream",
            headers={"Content-Disposition": "attachment; filename=vesnai-backup.zip.enc"},
        )
    return Response(
        content=data,
        media_type="application/zip",
        headers={"Content-Disposition": "attachment; filename=vesnai-backup.zip"},
    )


@backup_router.get("")
def backup_get(
    allow_plaintext: bool = Query(default=False),
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> Response:
    if not allow_plaintext:
        raise HTTPException(
            status_code=400,
            detail=(
                "unencrypted backup requires allow_plaintext=true; "
                "use POST /v1/backup with a passphrase for encrypted export"
            ),
        )
    return _backup_response(state.store.export_zip(), encrypted=False)


@backup_router.post("")
def backup_post(
    req: BackupRequest,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> Response:
    data = state.store.export_zip()
    if req.passphrase:
        from vesnai.crypto import encrypt_blob

        data = encrypt_blob(data, req.passphrase)
        return _backup_response(data, encrypted=True)
    raise HTTPException(
        status_code=400,
        detail="POST /v1/backup requires a passphrase for encrypted export",
    )


@backup_router.post("/restore")
async def restore(
    file: UploadFile,
    passphrase: str | None = Form(default=None),
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> dict:
    data = await read_upload_bounded(file)
    from vesnai.crypto import MAGIC, decrypt_blob

    if data.startswith(MAGIC):
        if not passphrase:
            raise HTTPException(status_code=400, detail="encrypted backup requires a passphrase")
        data = decrypt_blob(data, passphrase)
    state.store.import_zip(data)
    state.index.reindex(state.notes.list())
    return {"restored": True, "notes": len(state.store.list_paths())}


# --------------------------------------------------------------------------- #
# Jobs
# --------------------------------------------------------------------------- #
jobs_router = APIRouter(prefix="/v1/jobs", tags=["jobs"])


@jobs_router.get("/{job_id}")
def get_job(job_id: str, state: AppState = Depends(get_state), _=Depends(require_device)) -> dict:
    job = state.jobs.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job not found")
    return job.to_dict()


@jobs_router.get("/{job_id}/events")
async def job_events(
    job_id: str, state: AppState = Depends(get_state), _=Depends(require_device)
) -> StreamingResponse:
    """Server-Sent Events stream of a job's progress until it reaches a terminal state."""
    import asyncio

    from vesnai.jobs import JobStatus

    if state.jobs.get(job_id) is None:
        raise HTTPException(status_code=404, detail="job not found")

    async def _gen():
        terminal = {JobStatus.SUCCEEDED, JobStatus.FAILED}
        while True:
            job = state.jobs.get(job_id)
            if job is None:
                break
            yield f"data: {json.dumps(job.to_dict())}\n\n"
            if job.status in terminal:
                break
            await asyncio.sleep(0.25)

    return StreamingResponse(_gen(), media_type="text/event-stream")


# --------------------------------------------------------------------------- #
# AI: enrich / chat / search / graph
# --------------------------------------------------------------------------- #
ai_router = APIRouter(prefix="/v1", tags=["ai"])


@ai_router.post("/enrich")
async def enrich(
    req: EnrichRequest, state: AppState = Depends(get_state), _=Depends(require_device)
) -> dict:
    if not state.store.exists(req.path):
        raise HTTPException(status_code=404, detail="source note not found")

    async def _run(ctx):
        ctx.progress(0.1, "starting enrichment")
        if req.kind == "photo":
            rel = state.enrichment.enrich_photo(req.path)
        else:
            rel = state.enrichment.enrich_idea(req.path)
        ctx.progress(1.0, "done")
        return {"generated": rel}

    job = await state.jobs.run_to_completion(f"enrich:{req.kind}", _run)
    return job.to_dict()


def _to_chat_history(messages) -> list:
    from vesnai.providers.base import ChatMessage

    out = []
    for m in messages:
        out.append(ChatMessage(role=m.role, content=m.content))
    return out


def _message_out(m) -> ChatMessageOut:
    return ChatMessageOut(
        role=m.role,
        content=m.content,
        ts=m.ts,
        id=m.id or "",
        attachments=[ChatAttachmentOut(**a) for a in (m.attachments or [])],
        metadata=dict(getattr(m, "metadata", None) or {}),
    )


def _assistant_language_setting(req: ChatRequest) -> str | None:
    return req.assistant_language or req.language


def _resolve_chat_language(
    req: ChatRequest,
    *,
    session_language: str | None = None,
    text: str | None = None,
) -> str:
    from vesnai.ai.chat_language import resolve_language

    return resolve_language(
        user_setting=_assistant_language_setting(req),
        session_language=session_language,
        text=text or req.message,
    )


@ai_router.post("/chat", response_model=ChatResponse, status_code=202)
async def chat(
    req: ChatRequest, state: AppState = Depends(get_state), _=Depends(require_device)
) -> ChatResponse:
    from vesnai.ids import uuid7

    if not req.session_id:
        raise HTTPException(status_code=400, detail="session_id is required")
    convo = state.conversations.get(req.session_id)
    if convo is None:
        raise HTTPException(status_code=404, detail="session not found")

    user_attach_meta = [a for a in req.attachment_refs if a.get("path")]
    _, user_message_id = state.conversations.append(
        req.session_id,
        "user",
        req.message,
        attachments=user_attach_meta,
    )
    assistant_msg_id = uuid7()
    state.conversations.append(
        req.session_id,
        "assistant",
        "",
        message_id=assistant_msg_id,
    )
    convo = state.conversations.refresh_language(req.session_id)

    loc_ctx = (
        req.location_context.model_dump(exclude_none=True)
        if req.location_context is not None
        else None
    )

    _, queue_position = state.chat_turns.enqueue(
        req.session_id,
        user_message_id=user_message_id,
        message=req.message,
        attachment_refs=user_attach_meta,
        assistant_language=_assistant_language_setting(req),
        assistant_message_id=assistant_msg_id,
        persist_transcript=req.persist,
        location_context=loc_ctx,
    )
    await state.chat_turns.kick_async(req.session_id)

    return ChatResponse(
        status="accepted",
        session_id=req.session_id,
        user_message_id=user_message_id,
        assistant_message_id=assistant_msg_id,
        message_id=assistant_msg_id,
        queue_position=queue_position,
        language=convo.language,
    )


def _session_out(convo) -> ChatSessionOut:
    return ChatSessionOut(
        id=convo.id,
        title=convo.title,
        created=convo.created,
        updated=convo.updated,
        language=convo.language,
    )


@ai_router.get("/chat/sessions", response_model=list[ChatSessionOut])
def list_sessions(
    state: AppState = Depends(get_state), _=Depends(require_device)
) -> list[ChatSessionOut]:
    return [_session_out(c) for c in state.conversations.list_all()]


@ai_router.post("/chat/sessions", response_model=ChatSessionDetail)
def create_session(
    req: CreateSessionRequest,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> ChatSessionDetail:
    # Memory is updated after each completed turn; do not block session creation.
    convo = state.conversations.create(title=req.title or "New chat")
    return _session_detail(convo)


def _session_detail(convo) -> ChatSessionDetail:
    return ChatSessionDetail(
        id=convo.id,
        title=convo.title,
        created=convo.created,
        updated=convo.updated,
        language=convo.language,
        messages=[_message_out(m) for m in convo.messages],
    )


@ai_router.post("/chat/sessions/{session_id}/attachments")
async def upload_chat_attachment(
    session_id: str,
    file: UploadFile = File(...),
    kind: str = Form("file"),
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> dict:
    convo = state.conversations.get(session_id)
    if convo is None:
        raise HTTPException(status_code=404, detail="session not found")
    data = await read_upload_bounded(file)
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    filename = file.filename or "upload.bin"
    resolved_kind = kind
    if kind == "file":
        lower = filename.lower()
        if lower.endswith((".png", ".jpg", ".jpeg", ".webp", ".gif")):
            resolved_kind = "image"
        elif lower.endswith((".wav", ".mp3", ".m4a", ".ogg", ".webm")):
            resolved_kind = "audio"
    meta = state.conversations.save_attachment(
        session_id, filename, data, kind=resolved_kind
    )
    return meta


@ai_router.get("/chat/attachments/{session_id}/{filename}")
def get_chat_attachment(
    session_id: str,
    filename: str,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> Response:
    try:
        data = state.conversations.read_attachment(session_id, filename)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="attachment not found") from exc
    import mimetypes

    mime, _ = mimetypes.guess_type(filename)
    return Response(content=data, media_type=mime or "application/octet-stream")


@ai_router.post(
    "/chat/sessions/{session_id}/attachments/{filename}/save-to-note",
    response_model=SaveChatAttachmentToNoteResponse,
)
def save_chat_attachment_to_note(
    session_id: str,
    filename: str,
    req: SaveChatAttachmentToNoteRequest,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> SaveChatAttachmentToNoteResponse:
    convo = state.conversations.get(session_id)
    if convo is None:
        raise HTTPException(status_code=404, detail="session not found")
    try:
        result = state.save_chat_attachment_to_note(
            session_id,
            filename,
            note_path=req.note_path,
            title=req.title,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="attachment not found") from exc
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="note not found") from exc
    return SaveChatAttachmentToNoteResponse(**result)


@ai_router.get("/chat/sessions/{session_id}", response_model=ChatSessionDetail)
def get_session(
    session_id: str, state: AppState = Depends(get_state), _=Depends(require_device)
) -> ChatSessionDetail:
    convo = state.conversations.get(session_id)
    if convo is None:
        raise HTTPException(status_code=404, detail="session not found")
    from vesnai.ai.chat_image_ingest import backfill_session_external_images

    backfill_session_external_images(state.conversations, session_id)
    convo = state.conversations.get(session_id)
    if convo is None:
        raise HTTPException(status_code=404, detail="session not found")
    return _session_detail(convo)


@ai_router.post(
    "/chat/sessions/{session_id}/messages/{message_id}/retry-action",
    response_model=RetryChatActionResponse,
)
def retry_chat_action(
    session_id: str,
    message_id: str,
    req: RetryChatActionRequest,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> RetryChatActionResponse:
    if state.conversations.get(session_id) is None:
        raise HTTPException(status_code=404, detail="session not found")
    result = state.retry_chat_action(session_id, message_id, req.action)
    if result.get("error"):
        raise HTTPException(status_code=400, detail=result["error"])
    return RetryChatActionResponse(**result)


@ai_router.delete("/chat/sessions/{session_id}")
def delete_session(
    session_id: str, state: AppState = Depends(get_state), _=Depends(require_device)
) -> dict:
    if not state.conversations.delete(session_id):
        raise HTTPException(status_code=404, detail="session not found")
    return {"deleted": session_id}


@ai_router.post("/chat/sessions/{session_id}/consolidate")
def consolidate_session(
    session_id: str,
    background_tasks: BackgroundTasks,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> dict:
    """Trigger async background memory review for a session (Hermes-style)."""
    convo = state.conversations.get(session_id)
    if convo is None:
        raise HTTPException(status_code=404, detail="session not found")
    background_tasks.add_task(state.memory_review.run_review, session_id)
    return {"status": "review_scheduled", "session_id": session_id}


def _consolidate_session_legacy(state: AppState, convo) -> str | None:
    """Distil a session's user turns into durable bullets in memory/memory.md."""
    user_turns = [m.content for m in convo.messages if m.role == "user" and m.content.strip()]
    if not user_turns:
        return None
    path: str | None = None
    for text in user_turns:
        updated = state.memory.consolidate_message(text)
        if updated:
            path = updated
    return path


@ai_router.post("/search")
async def search(
    req: SearchRequest, state: AppState = Depends(get_state), _=Depends(require_device)
) -> dict:
    async def _run(ctx):
        ctx.progress(0.1, "planning search")
        rel = state.search_agent.run(
            req.query, languages=req.languages, max_seconds=req.max_seconds
        )
        ctx.progress(1.0, "done")
        return {"research": rel}

    job = await state.jobs.run_to_completion("search", _run)
    return job.to_dict()


@ai_router.post("/voice/tts")
def voice_tts(
    req: ChatRequest, state: AppState = Depends(get_state), _=Depends(require_device)
) -> Response:
    import httpx

    from vesnai.providers.remote_tts import VoiceNotConfiguredError

    session_language = None
    if req.session_id:
        convo = state.conversations.get(req.session_id)
        if convo is not None:
            session_language = convo.language
    from vesnai.ai.chat_language import resolve_tts_language

    language = resolve_tts_language(
        user_setting=_assistant_language_setting(req),
        session_language=session_language,
        text=req.message,
    )
    try:
        audio = state.voice.speak(req.message, language=language)
    except VoiceNotConfiguredError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except httpx.HTTPStatusError as exc:
        detail = exc.response.text.strip() or str(exc)
        raise HTTPException(status_code=502, detail=f"Voice service error: {detail}") from exc
    reg = state.voice_registration.load()
    media_type = reg.audio_content_type() if reg else "audio/wav"
    return Response(content=audio, media_type=media_type)


@ai_router.post("/voice/converse")
async def voice_converse(
    file: UploadFile,
    language: str | None = None,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> dict:
    import base64

    from vesnai.providers.remote_tts import VoiceNotConfiguredError

    audio = await read_upload_bounded(file, max_bytes=25 * 1024 * 1024)
    try:
        result = state.voice.converse(audio, language=language)
    except VoiceNotConfiguredError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return {
        "transcript": result.transcript,
        "reply": result.reply.content,
        "tool_calls": result.reply.tool_calls,
        "audio_base64": base64.b64encode(result.audio).decode(),
    }


@ai_router.get("/graph")
def graph(
    tag: list[str] | None = Query(default=None),
    type: str | None = None,
    origin: str | None = None,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> dict:
    from vesnai.graph import build_graph

    origin_enum = Origin(origin) if origin in {o.value for o in Origin} else None
    g = build_graph(state.notes.list(), tags=tag or [], type=type, origin=origin_enum)
    return g.to_dict()


# --------------------------------------------------------------------------- #
# Settings / secrets
# --------------------------------------------------------------------------- #
settings_router = APIRouter(prefix="/v1/settings", tags=["settings"])


@settings_router.get("", response_model=SettingsOut)
def get_settings_endpoint(
    state: AppState = Depends(get_state), _=Depends(require_device)
) -> SettingsOut:
    s = state.settings
    voice = state.voice_registration.load()
    return SettingsOut(
        offline_only=s.offline_only,
        default_chat_model=s.default_chat_model,
        default_embedding_model=s.default_embedding_model,
        search_languages=s.search_languages,
        search_max_seconds=s.search_max_seconds,
        secret_names=state.secrets.names(),
        voice_configured=voice is not None,
        voice_url=voice.resolved_url() if voice else None,
        voice_provider=voice.provider if voice else None,
    )


def _voice_out(state: AppState) -> VoiceRegistrationOut:
    reg = state.voice_registration.load()
    if reg is None:
        return VoiceRegistrationOut(configured=False)
    return VoiceRegistrationOut(
        configured=True,
        provider=reg.provider,
        url=reg.resolved_url(),
        secret_name=reg.secret_name,
        voices=reg.voices,
        model=reg.model,
    )


@settings_router.get("/voice", response_model=VoiceRegistrationOut)
def get_voice_registration(
    state: AppState = Depends(get_state), _=Depends(require_device)
) -> VoiceRegistrationOut:
    return _voice_out(state)


@settings_router.put("/voice", response_model=VoiceRegistrationOut)
def put_voice_registration(
    req: VoiceRegistrationIn,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> VoiceRegistrationOut:
    from vesnai.providers.remote_tts import validate_voice_registration
    from vesnai.voice_registration import (
        DEFAULT_SECRET_NAME,
        PROVIDER_OPENAI,
        PROVIDER_SIDECAR,
        VoiceRegistration,
    )

    provider = req.provider.strip().lower()
    if provider not in (PROVIDER_SIDECAR, PROVIDER_OPENAI):
        raise HTTPException(status_code=400, detail=f"unsupported provider: {req.provider}")

    if provider == PROVIDER_SIDECAR:
        url = (req.url or "").strip().rstrip("/")
        if not url:
            raise HTTPException(status_code=400, detail="url is required for sidecar")
        # Voice IDs are engine-specific; there is no bundled engine to guess for.
        if not req.voices:
            raise HTTPException(
                status_code=400,
                detail="voices is required for sidecar (per-language voice IDs)",
            )
        default_voices: dict[str, str] = {}
    else:
        url = (req.url or "").strip().rstrip("/")
        default_voices = {"pl": "nova", "en": "nova"}

    voices = req.voices or default_voices
    reg = VoiceRegistration(
        provider=provider,
        url=url,
        secret_name=DEFAULT_SECRET_NAME,
        voices=voices,
        model=req.model,
    )
    try:
        validate_voice_registration(reg, req.api_key)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=400, detail=f"could not reach voice service: {exc}"
        ) from exc

    state.secrets.set(DEFAULT_SECRET_NAME, req.api_key)
    state.voice_registration.save(reg)
    return _voice_out(state)


@settings_router.delete("/voice", response_model=VoiceRegistrationOut)
def delete_voice_registration(
    state: AppState = Depends(get_state), _=Depends(require_device)
) -> VoiceRegistrationOut:
    from vesnai.voice_registration import DEFAULT_SECRET_NAME

    reg = state.voice_registration.load()
    if reg is not None:
        state.secrets.delete(reg.secret_name)
    else:
        state.secrets.delete(DEFAULT_SECRET_NAME)
    state.voice_registration.delete()
    return VoiceRegistrationOut(configured=False)


@settings_router.post("/secrets")
def set_secret(
    req: SecretSet, state: AppState = Depends(get_state), _=Depends(require_device)
) -> dict:
    state.secrets.set(req.name, req.value)
    # Never echo the value back.
    return {"name": req.name, "stored": True}


@settings_router.delete("/secrets/{name}")
def delete_secret(
    name: str, state: AppState = Depends(get_state), _=Depends(require_device)
) -> dict:
    state.secrets.delete(name)
    return {"name": name, "deleted": True}


# --------------------------------------------------------------------------- #
# Notifications (local "image ready" feed; no Firebase)
# --------------------------------------------------------------------------- #
notifications_router = APIRouter(prefix="/v1/notifications", tags=["notifications"])


def _notification_out(n) -> NotificationOut:
    return NotificationOut(
        id=n.id,
        kind=n.kind,
        title=n.title,
        source_path=n.source_path,
        image_path=n.image_path,
        session_id=getattr(n, "session_id", None),
        attachment_path=getattr(n, "attachment_path", None),
        message_id=getattr(n, "message_id", None),
        note_path=getattr(n, "note_path", None),
        pending_image=getattr(n, "pending_image", False),
        ts=n.ts,
        read=n.read,
    )


@notifications_router.get("", response_model=list[NotificationOut])
def list_notifications(
    since: str | None = None,
    unread_only: bool = True,
    state: AppState = Depends(get_state),
    _=Depends(require_device),
) -> list[NotificationOut]:
    if since is not None:
        items = state.notifications.since(since)
    else:
        items = state.notifications.list_all(unread_only=unread_only)
    return [_notification_out(n) for n in items]


@notifications_router.post("/ack")
def ack_notifications(
    req: NotificationAck, state: AppState = Depends(get_state), _=Depends(require_device)
) -> dict:
    return {"acked": state.notifications.ack(req.ids)}


@notifications_router.get("/events")
async def notification_events(
    state: AppState = Depends(get_state), _=Depends(require_device)
) -> StreamingResponse:
    """SSE stream of new notifications for foregrounded clients."""
    import asyncio

    async def _gen():
        seen: set[str] = {n.id for n in state.notifications.list_all()}
        while True:
            for n in state.notifications.list_all():
                if n.id not in seen:
                    seen.add(n.id)
                    yield f"data: {json.dumps(_notification_out(n).model_dump())}\n\n"
            await asyncio.sleep(1.0)

    return StreamingResponse(_gen(), media_type="text/event-stream")


ALL_ROUTERS = [
    system_router,
    auth_router,
    notes_router,
    feedback_router,
    attachments_router,
    sync_router,
    backup_router,
    jobs_router,
    ai_router,
    settings_router,
    notifications_router,
]
