"""update_memory and create_playbook chat tool dispatch tests."""

from __future__ import annotations

import pytest

from vesnai.ai.chat import ChatService
from vesnai.ai.selftune import DurableMemoryStore, SkillService
from vesnai.notes import NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.providers.base import ChatMessage, ToolCall
from vesnai.providers.fakes import FakeAIProvider


@pytest.fixture
def chat_env(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    memory = DurableMemoryStore(notes)
    skills = SkillService(notes)
    from vesnai.ai.index import IndexService
    from vesnai.providers.fakes import FakeEmbeddingProvider

    index = IndexService(FakeEmbeddingProvider())
    chat = ChatService(
        FakeAIProvider(),
        index,
        notes,
        memory_apply=memory.apply,
        skills=skills,
    )
    return chat, memory, notes, skills


def test_update_memory_via_dispatch(chat_env):
    chat, memory, notes, _ = chat_env
    result = chat._dispatch(
        "update_memory",
        {"action": "add", "target": "memory", "entry": "Dog named Bo"},
        pending_jobs=[],
    )
    assert result["success"]
    assert "Bo" in notes.get("memory/memory.md").body


def test_create_playbook_via_dispatch(chat_env):
    chat, _, notes, _ = chat_env
    result = chat._dispatch(
        "create_playbook",
        {"name": "Deploy VesnAI", "steps": ["Build app", "Restart server"]},
        pending_jobs=[],
    )
    assert result["success"]
    path = result["path"]
    assert notes.get(path).type == "Playbook"


def test_scripted_update_memory_turn(chat_env):
    chat, memory, notes, _ = chat_env
    chat.ai = FakeAIProvider(
        scripted=[
            ChatMessage(
                role="assistant",
                tool_calls=[
                    ToolCall(
                        name="update_memory",
                        arguments={
                            "action": "add",
                            "target": "user",
                            "entry": "Prefers tea",
                        },
                    )
                ],
            ),
            ChatMessage(role="assistant", content="I'll remember that."),
        ]
    )
    turn = chat.run("remember I prefer tea")
    assert any(t["tool"] == "update_memory" for t in turn.tool_calls)
    assert "tea" in notes.get("memory/user.md").body.lower()
