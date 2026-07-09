"""Shared helpers for chat tools that read or mutate OKF notes."""

from __future__ import annotations

from collections.abc import Callable

from vesnai.ai.extract import default_extractor
from vesnai.ai.web_safety import sanitize_untrusted_text
from vesnai.attachment_refs import (
    ENRICHMENT_CHILD_TYPES,
    attachment_paths_match,
    attachment_refs_from_concept,
    normalize_bundle_path,
)
from vesnai.notes import NoteService
from vesnai.okf.model import Concept
from vesnai.providers.base import VisionProvider

READ_NOTE_BODY_MAX = 8000
_IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".tif", ".tiff")
_TRANSIENT_VISION_MARKERS = ("timeout", "timed out", "connection", "reset", "temporarily")


def is_note_path(path: str) -> bool:
    return normalize_bundle_path(path).endswith(".md")


def _basename(path: str) -> str:
    return normalize_bundle_path(path).rsplit("/", 1)[-1]


def _attachment_paths_match(a: str, b: str) -> bool:
    return attachment_paths_match(a, b)


def collect_all_attachment_refs(notes: NoteService) -> set[str]:
    refs: set[str] = set()
    for concept in notes.list().values():
        refs.update(attachment_refs_from_concept(concept))
    return refs


def is_attachment_referenced(notes: NoteService, att_path: str) -> bool:
    target = normalize_bundle_path(att_path)
    for concept in notes.list().values():
        for ref in attachment_refs_from_concept(concept):
            if _attachment_paths_match(ref, target):
                return True
    return False


def enrichment_children(notes: NoteService, source_path: str) -> list[str]:
    source_path = normalize_bundle_path(source_path)
    out: list[str] = []
    for rel, concept in notes.list().items():
        if (
            concept.is_generated
            and concept.type in ENRICHMENT_CHILD_TYPES
            and concept.source == source_path
        ):
            out.append(rel)
    return out


def stale_enrichment_children(notes: NoteService) -> list[str]:
    """GeneratedImage/Caption notes whose source note no longer exists."""
    out: list[str] = []
    for rel, concept in notes.list().items():
        if concept.type not in ENRICHMENT_CHILD_TYPES or not concept.is_generated:
            continue
        source = concept.source
        if source and not notes.store.exists(source):
            out.append(rel)
    return out


def find_note_for_attachment(notes: NoteService, att_path: str) -> str | None:
    target = normalize_bundle_path(att_path)
    for note_path, concept in notes.list().items():
        for ref in attachment_refs_from_concept(concept):
            if _attachment_paths_match(ref, target):
                return note_path
    return None


def resolve_bundle_attachment_path(
    notes: NoteService,
    attachment_path: str,
    *,
    note_path: str = "",
) -> str | None:
    """Resolve a bundle-relative attachment path (exact, basename, or via note list)."""
    attachment_path = normalize_bundle_path(attachment_path)
    if not attachment_path:
        return None
    if notes.store.exists(attachment_path):
        return attachment_path
    base = _basename(attachment_path)
    for candidate in (f"attachments/{base}", base):
        if notes.store.exists(candidate):
            return candidate
    note_path = normalize_bundle_path(note_path)
    if note_path and is_note_path(note_path) and notes.store.exists(note_path):
        concept = notes.get(note_path)
        for att in concept.vesnai.get("attachments") or []:
            att = str(att)
            if _attachment_paths_match(att, attachment_path) and notes.store.exists(att):
                return att
    parent = find_note_for_attachment(notes, attachment_path)
    if parent:
        concept = notes.get(parent)
        for att in concept.vesnai.get("attachments") or []:
            att = str(att)
            if _attachment_paths_match(att, attachment_path) and notes.store.exists(att):
                return att
    return None


def _body_snippet(body: str, *, max_chars: int) -> str:
    text = (body or "").strip()
    if len(text) <= max_chars:
        return sanitize_untrusted_text(text)
    return sanitize_untrusted_text(text[:max_chars] + "\n… (truncated)")


def read_note_payload(
    notes: NoteService,
    path: str,
    *,
    max_body_chars: int = READ_NOTE_BODY_MAX,
) -> dict:
    path = normalize_bundle_path(path or "")
    if not path:
        return {"error": "path is required"}
    if not is_note_path(path):
        if notes.store.exists(path):
            return {"error": "not a note path; use read_note_attachment", "path": path}
        return {"error": "note not found", "path": path}
    if not notes.store.exists(path):
        return {"error": "note not found", "path": path}
    concept = notes.get(path)
    return {
        "path": path,
        "title": concept.title or path,
        "type": concept.type,
        "tags": list(concept.tags),
        "origin": concept.origin.value,
        "body": _body_snippet(concept.body, max_chars=max_body_chars),
        "attachments": [str(a) for a in (concept.vesnai.get("attachments") or [])],
        "links": [str(link) for link in (concept.vesnai.get("links") or [])],
    }


def list_notes_payload(
    notes: NoteService,
    *,
    note_type: str | None = None,
    tag: str | None = None,
    origin: str | None = None,
    limit: int = 20,
) -> dict:
    limit = max(1, min(int(limit or 20), 50))
    rows: list[tuple[str, str, str, str]] = []
    for path, concept in notes.list().items():
        if note_type and concept.type != note_type:
            continue
        if tag and tag not in concept.tags:
            continue
        if origin and concept.origin.value != origin:
            continue
        updated = str(concept.vesnai.get("updated") or concept.vesnai.get("created") or "")
        rows.append((updated, path, concept.title or path, concept.type or "Note"))
    rows.sort(reverse=True)
    return {
        "notes": [
            {"path": path, "title": title, "type": ntype, "updated": updated}
            for updated, path, title, ntype in rows[:limit]
        ]
    }


def get_note_links_payload(notes: NoteService, path: str) -> dict:
    path = (path or "").strip()
    if not path:
        return {"error": "path is required"}
    if not notes.store.exists(path):
        return {"error": "note not found", "path": path}
    concept = notes.get(path)
    linked: list[dict] = []
    for link_path in concept.vesnai.get("links") or []:
        link_path = str(link_path)
        if notes.store.exists(link_path):
            target = notes.get(link_path)
            linked.append(
                {
                    "path": link_path,
                    "title": target.title or link_path,
                    "type": target.type,
                }
            )
        else:
            linked.append({"path": link_path, "title": link_path, "type": None})
    return {"path": path, "title": concept.title or path, "links": linked}


def unlink_notes_payload(notes: NoteService, from_path: str, to_path: str) -> dict:
    from_path = (from_path or "").strip()
    to_path = (to_path or "").strip()
    if not from_path or not to_path:
        return {"error": "from_path and to_path are required"}
    if not notes.store.exists(from_path):
        return {"error": "source note not found"}
    concept = notes.get(from_path)
    links = concept.vesnai.setdefault("links", [])
    if to_path not in links:
        return {"error": "link not found", "from_path": from_path, "to_path": to_path}
    links.remove(to_path)
    notes.store.write_concept(from_path, concept, message="chat unlink")
    return {"unlinked": [from_path, to_path]}


def _cached_attachment_description(concept, att_path: str) -> str | None:
    extracts = concept.vesnai.get("attachment_extracts")
    if not isinstance(extracts, dict):
        return None
    text = extracts.get(att_path)
    if isinstance(text, str) and text.strip():
        return text.strip()
    return None


def _is_transient_vision_error(exc: Exception) -> bool:
    msg = str(exc).lower()
    return any(marker in msg for marker in _TRANSIENT_VISION_MARKERS)


def _vision_caption(
    vision: VisionProvider,
    data: bytes,
    prompt: str,
) -> tuple[str | None, str | None]:
    """Return (description, error). Never raises."""
    last_exc: Exception | None = None
    for attempt in range(2):
        try:
            return vision.caption(data, prompt).strip(), None
        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            if attempt == 0 and _is_transient_vision_error(exc):
                continue
            break
    assert last_exc is not None
    return None, f"vision failed: {last_exc}"


def _resolve_parent_note_path(
    notes: NoteService,
    note_path: str,
    att_path: str,
) -> str | None:
    note_path = normalize_bundle_path(note_path)
    if note_path and is_note_path(note_path) and notes.store.exists(note_path):
        return note_path
    return find_note_for_attachment(notes, att_path)


def _cached_description_for_attachment(
    notes: NoteService,
    att_path: str,
    *,
    note_path: str = "",
) -> str | None:
    parent = _resolve_parent_note_path(notes, note_path, att_path)
    if not parent:
        return None
    concept = notes.get(parent)
    cached = _cached_attachment_description(concept, att_path)
    if cached:
        return cached
    for att in concept.vesnai.get("attachments") or []:
        att = str(att)
        if _attachment_paths_match(att, att_path):
            cached = _cached_attachment_description(concept, att)
            if cached:
                return cached
    return None


def _note_context_clause(concept, note_path: str) -> str | None:
    body = (concept.body or "").strip()
    if body:
        return f"Style/context from note: {body[:1200]}"
    title = (concept.title or note_path).strip()
    if title:
        return f"Inspired by note titled: {title}"
    return None


def _resolve_attachment_path(
    notes: NoteService,
    note_path: str,
    attachment_path: str | None,
) -> tuple[str | None, str | None]:
    """Return (bundle attachment path) or (None, error)."""
    note_path = normalize_bundle_path(note_path)
    attachment_path = normalize_bundle_path(attachment_path or "")
    if attachment_path:
        resolved = resolve_bundle_attachment_path(
            notes, attachment_path, note_path=note_path
        )
        if resolved:
            return resolved, None
        return None, "attachment not found"
    if not note_path or not is_note_path(note_path) or not notes.store.exists(note_path):
        return None, "note not found"
    concept = notes.get(note_path)
    for att in concept.vesnai.get("attachments") or []:
        att = str(att)
        if att.lower().endswith(_IMAGE_EXTS) and notes.store.exists(att):
            return att, None
    return None, "no image attachment on note"


def read_note_attachment_payload(
    notes: NoteService,
    *,
    note_path: str = "",
    attachment_path: str = "",
    vision: VisionProvider | None = None,
    describe_images: bool = True,
) -> dict:
    resolved, err = _resolve_attachment_path(notes, note_path, attachment_path or None)
    if err:
        return {"error": err}
    assert resolved is not None
    att_path = resolved
    data = notes.store.read_attachment(att_path)
    name = att_path.split("/")[-1]
    result: dict = {"attachment_path": att_path, "mime_guess": name.split(".")[-1].lower()}

    if att_path.lower().endswith(_IMAGE_EXTS):
        if describe_images and vision is not None:
            cached = _cached_description_for_attachment(
                notes, att_path, note_path=note_path
            )
            if cached:
                result["description"] = cached
                return result
            prompt = (
                "Describe this image in detail for an artist: style, colors, mood, "
                "technique, composition. Be specific and concise."
            )
            desc, err = _vision_caption(vision, data, prompt)
            if err:
                return {"error": err, "attachment_path": att_path}
            result["description"] = desc or "(image; no description)"
        else:
            result["description"] = "(image; vision not available)"
        return result

    extracted = default_extractor(data, name).strip()
    if extracted:
        result["text"] = sanitize_untrusted_text(extracted[:READ_NOTE_BODY_MAX])
    else:
        result["text"] = ""
    return result


def style_prompt_from_reference(
    notes: NoteService,
    reference_path: str,
    vision: VisionProvider | None,
) -> str | None:
    """Build a style clause from a note path or attachment path."""
    result = resolve_style_reference(notes, reference_path, vision)
    return result.get("clause")


def resolve_style_reference(
    notes: NoteService,
    reference_path: str,
    vision: VisionProvider | None,
) -> dict:
    """Return ``clause`` and/or ``error`` for style-from-note image generation."""
    reference_path = normalize_bundle_path(reference_path or "")
    if not reference_path:
        return {}

    if is_note_path(reference_path) and notes.store.exists(reference_path):
        concept = notes.get(reference_path)
        if any(
            str(a).lower().endswith(_IMAGE_EXTS)
            for a in (concept.vesnai.get("attachments") or [])
        ):
            for att in concept.vesnai.get("attachments") or []:
                att = str(att)
                if not att.lower().endswith(_IMAGE_EXTS):
                    continue
                cached = _cached_attachment_description(concept, att)
                if cached:
                    return {"clause": f"Visual style reference: {cached}"}
            payload = read_note_attachment_payload(
                notes,
                note_path=reference_path,
                vision=vision,
                describe_images=True,
            )
            desc = payload.get("description")
            if isinstance(desc, str) and desc.strip():
                return {"clause": f"Visual style reference: {desc.strip()}"}
            clause = _note_context_clause(concept, reference_path)
            if clause:
                return {"clause": clause}
            if payload.get("error"):
                return {"error": str(payload["error"])}
        clause = _note_context_clause(concept, reference_path)
        if clause:
            return {"clause": clause}
        return {"clause": f"Inspired by note titled: {concept.title or reference_path}"}

    resolved = resolve_bundle_attachment_path(notes, reference_path)
    if resolved:
        cached = _cached_description_for_attachment(notes, resolved)
        if cached:
            return {"clause": f"Visual style reference: {cached}"}
        parent = find_note_for_attachment(notes, resolved)
        payload = read_note_attachment_payload(
            notes,
            note_path=parent or "",
            attachment_path=resolved,
            vision=vision,
            describe_images=True,
        )
        desc = payload.get("description") or payload.get("text")
        if isinstance(desc, str) and desc.strip():
            return {"clause": f"Visual style reference: {desc.strip()}"}
        if parent:
            concept = notes.get(parent)
            clause = _note_context_clause(concept, parent)
            if clause:
                return {"clause": clause}
        if payload.get("error"):
            return {"error": str(payload["error"])}
        return {}

    if notes.store.exists(reference_path):
        return {"error": "reference path is not a note or image attachment"}

    return {"error": "reference path not found"}


def list_due_notes_payload(notes: NoteService, resurfacing, *, limit: int = 20) -> dict:
    due_paths = resurfacing.due(notes.list())[: max(1, min(int(limit or 20), 50))]
    out: list[dict] = []
    for path in due_paths:
        if notes.store.exists(path):
            c = notes.get(path)
            out.append({"path": path, "title": c.title or path, "type": c.type})
    return {"due_notes": out}


def mark_note_resurfaced_payload(notes: NoteService, path: str, *, clock) -> dict:
    path = (path or "").strip()
    if not path:
        return {"error": "path is required"}
    if not notes.store.exists(path):
        return {"error": "note not found", "path": path}
    concept = notes.get(path)
    count = int(concept.vesnai.get("resurface_count", 0)) + 1
    concept.vesnai["resurface_count"] = count
    concept.vesnai["last_resurfaced"] = clock.now().isoformat()
    notes.store.write_concept(path, concept, message="mark resurfaced")
    return {"path": path, "resurface_count": count}


def mark_note_done_payload(notes: NoteService, path: str, *, done: bool = True) -> dict:
    path = (path or "").strip()
    if not path:
        return {"error": "path is required"}
    if not notes.store.exists(path):
        return {"error": "note not found", "path": path}
    concept = notes.update(path, done=bool(done))
    return {
        "path": path,
        "title": concept.title,
        "done": concept.done,
        "done_at": concept.done_at,
    }


def append_to_note_payload(
    notes: NoteService,
    path: str,
    text: str,
    *,
    separator: str = "\n\n",
) -> dict:
    path = (path or "").strip()
    snippet = (text or "").strip()
    if not path:
        return {"error": "path is required"}
    if not snippet:
        return {"error": "text is required"}
    if not notes.store.exists(path):
        return {"error": "note not found", "path": path}
    concept = notes.get(path)
    body = (concept.body or "").strip()
    sep = separator if separator else "\n\n"
    new_body = f"{body}{sep}{snippet}".strip() if body else snippet
    updated = notes.update(path, body=new_body)
    return {"updated": path, "title": updated.title, "body_length": len(new_body)}


def refresh_attachment_extracts(
    notes: NoteService,
    rel_path: str,
    concept,
    *,
    vision: VisionProvider | None,
) -> Concept:
    """Cache OCR/caption text on the concept for semantic search indexing."""
    from vesnai.okf.model import Concept

    assert isinstance(concept, Concept)
    extracts: dict[str, str] = {}
    existing = concept.vesnai.get("attachment_extracts")
    if isinstance(existing, dict):
        extracts = {str(k): str(v) for k, v in existing.items() if v}
    new_data = False
    for att in concept.vesnai.get("attachments") or []:
        att = str(att)
        if att in extracts or not notes.store.exists(att):
            continue
        data = notes.store.read_attachment(att)
        name = att.split("/")[-1]
        if att.lower().endswith(_IMAGE_EXTS):
            if vision is None:
                continue
            extracted, _err = _vision_caption(
                vision,
                data,
                "Extract visible text and describe key content briefly for search indexing.",
            )
            extracted = (extracted or "").strip()
        else:
            extracted = default_extractor(data, name).strip()
        if extracted:
            extracts[att] = sanitize_untrusted_text(extracted[:READ_NOTE_BODY_MAX])
            new_data = True
    if new_data:
        concept.vesnai["attachment_extracts"] = extracts
        notes.store.write_concept(rel_path, concept, message="cache attachment index text")
    return concept


def attachment_extract_parts(concept) -> list[str]:
    extracts = concept.vesnai.get("attachment_extracts")
    if not isinstance(extracts, dict):
        return []
    return [str(v) for v in extracts.values() if v]


def read_chat_attachment_payload(
    *,
    get_conversation,
    read_attachment: Callable[[str, str], bytes] | None,
    session_id: str,
    attachment_path: str,
    message_id: str = "",
    vision: VisionProvider | None = None,
    describe_images: bool = True,
) -> dict:
    session_id = (session_id or "").strip()
    attachment_path = (attachment_path or "").strip()
    message_id = (message_id or "").strip()
    if not session_id:
        return {"error": "session_id is required"}
    if not attachment_path:
        return {"error": "attachment_path is required"}
    if not get_conversation:
        return {"error": "chat sessions are not available"}
    convo = get_conversation(session_id)
    if convo is None:
        return {"error": "session not found", "session_id": session_id}
    stored_name = attachment_path.split("/")[-1]
    if not read_attachment:
        return {"error": "chat attachments are not available"}
    if message_id:
        msg = next((m for m in convo.messages if m.id == message_id), None)
        if msg is None:
            return {"error": "message not found", "message_id": message_id}
        paths = {str(a.get("path") or "") for a in (msg.attachments or [])}
        if stored_name not in paths and attachment_path not in paths:
            return {"error": "attachment not on message", "attachment_path": attachment_path}
    try:
        data = read_attachment(session_id, stored_name)
    except FileNotFoundError:
        return {"error": "attachment not found", "attachment_path": stored_name}
    name = stored_name
    result: dict = {
        "session_id": session_id,
        "attachment_path": stored_name,
        "mime_guess": name.split(".")[-1].lower(),
    }
    if stored_name.lower().endswith(_IMAGE_EXTS):
        if describe_images and vision is not None:
            prompt = (
                "Describe this image in detail for an artist: style, colors, mood, "
                "technique, composition. Be specific and concise."
            )
            desc, err = _vision_caption(vision, data, prompt)
            if err:
                return {"error": err, "attachment_path": stored_name}
            result["description"] = desc or "(image; no description)"
        else:
            result["description"] = "(image; vision not available)"
        return result
    extracted = default_extractor(data, name).strip()
    result["text"] = sanitize_untrusted_text(extracted[:READ_NOTE_BODY_MAX]) if extracted else ""
    return result
