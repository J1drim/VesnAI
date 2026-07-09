"""Turn chat attachment metadata into LLM-ready user content."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from vesnai.ai.extract import default_extractor
from vesnai.ai.web_safety import sanitize_untrusted_text
from vesnai.providers.base import ChatMessage, STTProvider


@dataclass
class ChatAttachment:
    """Reference to an uploaded session attachment."""

    path: str  # filename under conversations/{session_id}/attachments/
    kind: str  # image | file | audio | generated
    filename: str
    mime: str = ""


def build_user_message(
    text: str,
    attachments: list[ChatAttachment],
    *,
    read_bytes: Callable[[str], bytes],
    stt: STTProvider | None = None,
) -> ChatMessage:
    """Merge text + file excerpts + STT into one user ChatMessage."""
    parts: list[str] = []
    if text.strip():
        parts.append(text.strip())
    image_bytes: list[bytes] = []

    for att in attachments:
        data = read_bytes(att.path)
        if att.kind == "image" or (
            att.kind == "generated" and att.mime.startswith("image/")
        ):
            image_bytes.append(data)
            continue
        if att.kind == "audio" and stt is not None:
            transcript = stt.transcribe(data).strip()
            if transcript:
                parts.append(f"[Voice note transcript: {transcript}]")
            continue
        if att.kind == "file" or att.kind == "audio":
            extracted = default_extractor(data, att.filename).strip()
            if extracted:
                safe = sanitize_untrusted_text(extracted)
                parts.append(f"[Attached file: {att.filename}]\n{safe}")
            elif att.kind == "audio":
                parts.append(f"[Voice note: {att.filename}]")

    content = "\n\n".join(parts) if parts else "(attachment only)"
    return ChatMessage(role="user", content=content, images=image_bytes)
