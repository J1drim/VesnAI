"""Enrichment, chat tool-calling, search agent, graph, jobs."""

from __future__ import annotations

import pytest

from vesnai.ai.chat import ChatService, _normalize_tags, note_paths_from_tool_calls
from vesnai.ai.enrichment import KIND_CAPTION, KIND_IMAGE, EnrichmentService
from vesnai.ai.index import IndexService
from vesnai.ai.search_agent import SearchAgent, SearchPlanOut, _plain_fallback_queries
from vesnai.graph import build_graph
from vesnai.jobs import JobQueue, JobStatus
from vesnai.notes import NoteInput, NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.okf.model import Origin
from vesnai.providers.base import ChatMessage, SearchResult, ToolCall
from vesnai.providers.fakes import (
    FakeAIProvider,
    FakeEmbeddingProvider,
    FakeImageProvider,
    FakeSearchProvider,
    FakeVisionProvider,
)


@pytest.fixture
def env(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    notes = NoteService(store, clock=fake_clock)
    index = IndexService(FakeEmbeddingProvider())
    return store, notes, index, fake_clock


# --------------------------------------------------------------------------- #
# Enrichment
# --------------------------------------------------------------------------- #
def test_enrich_idea_creates_generated_child_with_backlink(env):
    store, notes, index, clock = env
    rel, _ = notes.create(NoteInput(title="Aurora trip", body="see the lights", type="Idea"))
    enr = EnrichmentService(notes, index, image_provider=FakeImageProvider(),
                            ai_provider=FakeAIProvider(), clock=clock)
    child = enr.enrich_idea(rel)
    child_concept = notes.get(child)
    assert child_concept.is_generated
    assert child_concept.type == KIND_IMAGE
    assert child_concept.source == rel
    # Source links back to the child.
    assert child in notes.get(rel).vesnai.get("links", [])


def test_enrich_idempotent(env):
    store, notes, index, clock = env
    rel, _ = notes.create(NoteInput(title="Idea", type="Idea"))
    enr = EnrichmentService(notes, index, image_provider=FakeImageProvider(),
                            ai_provider=FakeAIProvider(), clock=clock)
    first = enr.enrich_idea(rel)
    second = enr.enrich_idea(rel)
    assert first == second
    generated = [p for p, c in notes.list().items() if c.type == KIND_IMAGE]
    assert len(generated) == 1


def test_enrich_photo_caption_text_fallback(env):
    """Without an image attachment, captioning falls back to the text AI provider."""
    store, notes, index, clock = env
    rel, _ = notes.create(NoteInput(title="Beach sunset", body="orange sky", type="Photo"))
    enr = EnrichmentService(notes, index, image_provider=FakeImageProvider(),
                            ai_provider=FakeAIProvider(), vision_provider=FakeVisionProvider(),
                            clock=clock)
    child = enr.enrich_photo(rel)
    c = notes.get(child)
    assert c.type == KIND_CAPTION and c.is_generated and c.body.strip()
    assert "[fake-caption" not in c.body  # no image -> vision provider not used


def test_enrich_photo_uses_vision_on_attachment(env):
    """With an image attachment, the vision provider "sees" the photo to caption it."""
    store, notes, index, clock = env
    att_path = "attachments/beach.png"
    store.save_attachment(att_path, b"\x89PNG\r\n\x1a\nfake-image-bytes")
    rel, _ = notes.create(
        NoteInput(title="Beach sunset", body="orange sky", type="Photo",
                  attachments=[att_path])
    )
    enr = EnrichmentService(notes, index, image_provider=FakeImageProvider(),
                            ai_provider=FakeAIProvider(), vision_provider=FakeVisionProvider(),
                            clock=clock)
    child = enr.enrich_photo(rel)
    c = notes.get(child)
    assert c.type == KIND_CAPTION and c.is_generated
    # The deterministic vision caption (derived from the image bytes) is in the body.
    assert "[fake-caption" in c.body
    assert child in notes.get(rel).vesnai.get("links", [])  # source back-links the caption


# --------------------------------------------------------------------------- #
# Chat tool-calling
# --------------------------------------------------------------------------- #
def test_chat_executes_scripted_tool_calls(env):
    store, notes, index, clock = env
    scripted = [
        ChatMessage(role="assistant", tool_calls=[
            ToolCall(name="create_note", arguments={"title": "Groceries", "body": "milk"})
        ]),
        ChatMessage(role="assistant", content="Done - I created your note."),
    ]
    chat = ChatService(FakeAIProvider(scripted), index, notes)
    turn = chat.run("please save a groceries note")
    assert "Done" in turn.content
    assert any(t["tool"] == "create_note" for t in turn.tool_calls)
    titles = [c.title for c in notes.list().values()]
    assert "Groceries" in titles


def test_create_note_rejects_empty_title_and_body(env):
    store, notes, index, clock = env
    chat = ChatService(FakeAIProvider(), index, notes)
    result = chat._dispatch("create_note", {"title": "", "body": ""}, pending_jobs=[])
    assert result.get("error") == "title or body required"
    assert notes.list() == {}


def test_create_note_normalizes_string_tags(env):
    store, notes, index, clock = env
    chat = ChatService(FakeAIProvider(), index, notes)
    result = chat._dispatch(
        "create_note",
        {"title": "Trip", "body": "Plans", "tags": "research, travel"},
        pending_jobs=[],
    )
    assert "created" in result
    note = notes.get(result["created"])
    assert "research" in note.tags
    assert "travel" in note.tags


def test_normalize_tags_handles_various_shapes():
    assert _normalize_tags(None) == []
    assert _normalize_tags("a, b") == ["a", "b"]
    assert _normalize_tags(["x", "y"]) == ["x", "y"]


def test_note_paths_from_tool_calls():
    paths = note_paths_from_tool_calls(
        [
            {"tool": "create_note", "result": {"created": "notes/a.md"}},
            {"tool": "web_search", "result": {"research_note_path": "notes/r.md"}},
            {"tool": "generate_document", "result": {"note_path": "notes/d.md"}},
        ]
    )
    assert paths == ["notes/a.md", "notes/r.md", "notes/d.md"]


def test_web_search_save_as_note_creates_research_file(env):
    store, notes, index, clock = env
    search = FakeSearchProvider()
    search.add("topic", [
        SearchResult("Topic", "https://x.test/1", "snippet", "en"),
    ])
    agent = SearchAgent(search, FakeAIProvider(), notes, clock=clock)
    chat = ChatService(FakeAIProvider(), index, notes, search_agent=agent)
    result = chat._dispatch(
        "web_search",
        {"query": "topic", "save_as_note": True},
        pending_jobs=[],
    )
    path = result.get("research_note_path")
    assert path
    assert store.exists(path)


def test_chat_search_tool(env):
    store, notes, index, clock = env
    rel, c = notes.create(NoteInput(title="Quantum computing notes", body="qubits"))
    index.index_concept(rel, c)
    scripted = [
        ChatMessage(role="assistant", tool_calls=[
            ToolCall(name="search_notes", arguments={"query": "quantum"})
        ]),
        ChatMessage(role="assistant", content="Found your quantum notes."),
    ]
    chat = ChatService(FakeAIProvider(scripted), index, notes)
    turn = chat.run("what do I know about quantum?")
    search_calls = [t for t in turn.tool_calls if t["tool"] == "search_notes"]
    assert search_calls and search_calls[0]["result"]["results"]


def test_chat_transcript_persisted_as_generated(env):
    store, notes, index, clock = env
    chat = ChatService(FakeAIProvider(), index, notes)
    turn = chat.run("hello")
    rel = chat.persist_transcript("hello", turn)
    assert notes.get(rel).is_generated


def test_chat_session_transcript_creates_and_appends(env):
    store, notes, index, clock = env
    chat = ChatService(FakeAIProvider(), index, notes)
    turn1 = chat.run("hello")
    path = chat.persist_session_transcript("sess-1", "Morning chat", "hello", turn1)
    assert path == "memory/chats/sess-1.md"
    c = notes.get(path)
    assert c.type == "ChatTranscript"
    assert "**You:** hello" in c.body
    assert "[fake-reply]" in c.body

    turn2 = chat.run("again")
    chat.persist_session_transcript("sess-1", "Morning chat", "again", turn2)
    updated = notes.get(path)
    assert updated.body.count("---") == 1
    assert "**You:** again" in updated.body


# --------------------------------------------------------------------------- #
# Search agent
# --------------------------------------------------------------------------- #
def test_plain_fallback_queries_appends_location():
    variants = _plain_fallback_queries("restaurants nearby", location_hint="Pabianice")
    assert "restaurants nearby" in variants
    assert any("Pabianice" in q for q in variants)


def test_search_agent_llm_plan(env):
    store, notes, index, clock = env

    class _PlanFake(FakeAIProvider):
        def complete_structured(self, prompt, schema, *, temperature=0.2, think=False):
            return (
                '{"queries": ["restauracje Pabianice", "restaurants Pabianice"], '
                '"languages": ["pl", "en"], "needs_location": true}'
            )

    agent = SearchAgent(_PlanFake(), _PlanFake(), notes, clock=clock)
    plan = agent.plan("restaurants nearby", ["en"], location_hint="Pabianice")
    assert any("Pabianice" in q for q in plan.queries)
    assert "pl" in plan.languages


def test_search_agent_plain_fallback_when_llm_unparseable(env):
    store, notes, index, clock = env
    agent = SearchAgent(FakeAIProvider(), FakeAIProvider(), notes, clock=clock)
    plan = agent.plan("quantum computing", ["en"], location_hint="Kraków")
    assert plan.queries[0] == "quantum computing"
    assert any("Kraków" in q for q in plan.queries)


def test_search_plan_out_schema():
    parsed = SearchPlanOut.model_validate(
        {"queries": ["a"], "languages": ["pl"], "needs_location": True}
    )
    assert parsed.needs_location is True


def test_search_agent_run_for_chat(env):
    store, notes, index, clock = env
    search = FakeSearchProvider()
    search.add("aurora", [
        SearchResult("Aurora basics", "https://a.test/1", "about aurora", "en"),
    ])
    agent = SearchAgent(search, FakeAIProvider(), notes, clock=clock)
    result = agent.run_for_chat("aurora", max_seconds=30, save_as_note=False)
    assert result["sources"]
    assert "summary" in result
    assert result.get("research_note_path") is None


def test_chat_web_search_dispatch(env):
    store, notes, index, clock = env
    search = FakeSearchProvider()
    search.add("weather", [
        SearchResult("Weather today", "https://w.test/1", "sunny", "en"),
    ])
    agent = SearchAgent(search, FakeAIProvider(), notes, clock=clock)
    chat = ChatService(FakeAIProvider(), index, notes, search_agent=agent)
    pending: list[dict] = []
    result = chat._dispatch("web_search", {"query": "weather"}, pending_jobs=pending)
    assert result.get("sources")
    assert "summary" in result


def test_search_agent_writes_research_with_citations(env):
    store, notes, index, clock = env
    search = FakeSearchProvider()
    search.add("aurora", [
        SearchResult("Aurora basics", "https://a.test/1", "about aurora", "en"),
        SearchResult("Zorza polarna", "https://a.test/2", "o zorzy", "pl"),
    ])
    agent = SearchAgent(search, FakeAIProvider(), notes, clock=clock)
    rel = agent.run("aurora", languages=["en", "pl"], max_seconds=60)
    c = notes.get(rel)
    assert c.type == "Research" and c.is_generated
    assert "Citations" in c.body
    assert "https://a.test/1" in c.body


def test_role_wiring_separates_chat_and_reasoning(tmp_path):
    """Chat uses the chat provider; reasoning jobs/enrichment use the reasoning model."""
    from vesnai.app_state import AppState, Providers
    from vesnai.config import Settings
    from vesnai.providers.fakes import (
        FakeAIProvider,
        FakeClock,
        FakeEmbeddingProvider,
        FakeImageProvider,
        FakeSearchProvider,
        FakeSTTProvider,
        FakeTTSProvider,
        FakeVisionProvider,
    )

    chat_ai = FakeAIProvider()
    reasoning_ai = FakeAIProvider()
    vision = FakeVisionProvider()
    providers = Providers(
        ai=chat_ai,
        embedder=FakeEmbeddingProvider(),
        image=FakeImageProvider(),
        tts=FakeTTSProvider(),
        search=FakeSearchProvider(),
        stt=FakeSTTProvider(),
        reasoning=reasoning_ai,
        vision=vision,
    )
    settings = Settings(
        knowledge_dir=tmp_path / "kb",
        data_dir=tmp_path / "data",
        advertise_mdns=False,
        offline_only=True,
    )
    state = AppState(settings, clock=FakeClock(), providers=providers)

    assert state.chat.ai is chat_ai
    assert state.search_agent.ai is reasoning_ai
    assert state.memory.ai is reasoning_ai
    assert state.enrichment.vision_provider is vision
    assert state.enrichment.ai_provider is reasoning_ai


def test_search_agent_respects_time_budget(env):
    store, notes, index, clock = env

    class SlowSearch(FakeSearchProvider):
        def search(self, query, *, language="en", max_results=10):
            clock.advance(100)  # each search burns 100s
            return super().search(query, language=language, max_results=max_results)

    agent = SearchAgent(SlowSearch(), FakeAIProvider(), notes, clock=clock)
    rel = agent.run("topic", languages=["en", "pl", "de"], max_seconds=50)
    # Budget exceeded almost immediately -> few findings, but still produces a note.
    assert notes.get(rel).type == "Research"


# --------------------------------------------------------------------------- #
# Graph
# --------------------------------------------------------------------------- #
def test_graph_nodes_edges_and_broken_link_tolerated(env):
    store, notes, index, clock = env
    a, _ = notes.create(NoteInput(title="A", links=["notes/missing.md"]))
    b, _ = notes.create(NoteInput(title="B"))
    # Link A -> B explicitly.
    ca = notes.get(a)
    ca.vesnai["links"] = [b, "notes/missing.md"]
    store.write_concept(a, ca)
    g = build_graph(notes.list())
    ids = {n.id for n in g.nodes}
    assert a in ids and b in ids
    assert any(e.source == a and e.target == b for e in g.edges)
    # Broken link to missing.md produced no edge.
    assert all(e.target != "notes/missing.md" for e in g.edges)


def test_graph_filter_by_origin(env):
    store, notes, index, clock = env
    notes.create(NoteInput(title="user note", origin=Origin.USER))
    notes.create(NoteInput(title="gen note", origin=Origin.GENERATED))
    g = build_graph(notes.list(), origin=Origin.GENERATED)
    assert all(n.origin == "generated" for n in g.nodes)


def test_graph_filter_by_multiple_tags_or(env):
    store, notes, index, clock = env
    notes.create(NoteInput(title="a", tags=["work"]))
    notes.create(NoteInput(title="b", tags=["personal"]))
    notes.create(NoteInput(title="c", tags=["other"]))
    g = build_graph(notes.list(), tags=["work", "personal"])
    titles = {n.title for n in g.nodes}
    assert titles == {"a", "b"}


# --------------------------------------------------------------------------- #
# Jobs
# --------------------------------------------------------------------------- #
async def test_job_lifecycle_success():
    q = JobQueue()

    async def work(ctx):
        ctx.progress(0.5, "halfway")
        return {"ok": True}

    job = await q.run_to_completion("test", work)
    assert job.status is JobStatus.SUCCEEDED
    assert job.result == {"ok": True}
    assert job.progress == 1.0


async def test_job_failure_captured():
    q = JobQueue()

    async def boom(ctx):
        raise RuntimeError("kaboom")

    job = await q.run_to_completion("test", boom)
    assert job.status is JobStatus.FAILED
    assert "kaboom" in (job.error or "")
