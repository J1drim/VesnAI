"""Marena idle critic: candidate selection, critique creation, re-review on edit."""

from __future__ import annotations

import json

import pytest

from vesnai.ai.marena_review import (
    CRITIQUE_TYPE,
    MARENA_MARKER_KEY,
    MARENA_MARKER_VALUE,
    MARENA_REVIEWED_KEY,
    MarenaReviewAgent,
)
from vesnai.notes import NoteInput, NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.okf.model import Origin


@pytest.fixture
def notes(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    return NoteService(store, clock=fake_clock)


class ScriptedAI:
    """Deterministic critic: returns a canned JSON verdict."""

    def __init__(self, payload: dict) -> None:
        self.payload = payload
        self.calls: list[str] = []

    def complete(self, prompt: str, **kwargs) -> str:
        self.calls.append(prompt)
        return json.dumps(self.payload)


class FakeSearchAgent:
    def __init__(self) -> None:
        self.queries: list[str] = []

    def run_for_chat(self, query: str, **kwargs) -> dict:
        self.queries.append(query)
        return {
            "summary": "- competitor exists",
            "sources": [
                {
                    "title": "Competitor",
                    "url": "https://example.com/competitor",
                    "snippet": "An existing app already does this.",
                }
            ],
        }


CLEAN = {"has_issues": False, "title": "", "critique": "", "search_query": None}
ISSUE = {
    "has_issues": True,
    "title": "Missing revenue model",
    "critique": "- No pricing plan.\n- Ignores existing competitors.",
    "search_query": "note taking app competitors",
}


def test_sound_note_creates_no_critique_but_stamps_version(notes, fake_clock):
    path, _ = notes.create(NoteInput(title="Plan", body="A solid, complete plan."))
    agent = MarenaReviewAgent(ScriptedAI(CLEAN), notes, clock=fake_clock)
    created = agent.run_once()
    assert created == []
    concept = notes.get(path)
    assert concept.vesnai[MARENA_REVIEWED_KEY] == 1
    # Nothing new was written to the bundle.
    assert [p for p, c in notes.list().items() if c.type == CRITIQUE_TYPE] == []


def test_issue_creates_linked_marena_critique(notes, fake_clock):
    path, _ = notes.create(NoteInput(title="Startup idea", body="I will build an app."))
    agent = MarenaReviewAgent(ScriptedAI(ISSUE), notes, clock=fake_clock)
    created = agent.run_once()
    assert len(created) == 1
    critique_path = created[0]["critique_path"]
    assert created[0]["source_path"] == path

    critique = notes.get(critique_path)
    assert critique.type == CRITIQUE_TYPE
    assert critique.origin is Origin.GENERATED
    assert critique.source == path
    assert path in critique.vesnai.get("links", [])
    assert critique.vesnai[MARENA_MARKER_KEY] == MARENA_MARKER_VALUE
    assert "No pricing plan" in critique.body
    assert notes.get(path).vesnai[MARENA_REVIEWED_KEY] == 1


def test_reviewed_note_is_not_requeued_until_edited(notes, fake_clock):
    path, _ = notes.create(NoteInput(title="Idea", body="Do the thing."))
    agent = MarenaReviewAgent(ScriptedAI(ISSUE), notes, clock=fake_clock)
    assert path in agent.candidates()
    agent.run_once()
    # Reviewed at current version: no longer a candidate, second run is a no-op.
    assert path not in agent.candidates()
    assert agent.run_once() == []
    # Editing bumps the version and re-queues the note.
    notes.update(path, body="Do the thing, but differently.")
    assert path in agent.candidates()


def test_skips_done_generated_and_critique_notes(notes, fake_clock):
    done_path, _ = notes.create(NoteInput(title="Shopping", body="milk", done=True))
    gen_path, _ = notes.create(
        NoteInput(title="Gen", body="x", origin=Origin.GENERATED)
    )
    agent = MarenaReviewAgent(ScriptedAI(ISSUE), notes, clock=fake_clock)
    candidates = agent.candidates()
    assert done_path not in candidates
    assert gen_path not in candidates
    # A critique written by Marena is never itself critiqued.
    idea, _ = notes.create(NoteInput(title="Idea", body="plan"))
    created = agent.run_once()
    critique_path = created[0]["critique_path"]
    assert critique_path not in agent.candidates()


def test_web_references_are_appended_when_search_available(notes, fake_clock):
    notes.create(NoteInput(title="Idea", body="I will build an app."))
    search = FakeSearchAgent()
    agent = MarenaReviewAgent(
        ScriptedAI(ISSUE), notes, search_agent=search, web_search=True, clock=fake_clock
    )
    created = agent.run_once()
    critique = notes.get(created[0]["critique_path"])
    assert search.queries == ["note taking app competitors"]
    assert "References found online" in critique.body
    assert "https://example.com/competitor" in critique.body


def test_web_search_disabled_writes_plain_critique(notes, fake_clock):
    notes.create(NoteInput(title="Idea", body="I will build an app."))
    search = FakeSearchAgent()
    agent = MarenaReviewAgent(
        ScriptedAI(ISSUE), notes, search_agent=search, web_search=False, clock=fake_clock
    )
    created = agent.run_once()
    assert search.queries == []
    assert "References found online" not in notes.get(created[0]["critique_path"]).body


def test_unparseable_llm_output_treated_as_no_issues(notes, fake_clock):
    class GarbageAI:
        def complete(self, prompt: str, **kwargs) -> str:
            return "I think this note is bad."

    path, _ = notes.create(NoteInput(title="Idea", body="plan"))
    agent = MarenaReviewAgent(GarbageAI(), notes, clock=fake_clock)
    assert agent.run_once() == []
    assert notes.get(path).vesnai[MARENA_REVIEWED_KEY] == 1


def test_max_notes_per_run_limits_batch(notes, fake_clock):
    for i in range(5):
        notes.create(NoteInput(title=f"Idea {i}", body="plan"))
    agent = MarenaReviewAgent(
        ScriptedAI(ISSUE), notes, max_notes_per_run=2, clock=fake_clock
    )
    assert len(agent.run_once()) == 2
    assert len(agent.candidates()) == 3


def test_should_run_respects_interval(notes, fake_clock):
    agent = MarenaReviewAgent(ScriptedAI(CLEAN), notes, clock=fake_clock)
    assert agent.should_run(interval_hours=6)
    agent.mark_ran()
    assert not agent.should_run(interval_hours=6)
    fake_clock.advance(7 * 3600)
    assert agent.should_run(interval_hours=6)
