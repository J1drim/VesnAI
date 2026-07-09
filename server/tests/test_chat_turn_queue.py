"""Async chat turn queue tests."""

from __future__ import annotations

from vesnai.ai.chat_turn_queue import PendingTurn, SessionTurnQueue
from vesnai.ai.conversations import ConversationStore


def test_session_queue_persist_and_pop(tmp_path, fake_clock):
    q = SessionTurnQueue(tmp_path, "sess-1")
    turn = PendingTurn(
        turn_id="t1",
        user_message_id="u1",
        message="hi",
        attachment_refs=[],
        assistant_language=None,
        assistant_message_id="a1",
        enqueued_at=fake_clock.now().isoformat(),
    )
    assert q.enqueue(turn) == 1
    assert q.depth() == 1
    peeked = q.peek()
    assert peeked is not None
    assert peeked.user_message_id == "u1"
    assert q.depth() == 1
    loaded = q.remove_first()
    assert loaded is not None
    assert loaded.user_message_id == "u1"
    assert q.depth() == 0


def test_session_queue_inflight(tmp_path, fake_clock):
    q = SessionTurnQueue(tmp_path, "sess-2")
    turn = PendingTurn(
        turn_id="t2",
        user_message_id="u2",
        message="hello",
        attachment_refs=[],
        assistant_language=None,
        assistant_message_id="a2",
        enqueued_at=fake_clock.now().isoformat(),
    )
    q.enqueue(turn)
    q.save_inflight(turn)
    assert q.load_inflight() is not None
    assert q.has_pending_work()
    q.clear_inflight()
    assert q.load_inflight() is None
    assert q.has_pending_work()


def test_update_message_content(tmp_path, fake_clock):
    store = ConversationStore(tmp_path, clock=fake_clock)
    convo = store.create()
    _, msg_id = store.append(convo.id, "assistant", "")
    store.update_message_content(convo.id, msg_id, "Hello there")
    fetched = store.get(convo.id)
    assert fetched.messages[-1].content == "Hello there"
