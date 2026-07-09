"""Auto-illustration: queue a FLUX image for new text notes (gated by setting)."""

from __future__ import annotations

import asyncio

from vesnai.app_state import AppState, default_fake_providers
from vesnai.config import Settings
from vesnai.jobs import Job, JobStatus
from vesnai.notes import NoteInput
from vesnai.okf.model import Origin
from vesnai.okf.parse import dump_concept
from vesnai.providers.fakes import FakeClock
from vesnai.sync import Change


def _state(tmp_path, *, auto_illustrate: bool) -> AppState:
    settings = Settings(
        knowledge_dir=tmp_path / "kb",
        data_dir=tmp_path / "data",
        offline_only=True,
        advertise_mdns=False,
        auto_illustrate=auto_illustrate,
    )
    return AppState(settings, clock=FakeClock(), providers=default_fake_providers())


def _illustrate_jobs(state: AppState) -> list[Job]:
    return [j for j in state.jobs.all() if j.kind == "auto_illustrate"]


def test_text_note_schedules_illustration_when_enabled(tmp_path):
    state = _state(tmp_path, auto_illustrate=True)
    state.notes.create(NoteInput(title="Aurora", body="see the northern lights"))
    assert len(_illustrate_jobs(state)) >= 1


def test_disabled_setting_schedules_nothing(tmp_path):
    state = _state(tmp_path, auto_illustrate=False)
    state.notes.create(NoteInput(title="Aurora", body="see the northern lights"))
    assert _illustrate_jobs(state) == []


def test_photo_and_generated_notes_are_skipped(tmp_path):
    state = _state(tmp_path, auto_illustrate=True)
    state.notes.create(NoteInput(title="Sunset", body="a photo", type="Photo"))
    state.notes.create(
        NoteInput(title="img", body="x", type="GeneratedImage", origin=Origin.GENERATED)
    )
    assert _illustrate_jobs(state) == []


def test_on_complete_writes_image_ready_notification(tmp_path):
    state = _state(tmp_path, auto_illustrate=True)
    rel, _ = state.notes.create(NoteInput(title="Idea", body="something memorable"))
    job = Job(id="j1", kind="auto_illustrate", status=JobStatus.SUCCEEDED)
    job.result = {"source_path": rel, "generated": "notes/idea-image.md"}
    state._on_job_complete(job)
    notes = state.notifications.list_all(unread_only=True)
    assert len(notes) == 1
    assert notes[0].kind == "image_ready"
    assert notes[0].source_path == rel


def test_reconcile_enqueues_missing_illustration(tmp_path):
    state = _state(tmp_path, auto_illustrate=True)
    state.notes.create(NoteInput(title="Idea", body="reconcile me"))
    # Drop any jobs queued by the observer; reconcile should re-enqueue.
    state.jobs._jobs.clear()
    scheduled = state.reconcile_illustrations()
    assert scheduled >= 1


def test_update_does_not_reillustrate_or_notify(tmp_path):
    state = _state(tmp_path, auto_illustrate=True)
    rel, _ = state.notes.create(NoteInput(title="Idea", body="reconcile me"))
    state.jobs._jobs.clear()
    # Simulate illustration already linked.
    state.notes.create(
        NoteInput(
            title="img",
            body="x",
            type="GeneratedImage",
            origin=Origin.GENERATED,
            source=rel,
        )
    )
    state.notes.update(rel, body="- [x] done\n- [ ] todo")
    assert _illustrate_jobs(state) == []
    job = Job(id="j1", kind="auto_illustrate", status=JobStatus.SUCCEEDED)
    job.result = {"source_path": rel, "generated": "notes/x.md", "created": False}
    state._on_job_complete(job)
    assert state.notifications.list_all(unread_only=True) == []


async def _drain_auto_illustrate(state: AppState) -> None:
    while not state.jobs._queue.empty():
        job, func = await state.jobs._queue.get()
        await state.jobs._run_one(job, func)


def test_sync_update_version_gt_one_skips_illustration(tmp_path):
    state = _state(tmp_path, auto_illustrate=True)
    rel, _ = state.notes.create(NoteInput(title="Idea", body="text"))
    state.jobs._jobs.clear()
    while not state.jobs._queue.empty():
        state.jobs._queue.get_nowait()
    concept = state.notes.get(rel)
    concept.vesnai["version"] = 2
    concept.body = "edited checklist"
    state.sync.push([Change(path=rel, doc=dump_concept(concept))], device="phone")
    assert _illustrate_jobs(state) == []


def test_second_illustrate_job_does_not_notify(tmp_path):
    state = _state(tmp_path, auto_illustrate=True)
    rel, _ = state.notes.create(NoteInput(title="Idea", body="text"))
    asyncio.run(_drain_auto_illustrate(state))
    assert state._has_generated_image(rel)
    before = len(state.notifications.list_all(unread_only=True))
    state._schedule_illustration(rel)
    asyncio.run(_drain_auto_illustrate(state))
    assert len(state.notifications.list_all(unread_only=True)) == before


def test_conflict_copy_is_never_illustrated(tmp_path):
    state = _state(tmp_path, auto_illustrate=True)
    rel, concept = state.notes.create(NoteInput(title="Dup", body="conflict"))
    conflict = rel[:-3] + ".conflict-phone.md"
    state.store.write_concept(conflict, concept, message="conflict copy")
    state.jobs._jobs.clear()
    while not state.jobs._queue.empty():
        state.jobs._queue.get_nowait()
    state.reconcile_illustrations()
    assert _illustrate_jobs(state) == []


def test_note_with_attachments_frontmatter_skips_illustration(tmp_path):
    state = _state(tmp_path, auto_illustrate=True)
    rel, concept = state.notes.create(NoteInput(title="Pic", body="see this"))
    state.jobs._jobs.clear()
    concept.vesnai["attachments"] = ["attachments/photo.png"]
    state.store.write_concept(rel, concept, message="attach")
    assert _illustrate_jobs(state) == []


def test_note_with_attachment_markdown_skips_illustration(tmp_path):
    state = _state(tmp_path, auto_illustrate=True)
    state.notes.create(
        NoteInput(
            title="Pic",
            body="Look ![photo](attachments/photo.png)",
        )
    )
    assert _illustrate_jobs(state) == []
