"""Background memory review agent tests."""

from __future__ import annotations

from vesnai.ai.conversations import ConversationStore
from vesnai.ai.memory_review import MemoryReviewAgent
from vesnai.ai.selftune import DurableMemoryStore
from vesnai.notes import NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.providers.base import ChatMessage, ToolCall
from vesnai.providers.fakes import FakeAIProvider


def test_memory_review_calls_update_memory(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    memory = DurableMemoryStore(notes)
    convos = ConversationStore(tmp_path / "data", clock=fake_clock)
    session = convos.create("Test")
    convos.append(session.id, "user", "I prefer concise answers in Polish")

    ai = FakeAIProvider(
        scripted=[
            ChatMessage(
                role="assistant",
                tool_calls=[
                    ToolCall(
                        name="update_memory",
                        arguments={
                            "action": "add",
                            "target": "user",
                            "entry": "Prefers concise answers in Polish",
                        },
                    )
                ],
            ),
            ChatMessage(role="assistant", content="Nothing else to save."),
        ]
    )
    agent = MemoryReviewAgent(ai, memory, convos, interval_turns=1)
    executed = agent.run_review(session.id)
    assert any(
        e.get("tool") == "update_memory"
        and e.get("result", {}).get("success")
        for e in executed
    )
    body = notes.get("memory/user.md").body
    assert "concise" in body.lower() or "Polish" in body
