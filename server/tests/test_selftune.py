"""Self-tuning loop: classifier, resurfacing, consolidation, skills, user model."""

from __future__ import annotations

import pytest

from vesnai.ai.selftune import (
    USER_MODEL_LEGACY_PATH,
    DurableMemoryStore,
    FeedbackEvent,
    FeedbackStore,
    MemoryConsolidator,
    ResurfacingScheduler,
    SkillService,
    TagClassifier,
    TrajectoryLog,
    UserModelService,
)
from vesnai.notes import NoteInput, NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.providers.fakes import FakeAIProvider


@pytest.fixture
def notes(tmp_path, fake_clock):
    store = BundleStore(tmp_path / "kb", clock=fake_clock)
    return NoteService(store, clock=fake_clock)


def test_feedback_store_roundtrip(tmp_path):
    fs = FeedbackStore(tmp_path)
    fs.record(FeedbackEvent(text="buy milk", tags=["misc"], action="accepted"))
    fs.record(FeedbackEvent(text="great idea", tags=["idea"], action="added"))
    assert len(fs.all()) == 2


def test_tag_classifier_trains_and_improves_metric():
    train = [
        ("remember to buy milk and eggs", ["misc"]),
        ("groceries shopping list", ["misc"]),
        ("a brilliant startup idea about ai", ["idea"]),
        ("new idea for an app", ["idea"]),
    ]
    clf = TagClassifier()
    # Before training: no knowledge -> 0 accuracy.
    assert clf.evaluate(train) == 0.0
    clf.fit(train)
    after = clf.evaluate(train)
    assert after >= 0.75
    assert "idea" in clf.predict("another idea for an app")


def test_resurfacing_selects_due_notes(notes, fake_clock):
    rel, _ = notes.create(NoteInput(title="Old note"))
    sched = ResurfacingScheduler(clock=fake_clock)
    # Just created -> not due yet (first interval is 1 day).
    assert rel not in sched.due(notes.list())
    fake_clock.advance(2 * 86400)
    assert rel in sched.due(notes.list())


def test_resurfacing_skips_done_notes(notes, fake_clock):
    rel, _ = notes.create(NoteInput(title="Shopping list", body="milk, eggs"))
    fake_clock.advance(2 * 86400)
    sched = ResurfacingScheduler(clock=fake_clock)
    assert rel in sched.due(notes.list())
    # Marking the note done removes it from the review queue...
    notes.update(rel, done=True)
    assert rel not in sched.due(notes.list())
    # ...and reopening it brings it back.
    notes.update(rel, done=False)
    assert rel in sched.due(notes.list())


def test_memory_consolidation_creates_linked_memory(notes):
    a, _ = notes.create(NoteInput(title="Fact one", body="the sky is blue"))
    b, _ = notes.create(NoteInput(title="Fact two", body="water is wet"))
    mc = MemoryConsolidator(notes, FakeAIProvider())
    rel = mc.consolidate([a, b])
    c = notes.get(rel)
    assert c.type == "Memory" and c.is_generated
    assert a in c.vesnai.get("links", []) and b in c.vesnai.get("links", [])


def test_memory_upserts_into_single_note_and_dedupes(notes):
    mc = MemoryConsolidator(notes, FakeAIProvider())
    mc.upsert(["- likes tea", "- works at night"])
    # A second upsert appends new bullets and dedupes existing ones.
    mc.upsert(["- likes tea", "- has a dog named Bo"])
    assert mc.PATH == "memory/memory.md"
    body = mc.read()
    assert body.count("- likes tea") == 1
    assert "- works at night" in body
    assert "- has a dog named Bo" in body
    # Still a single memory.md note (user.md is separate).
    memory_notes = [
        p for p, c in notes.list().items()
        if c.type == "Memory" and p == "memory/memory.md"
    ]
    assert len(memory_notes) == 1


def test_consolidate_message_updates_memory(notes):
    mc = MemoryConsolidator(notes, FakeAIProvider())
    path = mc.consolidate_message("I prefer tea in the morning")
    assert path == MemoryConsolidator.PATH
    body = mc.read()
    assert "tea" in body.lower() or "prefer" in body.lower()


def test_skill_create_and_refine(notes):
    svc = SkillService(notes)
    rel = svc.create_skill("Weekly review", ["open notes", "summarize", "plan"])
    assert notes.get(rel).type == "Playbook"
    svc.refine_skill(rel, "archive done items")
    assert "archive done items" in notes.get(rel).body
    assert notes.get(rel).vesnai["skill_revision"] == 2


def test_user_model_evolves(notes):
    svc = UserModelService(notes)
    svc.update({"favorite_topic": "astronomy"})
    svc.update({"writing_style": "concise"})
    c = notes.get(UserModelService.PATH)
    assert c.vesnai["attributes"] == {"favorite_topic": "astronomy", "writing_style": "concise"}


def test_trajectory_compress_dedups(tmp_path):
    log = TrajectoryLog(tmp_path)
    log.append({"step": "a"})
    log.append({"step": "a"})
    log.append({"step": "b"})
    assert len(log.all()) == 3
    assert len(log.compress()) == 2


def test_durable_memory_apply_add_user_and_memory(notes):
    store = DurableMemoryStore(notes, disk_max_chars=100_000, prompt_max_chars=32_000)
    r1 = store.apply("add", "user", "Prefers concise answers")
    r2 = store.apply("add", "memory", "Dog is named Bo")
    assert r1["success"] and r2["success"]
    prompt = store.read_for_prompt()
    assert "concise" in prompt and "Bo" in prompt


def test_durable_memory_replace_and_remove(notes):
    store = DurableMemoryStore(notes)
    store.apply("add", "memory", "Works in Warsaw")
    store.apply("replace", "memory", "Works in Kraków", replace_match="Warsaw")
    body = notes.get("memory/memory.md").body
    assert "Kraków" in body and "Warsaw" not in body
    store.apply("remove", "memory", "", replace_match="Kraków")
    assert "Kraków" not in notes.get("memory/memory.md").body


def test_durable_memory_projects_target(notes):
    store = DurableMemoryStore(notes)
    r = store.apply("add", "projects", "Active: VesnAI chat UX")
    assert r["success"]
    assert notes.store.exists("memory/projects.md")


def test_durable_memory_disk_overflow(notes):
    store = DurableMemoryStore(notes, disk_max_chars=200, prompt_max_chars=100)
    long_entry = "x" * 120
    r1 = store.apply("add", "memory", long_entry)
    assert r1["success"]
    r2 = store.apply("add", "user", long_entry)
    assert r2.get("error") == "overflow"


def test_durable_memory_prompt_truncation(notes):
    store = DurableMemoryStore(notes, disk_max_chars=50_000, prompt_max_chars=500)
    for i in range(40):
        store.apply("add", "memory", f"Fact number {i} with some padding text")
    prompt = store.read_for_prompt()
    assert len(prompt) <= 600
    assert "truncated" in prompt.lower() or "Memory usage" in prompt


def test_user_model_migration_to_user_md(notes):
    from vesnai.okf.model import Concept, Origin

    concept = Concept(
        frontmatter={
            "type": "UserModel",
            "title": "User model",
            "tags": ["profile"],
            "vesnai": {
                "origin": Origin.GENERATED.value,
                "attributes": {"language": "Polish"},
            },
        },
        body="",
    )
    notes.store.write_concept(USER_MODEL_LEGACY_PATH, concept, message="test")
    _store = DurableMemoryStore(notes)
    body = notes.get("memory/user.md").body
    assert "Polish" in body
