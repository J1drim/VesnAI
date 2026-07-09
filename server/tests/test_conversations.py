"""ConversationStore round-trip and titling."""

from __future__ import annotations

from vesnai.ai.conversations import ConversationStore


def test_create_append_list_and_delete(tmp_path, fake_clock):
    store = ConversationStore(tmp_path, clock=fake_clock)
    convo = store.create()
    assert convo.title == "New chat"

    store.append(convo.id, "user", "What is on my todo list today?")
    updated, _ = store.append(convo.id, "assistant", "You have two tasks.")
    # First user message becomes the title.
    assert updated.title.startswith("What is on my todo")
    assert [m.role for m in updated.messages] == ["user", "assistant"]

    fetched = store.get(convo.id)
    assert fetched is not None
    assert len(fetched.messages) == 2

    assert any(c.id == convo.id for c in store.list_all())
    assert store.delete(convo.id) is True
    assert store.get(convo.id) is None
    assert store.delete(convo.id) is False


def test_list_sorted_by_updated_desc(tmp_path, fake_clock):
    store = ConversationStore(tmp_path, clock=fake_clock)
    a = store.create(title="first")
    fake_clock.advance(60)
    b = store.create(title="second")
    fake_clock.advance(60)
    store.append(a.id, "user", "later activity on a")
    ids = [c.id for c in store.list_all()]
    # `a` was updated most recently, so it sorts first.
    assert ids[0] == a.id and b.id in ids
