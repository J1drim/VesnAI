"""Live LLM tool-calling tests (Ollama + real chat model).

These verify the model actually invokes VesnAI chat tools against a temp
knowledge bundle — not just harness wiring with FakeAIProvider.

Requires:
  - ``uv sync --extra ai`` (ollama package)
  - Ollama daemon running locally
  - Chat model installed (default ``qwen3.6``)

Run opt-in suite::

    cd server && uv run pytest -m live tests/test_live_llm_tools.py -v

Override model::

    VESNAI_TEST_CHAT_MODEL=qwen3.6 uv run pytest -m live tests/test_live_llm_tools.py -v

Regular CI excludes ``live`` tests (see ``.github/workflows/ci.yml``).
Nightly job runs ``pytest -m live``.
"""

from __future__ import annotations

import os
from typing import Any

import pytest

from vesnai.ai.chat import ChatService
from vesnai.ai.index import IndexService
from vesnai.ai.selftune import DurableMemoryStore, SkillService
from vesnai.notes import NoteInput, NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.okf.model import Origin
from vesnai.providers.fakes import FakeEmbeddingProvider

pytestmark = pytest.mark.live


def _ollama_host() -> str | None:
    return os.environ.get("OLLAMA_HOST") or os.environ.get("VESNAI_OLLAMA_HOST")


def _test_chat_model() -> str:
    return os.environ.get("VESNAI_TEST_CHAT_MODEL", "qwen3.6")


def ollama_skip_reason(model: str) -> str | None:
    """Return a skip reason if Ollama or the model is unavailable."""
    try:
        import ollama
    except ImportError:
        return "ollama package not installed (uv sync --extra ai)"

    try:
        from vesnai.providers.ollama import model_is_installed

        client = ollama.Client(host=_ollama_host())
        installed = {m.model for m in client.list().models}
        if not model_is_installed(model, installed):
            return f"Ollama model {model!r} not installed (have: {sorted(installed)[:8]}…)"
        # Minimal liveness ping (one token).
        client.chat(
            model=model,
            messages=[{"role": "user", "content": "ping"}],
            options={"num_predict": 1, "temperature": 0},
        )
    except Exception as exc:  # noqa: BLE001
        return f"Ollama not reachable: {exc}"
    return None


@pytest.fixture(scope="module")
def live_chat_model() -> str:
    model = _test_chat_model()
    reason = ollama_skip_reason(model)
    if reason:
        pytest.skip(reason)
    return model


@pytest.fixture
def seeded_knowledge(tmp_path, fake_clock):
    """Temp OKF bundle with a couple of notes for RAG context."""
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    rel1, c1 = notes.create(
        NoteInput(
            title="VesnAI project",
            body="Personal second-brain app with chat and OKF notes.",
            type="Note",
            tags=["project"],
            origin=Origin.USER,
        )
    )
    rel2, c2 = notes.create(
        NoteInput(
            title="Coffee preference",
            body="Usually drinks espresso in the morning.",
            type="Note",
            tags=["misc"],
            origin=Origin.USER,
        )
    )
    index.index_concept(rel1, c1)
    index.index_concept(rel2, c2)
    memory = DurableMemoryStore(notes)
    skills = SkillService(notes)
    return notes, index, memory, skills


@pytest.fixture
def live_chat(live_chat_model: str, seeded_knowledge):
    from vesnai.providers.ollama import OllamaAIProvider

    notes, index, memory, skills = seeded_knowledge
    ai = OllamaAIProvider(
        model=live_chat_model,
        host=_ollama_host(),
        think=False,
        keep_alive="5m",
    )
    chat = ChatService(
        ai,
        index,
        notes,
        memory_apply=memory.apply,
        skills=skills,
        search_agent=None,
    )
    return chat, memory, notes


def _tool_names(turn) -> set[str]:
    return {t.get("tool", "") for t in (turn.tool_calls or [])}


def _tool_results(turn, name: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for entry in turn.tool_calls or []:
        if entry.get("tool") != name:
            continue
        result = entry.get("result")
        if isinstance(result, dict):
            out.append(result)
    return out


@pytest.mark.live
def test_live_llm_calls_update_memory_on_remember(live_chat):
    chat, memory, notes = live_chat
    turn = chat.run(
        "Remember this for all future chats: my dog is named Bo. "
        "You must call the update_memory tool now with target memory.",
        language="en",
    )
    tools = _tool_names(turn)
    memory_results = _tool_results(turn, "update_memory")
    body = notes.get("memory/memory.md").body if notes.store.exists("memory/memory.md") else ""

    assert "update_memory" in tools, (
        f"Expected update_memory tool call; got tools={tools}, "
        f"reply={turn.content[:300]!r}"
    )
    assert any(r.get("success") for r in memory_results), memory_results
    assert "bo" in body.lower() or any(
        "bo" in str(r.get("entry", "")).lower() for r in memory_results
    ), f"Memory file missing Bo: {body[:400]!r}"


@pytest.mark.live
def test_live_llm_calls_create_note_when_asked(live_chat):
    chat, _, notes = live_chat
    before = set(notes.list())
    turn = chat.run(
        "Create a new note for me using the create_note tool. "
        "Title: Live test groceries. Body: buy milk and eggs. Do it now.",
        language="en",
    )
    tools = _tool_names(turn)
    create_results = _tool_results(turn, "create_note")
    after = set(notes.list())
    new_paths = after - before

    assert "create_note" in tools, (
        f"Expected create_note tool call; got tools={tools}, "
        f"reply={turn.content[:300]!r}"
    )
    assert any(r.get("created") for r in create_results) or new_paths, (
        f"No note created; results={create_results}, new_paths={new_paths}"
    )
    if new_paths:
        path = next(iter(new_paths))
        concept = notes.get(path)
        assert "groceries" in (concept.title or "").lower() or "milk" in concept.body.lower()


@pytest.mark.live
def test_live_llm_calls_create_playbook_for_procedure(live_chat):
    chat, _, notes = live_chat
    before = {p for p, c in notes.list().items() if c.type == "Playbook"}
    turn = chat.run(
        "Save this as a playbook skill using create_playbook. "
        "Name: Morning standup. Steps: check calendar, review tasks, pick top priority.",
        language="en",
    )
    tools = _tool_names(turn)
    pb_results = _tool_results(turn, "create_playbook")
    after = {p for p, c in notes.list().items() if c.type == "Playbook"}
    new_playbooks = after - before

    assert "create_playbook" in tools or new_playbooks, (
        f"Expected create_playbook; tools={tools}, reply={turn.content[:300]!r}"
    )
    if pb_results:
        assert any(r.get("success") and r.get("path") for r in pb_results)
    if new_playbooks:
        path = next(iter(new_playbooks))
        assert "standup" in notes.get(path).title.lower() or "Steps" in notes.get(path).body


@pytest.mark.live
def test_live_llm_polish_remember_triggers_update_memory(live_chat):
    """Polish trigger phrase (common for this user base)."""
    chat, _, notes = live_chat
    turn = chat.run(
        "Zapamiętaj na przyszłość: wolę krótkie odpowiedzi po polsku. "
        "Użyj narzędzia update_memory z target user.",
        language="pl",
    )
    tools = _tool_names(turn)
    assert "update_memory" in tools, (
        f"Expected update_memory for Polish remember prompt; tools={tools}, "
        f"reply={turn.content[:300]!r}"
    )
    if notes.store.exists("memory/user.md"):
        assert "polsk" in notes.get("memory/user.md").body.lower() or any(
            r.get("success")
            for r in _tool_results(turn, "update_memory")
        )
