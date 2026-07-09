"""Persistent multi-session chat storage."""

from __future__ import annotations

import json
import mimetypes
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path

from vesnai.ai.chat_language import detect_conversation_language
from vesnai.ids import uuid7
from vesnai.providers.base import Clock, SystemClock

_UNSAFE = re.compile(r"[^a-zA-Z0-9._-]+")


@dataclass
class ChatMessageRecord:
    role: str
    content: str
    ts: str
    id: str = ""
    attachments: list[dict] = field(default_factory=list)
    metadata: dict = field(default_factory=dict)


@dataclass
class Conversation:
    id: str
    title: str
    created: str
    updated: str
    language: str | None = None
    turns_since_memory: int = 0
    messages: list[ChatMessageRecord] = field(default_factory=list)

    def to_dict(self) -> dict:
        payload = {
            "id": self.id,
            "title": self.title,
            "created": self.created,
            "updated": self.updated,
            "messages": [asdict(m) for m in self.messages],
            "turns_since_memory": self.turns_since_memory,
        }
        if self.language:
            payload["language"] = self.language
        return payload

    @classmethod
    def from_dict(cls, raw: dict) -> Conversation:
        messages = []
        for m in raw.get("messages", []):
            messages.append(
                ChatMessageRecord(
                    role=m["role"],
                    content=m.get("content", ""),
                    ts=m.get("ts", ""),
                    id=m.get("id", ""),
                    attachments=list(m.get("attachments") or []),
                    metadata=dict(m.get("metadata") or {}),
                )
            )
        return cls(
            id=raw["id"],
            title=raw.get("title", "New chat"),
            created=raw["created"],
            updated=raw.get("updated", raw["created"]),
            language=raw.get("language"),
            turns_since_memory=int(raw.get("turns_since_memory", 0)),
            messages=messages,
        )


class ConversationStore:
    def __init__(self, data_dir: Path | str, clock: Clock | None = None) -> None:
        self._dir = Path(data_dir) / "conversations"
        self._dir.mkdir(parents=True, exist_ok=True)
        self.clock = clock or SystemClock()

    def _path(self, session_id: str) -> Path:
        return self._dir / f"{session_id}.json"

    def attachments_dir(self, session_id: str) -> Path:
        path = self._dir / session_id / "attachments"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def _now(self) -> str:
        return self.clock.now().isoformat()

    def create(self, title: str = "New chat") -> Conversation:
        now_dt = self.clock.now()
        now = now_dt.isoformat()
        convo = Conversation(
            id=uuid7(int(now_dt.timestamp() * 1000)), title=title, created=now, updated=now
        )
        self._write(convo)
        return convo

    def get(self, session_id: str) -> Conversation | None:
        path = self._path(session_id)
        if not path.exists():
            return None
        return Conversation.from_dict(json.loads(path.read_text(encoding="utf-8")))

    def list_all(self) -> list[Conversation]:
        convos = []
        for path in self._dir.glob("*.json"):
            try:
                convos.append(Conversation.from_dict(json.loads(path.read_text("utf-8"))))
            except (json.JSONDecodeError, KeyError):
                continue
        return sorted(convos, key=lambda c: c.updated, reverse=True)

    def delete(self, session_id: str) -> bool:
        path = self._path(session_id)
        if path.exists():
            path.unlink()
            return True
        return False

    def append(
        self,
        session_id: str,
        role: str,
        content: str,
        *,
        attachments: list[dict] | None = None,
        message_id: str | None = None,
        metadata: dict | None = None,
    ) -> tuple[Conversation, str]:
        convo = self.get(session_id)
        if convo is None:
            raise KeyError(session_id)
        now_dt = self.clock.now()
        msg_id = message_id or uuid7(int(now_dt.timestamp() * 1000))
        convo.messages.append(
            ChatMessageRecord(
                role=role,
                content=content,
                ts=self._now(),
                id=msg_id,
                attachments=list(attachments or []),
                metadata=dict(metadata or {}),
            )
        )
        convo.updated = self._now()
        if role == "user" and convo.title in ("", "New chat"):
            convo.title = _title_from(content)
        self._write(convo)
        return convo, msg_id

    def add_message_attachment(
        self, session_id: str, message_id: str, attachment: dict
    ) -> Conversation:
        convo = self.get(session_id)
        if convo is None:
            raise KeyError(session_id)
        for msg in convo.messages:
            if msg.id == message_id:
                msg.attachments.append(attachment)
                convo.updated = self._now()
                self._write(convo)
                return convo
        for msg in reversed(convo.messages):
            if msg.role == "assistant":
                msg.attachments.append(attachment)
                convo.updated = self._now()
                self._write(convo)
                return convo
        raise KeyError(message_id)

    def update_message_metadata(
        self, session_id: str, message_id: str, metadata: dict
    ) -> Conversation:
        convo = self.get(session_id)
        if convo is None:
            raise KeyError(session_id)
        for msg in convo.messages:
            if msg.id == message_id:
                merged = dict(msg.metadata or {})
                merged.update(metadata)
                msg.metadata = merged
                convo.updated = self._now()
                self._write(convo)
                return convo
        raise KeyError(message_id)

    def get_message(self, session_id: str, message_id: str) -> ChatMessageRecord | None:
        convo = self.get(session_id)
        if convo is None:
            return None
        for msg in convo.messages:
            if msg.id == message_id:
                return msg
        return None

    def preceding_user_message(
        self, session_id: str, assistant_message_id: str
    ) -> ChatMessageRecord | None:
        convo = self.get(session_id)
        if convo is None:
            return None
        found = False
        for msg in reversed(convo.messages):
            if msg.id == assistant_message_id:
                found = True
                continue
            if found and msg.role == "user":
                return msg
        return None

    def update_message_content(
        self, session_id: str, message_id: str, content: str
    ) -> Conversation:
        convo = self.get(session_id)
        if convo is None:
            raise KeyError(session_id)
        for msg in convo.messages:
            if msg.id == message_id:
                msg.content = content
                convo.updated = self._now()
                self._write(convo)
                return convo
        raise KeyError(message_id)

    def remove_message(self, session_id: str, message_id: str) -> Conversation:
        convo = self.get(session_id)
        if convo is None:
            raise KeyError(session_id)
        convo.messages = [m for m in convo.messages if m.id != message_id]
        convo.updated = self._now()
        self._write(convo)
        return convo

    def save_attachment(
        self,
        session_id: str,
        filename: str,
        data: bytes,
        *,
        kind: str,
    ) -> dict:
        safe_name = _UNSAFE.sub("_", Path(filename).name) or "upload.bin"
        stored = f"{uuid7()}-{safe_name}"
        dest = self.attachments_dir(session_id) / stored
        dest.write_bytes(data)
        mime, _ = mimetypes.guess_type(safe_name)
        return {
            "path": stored,
            "kind": kind,
            "filename": safe_name,
            "mime": mime or "application/octet-stream",
        }

    def read_attachment(self, session_id: str, stored_name: str) -> bytes:
        name = Path(stored_name).name
        path = self.attachments_dir(session_id) / name
        if not path.exists():
            raise FileNotFoundError(stored_name)
        return path.read_bytes()

    def save_generated_image(self, session_id: str, data: bytes) -> dict:
        stored = f"{uuid7()}-generated.png"
        dest = self.attachments_dir(session_id) / stored
        dest.write_bytes(data)
        return {
            "path": stored,
            "kind": "generated",
            "filename": "generated.png",
            "mime": "image/png",
        }

    def save_fetched_image(self, session_id: str, data: bytes, mime: str) -> dict:
        ext_by_mime = {
            "image/png": "png",
            "image/jpeg": "jpg",
            "image/webp": "webp",
            "image/gif": "gif",
        }
        normalized = (mime or "image/png").split(";")[0].strip().lower()
        ext = ext_by_mime.get(normalized, "bin")
        stored = f"{uuid7()}-fetched.{ext}"
        dest = self.attachments_dir(session_id) / stored
        dest.write_bytes(data)
        return {
            "path": stored,
            "kind": "fetched",
            "filename": f"fetched.{ext}",
            "mime": normalized or "application/octet-stream",
        }

    def refresh_language(self, session_id: str) -> Conversation:
        convo = self.get(session_id)
        if convo is None:
            raise KeyError(session_id)
        lang = detect_conversation_language(convo.messages)
        if lang and lang != convo.language:
            convo.language = lang
            self._write(convo)
        return convo

    def increment_turns_since_memory(self, session_id: str) -> Conversation:
        convo = self.get(session_id)
        if convo is None:
            raise KeyError(session_id)
        convo.turns_since_memory += 1
        self._write(convo)
        return convo

    def set_turns_since_memory(self, session_id: str, value: int) -> Conversation:
        convo = self.get(session_id)
        if convo is None:
            raise KeyError(session_id)
        convo.turns_since_memory = value
        self._write(convo)
        return convo

    def _write(self, convo: Conversation) -> None:
        self._path(convo.id).write_text(
            json.dumps(convo.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8"
        )


def _title_from(text: str, *, limit: int = 48) -> str:
    snippet = " ".join(text.strip().split())
    if not snippet:
        return "New chat"
    return snippet if len(snippet) <= limit else snippet[: limit - 1].rstrip() + "…"
