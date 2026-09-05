"""NotificationStore feed: append / since / ack."""

from __future__ import annotations

import json
from unittest.mock import patch

import pytest

from vesnai.notifications import NotificationStore


def test_append_since_and_ack(tmp_path, fake_clock):
    store = NotificationStore(tmp_path, clock=fake_clock)
    fake_clock.advance(1)
    a = store.append(kind="image_ready", title="A", source_path="notes/a.md",
                     image_path="attachments/a.png")
    fake_clock.advance(1)
    b = store.append(kind="image_ready", title="B", source_path="notes/b.md")

    assert {n.id for n in store.list_all(unread_only=True)} == {a.id, b.id}
    # `since` returns only events strictly after the cursor.
    after_a = store.since(a.ts)
    assert [n.id for n in after_a] == [b.id]

    assert store.ack([a.id]) == 1
    unread = store.list_all(unread_only=True)
    assert [n.id for n in unread] == [b.id]
    # Acking again is a no-op.
    assert store.ack([a.id]) == 0


def test_delivery_is_per_device_and_atomic_replace_preserves_previous_feed(tmp_path):
    store = NotificationStore(tmp_path)
    event = store.append(kind='chat_turn_ready', title='Done')
    assert store.ack([event.id], device='phone') == 1
    assert store.list_all(unread_only=True, device='phone') == []
    assert [n.id for n in store.list_all(unread_only=True, device='desktop')] == [event.id]
    assert store.list_all()[0].read is False  # owner read state is distinct
    before = (tmp_path / 'notifications.json').read_bytes()
    with patch('vesnai.notifications.os.replace', side_effect=OSError('interrupted')), pytest.raises(OSError):
        store.append(kind='image_ready', title='Interrupted')
    assert (tmp_path / 'notifications.json').read_bytes() == before
    assert not list(tmp_path.glob('*.tmp'))


def test_legacy_global_read_migrates_without_realerting(tmp_path):
    store = NotificationStore(tmp_path)
    store.append(kind='image_ready', title='Already consumed')
    data = json.loads((tmp_path / 'notifications.json').read_text())
    data[0].pop('delivered_to')
    data[0].pop('legacy_delivered')
    data[0]['read'] = True
    (tmp_path / 'notifications.json').write_text(json.dumps(data))
    assert store.list_all(unread_only=True, device='new') == []
