"""SSR-safe ingest of external markdown image URLs into chat attachments."""

from __future__ import annotations

from typing import TYPE_CHECKING

from vesnai.ai.tool_guardrails import (
    extract_external_image_urls,
    has_external_image_markdown,
    strip_external_image_markdown,
)
from vesnai.ai.web_safety import UnsafeUrlError, fetch_image_url
from vesnai.observability import get_logger

if TYPE_CHECKING:
    from vesnai.ai.conversations import ConversationStore

log = get_logger("vesnai.chat_image_ingest")

_FETCH_FAIL_NOTE = "(Nie udało się pobrać obrazka z linku.)"


def _message_has_image_attachment(attachments: list[dict]) -> bool:
    for att in attachments or []:
        mime = (att.get("mime") or "").lower()
        kind = att.get("kind") or ""
        if mime.startswith("image/") or kind in ("generated", "fetched"):
            return True
    return False


def ingest_message_external_images(
    conversations: ConversationStore,
    session_id: str,
    message_id: str,
    content: str,
) -> str:
    """Fetch ![...](http...) URLs, save as attachments, strip markdown from content."""
    if not has_external_image_markdown(content):
        return content

    convo = conversations.get(session_id)
    if convo is not None:
        for msg in convo.messages:
            if msg.id == message_id and _message_has_image_attachment(msg.attachments):
                return strip_external_image_markdown(content) or content

    urls = extract_external_image_urls(content)
    if not urls:
        return content

    any_success = False
    for url in urls:
        try:
            data, mime = fetch_image_url(url)
            att = conversations.save_fetched_image(session_id, data, mime)
            conversations.add_message_attachment(session_id, message_id, att)
            any_success = True
        except (UnsafeUrlError, OSError, ValueError) as exc:
            log.warning(
                "chat_image_ingest_failed",
                session_id=session_id,
                message_id=message_id,
                url=url,
                error=str(exc),
            )

    cleaned = strip_external_image_markdown(content)
    if any_success:
        return cleaned if cleaned else strip_external_image_markdown(content) or content
    if cleaned:
        return f"{cleaned}\n\n{_FETCH_FAIL_NOTE}".strip()
    return _FETCH_FAIL_NOTE


def backfill_session_external_images(
    conversations: ConversationStore,
    session_id: str,
) -> int:
    """Ingest external image URLs from assistant messages missing image attachments."""
    convo = conversations.get(session_id)
    if convo is None:
        return 0
    updated = 0
    for msg in convo.messages:
        if msg.role != "assistant":
            continue
        if _message_has_image_attachment(msg.attachments):
            continue
        if not has_external_image_markdown(msg.content):
            continue
        new_content = ingest_message_external_images(
            conversations, session_id, msg.id, msg.content
        )
        if new_content != msg.content:
            conversations.update_message_content(session_id, msg.id, new_content)
            updated += 1
    return updated
