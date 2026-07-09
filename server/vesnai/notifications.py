"""Local notification feed (no Firebase / push services).

Events (currently ``image_ready``) are appended to ``data_dir/notifications.json``
and drained by the app: it subscribes to the SSE stream while foregrounded and
drains the unread feed on launch/resume, raising a local OS notification per
event. Persisting the feed makes queued work survive a restart.
"""

from __future__ import annotations

import json
import threading
from dataclasses import asdict, dataclass
from pathlib import Path

from vesnai.ids import uuid7
from vesnai.providers.base import Clock, SystemClock


@dataclass
class Notification:
    id: str
    kind: str
    title: str
    source_path: str | None
    image_path: str | None
    ts: str
    read: bool = False
    session_id: str | None = None
    attachment_path: str | None = None
    message_id: str | None = None
    note_path: str | None = None
    pending_image: bool = False


class NotificationStore:
    def __init__(self, data_dir: Path | str, clock: Clock | None = None) -> None:
        self._path = Path(data_dir) / "notifications.json"
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self.clock = clock or SystemClock()
        self._lock = threading.Lock()

    def _load(self) -> list[dict]:
        if not self._path.exists():
            return []
        try:
            return json.loads(self._path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return []

    def _save(self, items: list[dict]) -> None:
        self._path.write_text(
            json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    def append(
        self,
        *,
        kind: str,
        title: str,
        source_path: str | None = None,
        image_path: str | None = None,
        session_id: str | None = None,
        attachment_path: str | None = None,
        message_id: str | None = None,
        note_path: str | None = None,
        pending_image: bool = False,
    ) -> Notification:
        note = Notification(
            id=uuid7(int(self.clock.now().timestamp() * 1000)),
            kind=kind,
            title=title,
            source_path=source_path,
            image_path=image_path,
            ts=self.clock.now().isoformat(),
            session_id=session_id,
            attachment_path=attachment_path,
            message_id=message_id,
            note_path=note_path,
            pending_image=pending_image,
        )
        with self._lock:
            items = self._load()
            items.append(asdict(note))
            self._save(items)
        return note

    def list_all(self, *, unread_only: bool = False) -> list[Notification]:
        items = self._load()
        notes = [Notification(**i) for i in items]
        if unread_only:
            notes = [n for n in notes if not n.read]
        return sorted(notes, key=lambda n: n.ts)

    def since(self, ts: str | None) -> list[Notification]:
        notes = self.list_all()
        if ts:
            notes = [n for n in notes if n.ts > ts]
        return notes

    def ack(self, ids: list[str]) -> int:
        target = set(ids)
        acked = 0
        with self._lock:
            items = self._load()
            for item in items:
                if item["id"] in target and not item.get("read"):
                    item["read"] = True
                    acked += 1
            self._save(items)
        return acked
