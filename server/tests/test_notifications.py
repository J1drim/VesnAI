"""NotificationStore feed: append / since / ack."""

from __future__ import annotations

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
