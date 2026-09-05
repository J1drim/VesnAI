"""Local notification feed (no Firebase / push services).

Completion events are atomically persisted to ``data_dir/notifications.json``.
Foreground/background pollers acknowledge delivery per authenticated device;
owner-wide read state is separate. SSE remains an optional transport.
"""

from __future__ import annotations

import json
import os
import tempfile
import threading
from dataclasses import asdict, dataclass, field
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
    delivered_to: list[str] = field(default_factory=list)
    legacy_delivered: bool = False


class NotificationStore:
    def __init__(self, data_dir: Path | str, clock: Clock | None = None) -> None:
        self._path = Path(data_dir) / "notifications.json"
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self.clock = clock or SystemClock()
        self._lock = threading.Lock()

    def _load(self) -> list[dict]:
        if not self._path.exists():
            return []
        items = json.loads(self._path.read_text(encoding="utf-8"))
        # Previously consumed global events must not flood upgraded devices.
        for item in items:
            if 'delivered_to' not in item:
                item['legacy_delivered'] = bool(item.get('read'))
                item['delivered_to'] = []
        return items

    def _save(self, items: list[dict]) -> None:
        fd, path = tempfile.mkstemp(dir=self._path.parent, prefix='.notifications-', suffix='.tmp')
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as output:
                json.dump(items, output, ensure_ascii=False, indent=2)
                output.flush()
                os.fsync(output.fileno())
            os.replace(path, self._path)
        finally:
            Path(path).unlink(missing_ok=True)

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

    def list_all(self, *, unread_only: bool = False, device: str | None = None) -> list[Notification]:
        items = self._load()
        notes = [Notification(**i) for i in items]
        if unread_only:
            notes = [n for n in notes if (not n.read if device is None else
                     device not in n.delivered_to and not n.legacy_delivered)]
        return sorted(notes, key=lambda n: n.ts)

    def since(self, ts: str | None) -> list[Notification]:
        notes = self.list_all()
        if ts:
            notes = [n for n in notes if n.ts > ts]
        return notes

    def ack(self, ids: list[str], *, device: str | None = None) -> int:
        target = set(ids)
        acked = 0
        with self._lock:
            items = self._load()
            for item in items:
                if item['id'] not in target:
                    continue
                if device is None:
                    if not item.get('read'):
                        item['read'] = True
                        acked += 1
                elif device not in item['delivered_to']:
                    item['delivered_to'].append(device)
                    acked += 1
            self._save(items)
        return acked
