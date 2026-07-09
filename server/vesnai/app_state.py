"""Dependency-injection container wiring all services together.

By default (offline mode) every AI capability is backed by the deterministic
fakes, so the server boots and is fully usable/testable with zero models. Real
local providers (Ollama/FLUX/whisper.cpp/SearXNG) are wired in by
:func:`vesnai.providers.factory.build_providers` when offline mode is disabled
and the integrations are installed.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass

from vesnai.ai.chat import ChatService
from vesnai.ai.conversations import ConversationStore
from vesnai.ai.enrichment import EnrichmentService
from vesnai.ai.index import IndexService
from vesnai.ai.memory_review import MemoryReviewAgent
from vesnai.ai.search_agent import SearchAgent
from vesnai.ai.selftune import (
    FeedbackStore,
    MemoryConsolidator,
    ResurfacingScheduler,
    SkillService,
    TagClassifier,
    TrajectoryLog,
    UserModelService,
    list_playbooks_for_prompt,
)
from vesnai.ai.tool_policy_review import ToolPolicyReviewAgent, ToolPolicyStore
from vesnai.ai.tool_receipts import ToolReceiptLedger
from vesnai.ai.turn_action_validator import TurnActionValidator
from vesnai.ai.voice import VoiceService
from vesnai.auth import AuthService
from vesnai.config import Settings, get_settings
from vesnai.jobs import JobQueue
from vesnai.notes import NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.providers.base import (
    AIProvider,
    Clock,
    EmbeddingProvider,
    ImageProvider,
    SearchProvider,
    STTProvider,
    SystemClock,
    TTSProvider,
    VisionProvider,
)
from vesnai.providers.fakes import (
    FakeAIProvider,
    FakeEmbeddingProvider,
    FakeImageProvider,
    FakeSearchProvider,
    FakeSTTProvider,
    FakeTTSProvider,
    FakeVisionProvider,
)
from vesnai.secrets import SecretStore
from vesnai.sync import SyncService
from vesnai.voice_registration import VoiceRegistrationStore


@dataclass
class Providers:
    ai: AIProvider  # interactive chat / voice / tool-calling (thinking off)
    embedder: EmbeddingProvider
    image: ImageProvider
    tts: TTSProvider
    search: SearchProvider
    stt: STTProvider
    reasoning: AIProvider  # background reasoning (thinking on)
    vision: VisionProvider  # multimodal photo captioning
    marena: AIProvider | None = None  # adversarial critic; None inherits reasoning

    def __post_init__(self) -> None:
        if self.marena is None:
            self.marena = self.reasoning


def default_fake_providers() -> Providers:
    return Providers(
        ai=FakeAIProvider(),
        embedder=FakeEmbeddingProvider(),
        image=FakeImageProvider(),
        tts=FakeTTSProvider(),
        search=FakeSearchProvider(),
        stt=FakeSTTProvider(),
        reasoning=FakeAIProvider(),
        vision=FakeVisionProvider(),
    )


class AppState:
    def __init__(
        self,
        settings: Settings | None = None,
        *,
        clock: Clock | None = None,
        providers: Providers | None = None,
    ) -> None:
        self.settings = settings or get_settings()
        self.settings.ensure_dirs()
        self.clock = clock or SystemClock()
        self.secrets = SecretStore(self.settings.data_dir)
        self.voice_registration = VoiceRegistrationStore(self.settings.data_dir)
        if providers is None:
            from vesnai.providers.factory import build_providers

            self.providers = build_providers(
                self.settings,
                secrets=self.secrets,
                voice_store=self.voice_registration,
            )
        else:
            self.providers = providers

        # Core
        self.store = BundleStore(self.settings.knowledge_dir, clock=self.clock)
        self.notes = NoteService(self.store, clock=self.clock)
        self.auth = AuthService(self.settings.data_dir, clock=self.clock)
        self.sync = SyncService(
            self.store, self.settings.data_dir, notes=self.notes, clock=self.clock
        )
        self.jobs = JobQueue()

        # AI
        from vesnai.providers.factory import build_vector_store

        self.index = IndexService(
            self.providers.embedder,
            store=build_vector_store(
                self.settings, dim=self.providers.embedder.dim
            ),
        )
        self._reindex_notes()
        # Keep the index live as the bundle changes.
        self.store.add_observer(self._on_store_change)

        self.enrichment = EnrichmentService(
            self.notes, self.index,
            image_provider=self.providers.image,
            ai_provider=self.providers.reasoning,
            vision_provider=self.providers.vision,
            clock=self.clock,
        )
        self.conversations = ConversationStore(self.settings.data_dir, clock=self.clock)
        self.search_agent = SearchAgent(
            self.providers.search, self.providers.reasoning, self.notes, clock=self.clock
        )
        from vesnai.ai.documents import DocumentService

        self.document_service = DocumentService(self.providers.reasoning)

        # Self-tuning (before chat — chat wires memory + skills)
        self.feedback = FeedbackStore(self.settings.data_dir)
        self.tag_classifier = TagClassifier()
        self.resurfacing = ResurfacingScheduler(clock=self.clock)
        self.memory = MemoryConsolidator(
            self.notes,
            self.providers.reasoning,
            disk_max_chars=self.settings.memory_disk_max_chars,
            prompt_max_chars=self.settings.memory_prompt_max_chars,
        )
        self.skills = SkillService(self.notes)
        self.user_model = UserModelService(self.notes)
        self.trajectories = TrajectoryLog(self.settings.data_dir)
        self.receipt_ledger = ToolReceiptLedger(self.settings.data_dir, clock=self.clock)
        self.tool_policy = ToolPolicyStore(self.settings.data_dir)
        self.memory_review = MemoryReviewAgent(
            self.providers.reasoning,
            self.memory,
            self.conversations,
            interval_turns=self.settings.memory_review_interval_turns,
        )

        self.chat = ChatService(
            self.providers.ai,
            self.index,
            self.notes,
            stt=self.providers.stt,
            submit_image_job=self._submit_chat_image_job,
            read_attachment=lambda sid, path: self.conversations.read_attachment(sid, path),
            append_attachment_to_note=self._append_attachment_to_note,
            search_agent=self.search_agent,
            document_service=self.document_service,
            save_chat_document=self._save_chat_document,
            memory_apply=self._memory_apply,
            skills=self.skills,
            list_playbooks=lambda: list_playbooks_for_prompt(self.notes),
            turn_action_validator=(
                TurnActionValidator(self.providers.reasoning)
                if self.settings.chat_turn_validation and not self.settings.offline_only
                else None
            ),
            receipt_ledger=self.receipt_ledger,
            read_tool_policy=self.tool_policy.read,
            search_max_seconds=float(self.settings.search_max_seconds),
            get_conversation=self.conversations.get,
            vision_provider=self.providers.vision,
            run_enrich=self._chat_enrich_note,
            list_due_notes=self._chat_list_due_notes,
        )
        self.tool_policy_review = ToolPolicyReviewAgent(
            self.providers.reasoning,
            self.trajectories,
            self.tool_policy,
            min_failures=self.settings.tool_policy_review_min_failures,
            clock=self.clock,
        )
        from vesnai.ai.marena_review import MarenaReviewAgent

        self.marena_review = MarenaReviewAgent(
            self.providers.marena or self.providers.reasoning,
            self.notes,
            search_agent=self.search_agent,
            web_search=(
                self.settings.marena_web_search
                and not self.settings.offline_only
                and self.settings.search_engine != "none"
            ),
            search_languages=self.settings.search_languages,
            max_notes_per_run=self.settings.marena_max_notes_per_run,
            clock=self.clock,
        )
        self._marena_inflight = False
        # Remote sidecar/OpenAI pick voices from the registration; Chatterbox
        # clones the reference WAV, so no per-request voice is needed.
        self.voice = VoiceService(
            self.chat,
            self.providers.tts,
            self.providers.stt,
        )

        # Notifications + serialized FLUX (auto-illustration). The lock keeps
        # concurrent image jobs from thrashing the GPU; other job kinds stay
        # concurrent.
        from vesnai.notifications import NotificationStore

        self.notifications = NotificationStore(self.settings.data_dir)
        self._flux_lock = asyncio.Lock()
        self._illustrate_inflight: set[str] = set()
        from vesnai.ai.chat_turn_queue import ChatTurnProcessor

        self.chat_turns = ChatTurnProcessor(self, clock=self.clock)
        self.jobs.on_complete(self._on_job_complete)

    # Note types that already are/contain imagery or are system bookkeeping, so
    # we never auto-illustrate them (prevents loops and clutter).
    NON_ILLUSTRATED_TYPES = frozenset(
        {
            "Photo",
            "GeneratedImage",
            "GeneratedCaption",
            "Memory",
            "UserModel",
            "Playbook",
            "Critique",
        }
    )
    NON_ILLUSTRATED_PREFIXES = ("memory/", "profile/")

    def _memory_apply(
        self,
        action: str,
        target: str,
        entry: str,
        *,
        replace_match: str | None = None,
    ) -> dict:
        return self.memory.apply(action, target, entry, replace_match=replace_match)

    def _chat_enrich_note(self, path: str, kind: str) -> str:
        if kind == "photo":
            return self.enrichment.enrich_photo(path)
        return self.enrichment.enrich_idea(path)

    def _chat_list_due_notes(self, limit: int) -> dict:
        from vesnai.ai.note_tools import list_due_notes_payload

        return list_due_notes_payload(self.notes, self.resurfacing, limit=limit)

    def _retrain_tag_classifier(self) -> None:
        examples: list[tuple[str, list[str]]] = []
        for event in self.feedback.all():
            if event.action in ("accepted", "added") and event.tags:
                examples.append((event.text, event.tags))
        if len(examples) >= 3:
            self.tag_classifier.fit(examples)

    def record_tag_feedback(self, text: str, tags: list[str], action: str) -> None:
        from vesnai.ai.selftune import FeedbackEvent

        self.feedback.record(FeedbackEvent(text=text, tags=tags, action=action))
        self._retrain_tag_classifier()

    def _reindex_notes(self) -> None:
        from vesnai.ai.note_tools import refresh_attachment_extracts

        concepts = self.notes.list()
        prepared: dict = {}
        for path, concept in concepts.items():
            prepared[path] = refresh_attachment_extracts(
                self.notes,
                path,
                concept,
                vision=self.providers.vision,
            )
        self.index.reindex(prepared)

    def _on_store_change(self, rel_path: str, deleted: bool) -> None:
        from vesnai.ai.note_tools import refresh_attachment_extracts
        from vesnai.okf.model import RESERVED_FILENAMES

        if rel_path.rsplit("/", 1)[-1] in RESERVED_FILENAMES or not rel_path.endswith(".md"):
            return
        if deleted:
            self.index.remove(rel_path)
            return
        if not self.store.exists(rel_path):
            return
        concept = self.store.read_concept(rel_path)
        concept = refresh_attachment_extracts(
            self.notes,
            rel_path,
            concept,
            vision=self.providers.vision,
        )
        self.index.index_concept(rel_path, concept)
        # Only illustrate on the first revision of a note. Updates (version > 1) and
        # post-enrichment link-back writes must not re-queue FLUX.
        version = int(concept.vesnai.get("version", 1))
        if (
            self.settings.auto_illustrate
            and self.settings.image_engine != "none"
            and version == 1
            and self._should_illustrate(rel_path, concept)
        ):
            self._schedule_illustration(rel_path)

    def _has_generated_image(self, rel_path: str) -> bool:
        for concept in self.notes.list().values():
            if (
                concept.is_generated
                and concept.type == "GeneratedImage"
                and concept.source == rel_path
            ):
                return True
        return False

    def _should_illustrate(self, rel_path: str, concept) -> bool:
        if ".conflict-" in rel_path:
            return False
        if any(rel_path.startswith(p) for p in self.NON_ILLUSTRATED_PREFIXES):
            return False
        if (concept.type or "") in self.NON_ILLUSTRATED_TYPES:
            return False
        if concept.vesnai.get("attachments"):
            return False
        if "attachments/" in (concept.body or ""):
            return False
        if self._has_generated_image(rel_path):
            return False
        return True

    def _schedule_illustration(self, rel_path: str) -> None:
        if self._has_generated_image(rel_path):
            return
        if rel_path in self._illustrate_inflight:
            return
        self._illustrate_inflight.add(rel_path)

        async def _run(ctx):
            from vesnai.ai.enrichment import KIND_IMAGE

            try:
                async with self._flux_lock:
                    existing = self.enrichment._existing_child(rel_path, KIND_IMAGE)
                    if existing:
                        return {
                            "source_path": rel_path,
                            "generated": existing,
                            "created": False,
                        }
                    generated = await asyncio.to_thread(
                        self.enrichment.enrich_idea, rel_path
                    )
                return {
                    "source_path": rel_path,
                    "generated": generated,
                    "created": True,
                }
            finally:
                self._illustrate_inflight.discard(rel_path)

        self.jobs.submit("auto_illustrate", _run)

    def _okf_chat_image_path(self, session_id: str, stored_name: str) -> str:
        from pathlib import Path

        session_stem = session_id.replace("-", "")[:8] or "chat"
        safe = Path(stored_name).name
        return f"attachments/{session_stem}-chat-{safe}"

    def _save_chat_document(
        self,
        session_id: str,
        message_id: str,
        data: bytes,
        filename: str,
        mime: str,
    ) -> dict:
        from vesnai.ai.documents import DocumentService

        att = self.conversations.save_attachment(
            session_id, filename, data, kind="document"
        )
        att["mime"] = mime
        self.conversations.add_message_attachment(session_id, message_id, att)
        session_stem = session_id.replace("-", "")[:8] or "chat"
        ext = filename.rsplit(".", 1)[-1] if "." in filename else "bin"
        okf_path = DocumentService.attachment_path(session_stem, f".{ext}")
        if not self.store.exists(okf_path):
            self.notes.store.save_attachment(okf_path, data)
        att["okf_attachment"] = okf_path
        return att

    def save_chat_attachment_to_note(
        self,
        session_id: str,
        filename: str,
        *,
        note_path: str | None = None,
        title: str | None = None,
    ) -> dict:
        from vesnai.notes import NoteInput
        from vesnai.okf.model import Origin

        data = self.conversations.read_attachment(session_id, filename)
        okf_path = self._okf_chat_image_path(session_id, filename)
        if not self.store.exists(okf_path):
            self.notes.store.save_attachment(okf_path, data)
        image_line = f"![generated]({okf_path})"
        if note_path:
            concept = self.notes.get(note_path)
            attachments = concept.vesnai.setdefault("attachments", [])
            if okf_path not in attachments:
                attachments.append(okf_path)
            body = concept.body.rstrip()
            if image_line not in body:
                body = f"{body}\n\n{image_line}\n" if body else f"{image_line}\n"
            concept = self.notes.update(note_path, body=body)
            self.index.index_concept(note_path, concept)
            return {"note_path": note_path, "attachment": okf_path}
        note_title = (title or "Chat image").strip() or "Chat image"
        rel, concept = self.notes.create(
            NoteInput(
                title=note_title,
                body=f"{image_line}\n",
                type="Photo",
                tags=["generated", "chat"],
                origin=Origin.USER,
                attachments=[okf_path],
            )
        )
        self.index.index_concept(rel, concept)
        return {"note_path": rel, "attachment": okf_path}

    def _append_attachment_to_note(
        self, note_path: str, session_id: str, attachment_path: str
    ) -> dict:
        return self.save_chat_attachment_to_note(
            session_id, attachment_path, note_path=note_path
        )

    async def _execute_chat_image_job(
        self,
        ctx,
        prompt: str,
        session_id: str,
        message_id: str,
        save_to_notes: bool,
    ) -> dict:
        import asyncio

        from vesnai.ai.image_prompts import build_chat_image_prompt
        from vesnai.notes import NoteInput
        from vesnai.okf.model import Origin

        flux_prompt = build_chat_image_prompt(prompt)
        ctx.progress(0.1, "generating image")
        async with self._flux_lock:
            image = await asyncio.to_thread(
                self.providers.image.generate, flux_prompt, seed=0
            )
        att = self.conversations.save_generated_image(session_id, image.data)
        self.conversations.add_message_attachment(session_id, message_id, att)
        okf_path = self._okf_chat_image_path(session_id, att["path"])
        self.notes.store.save_attachment(okf_path, image.data)
        note_path = None
        if save_to_notes:
            title = (prompt[:48] or "Generated image").strip() or "Generated image"
            rel, concept = self.notes.create(
                NoteInput(
                    title=title,
                    body=f"![generated]({okf_path})\n\n{prompt}".strip(),
                    type="Photo",
                    tags=["generated", "chat"],
                    origin=Origin.USER,
                    attachments=[okf_path],
                )
            )
            self.index.index_concept(rel, concept)
            note_path = rel
        ctx.progress(1.0, "done")
        return {
            "session_id": session_id,
            "message_id": message_id,
            "attachment": att,
            "okf_attachment": okf_path,
            "note_path": note_path,
        }

    def _submit_chat_image_job(
        self, prompt: str, session_id: str, message_id: str, save_to_notes: bool
    ) -> str:
        async def _run(ctx):
            return await self._execute_chat_image_job(
                ctx, prompt, session_id, message_id, save_to_notes
            )

        job = self.jobs.submit("chat_generate_image", _run)
        return job.id

    def retry_chat_action(
        self, session_id: str, message_id: str, action: str = "generate_image"
    ) -> dict:
        from vesnai.ai.chat import _chat_image_job_prompt

        if action != "generate_image":
            return {"error": f"unsupported action {action}"}
        msg = self.conversations.get_message(session_id, message_id)
        if msg is None or msg.role != "assistant":
            return {"error": "assistant message not found"}
        meta = dict(msg.metadata or {})
        pending = list(meta.get("pending_actions") or [])
        prompt = None
        for entry in pending:
            if entry.get("kind") == "generate_image" and entry.get("prompt"):
                prompt = entry["prompt"]
                break
        if not prompt:
            user_msg = self.conversations.preceding_user_message(session_id, message_id)
            had_image = bool(
                user_msg
                and any(a.get("kind") == "image" for a in (user_msg.attachments or []))
            )
            prompt = _chat_image_job_prompt(
                user_msg.content if user_msg else "",
                had_image_attachment=had_image,
            )
        job_id = self._submit_chat_image_job(prompt, session_id, message_id, False)
        updated_pending = [
            {
                "kind": "generate_image",
                "job_id": job_id,
                "prompt": prompt,
                "status": "queued",
            }
        ]
        meta["pending_actions"] = updated_pending
        self.conversations.update_message_metadata(session_id, message_id, meta)
        return {"job_id": job_id, "action": action, "status": "queued"}

    def maybe_run_tool_policy_review(self) -> bool:
        if self.settings.offline_only:
            return False
        return self.tool_policy_review.run_if_due(
            interval_hours=self.settings.tool_policy_review_interval_hours
        )

    def maybe_run_marena_review(self) -> bool:
        """Queue an idle Marena critique pass if due and there is work to do."""
        if not self.settings.marena_enabled:
            return False
        if self._marena_inflight:
            return False
        if not self.marena_review.should_run(
            interval_hours=self.settings.marena_interval_hours
        ):
            return False
        if not self.marena_review.candidates():
            self.marena_review.mark_ran()
            return False
        self._marena_inflight = True

        async def _run(ctx):
            try:
                created = await asyncio.to_thread(self.marena_review.run_once)
                return {"critiques": created}
            finally:
                self._marena_inflight = False

        self.jobs.submit("marena_review", _run)
        return True

    def _set_pending_action_status(
        self,
        session_id: str,
        message_id: str | None,
        job_id: str,
        status: str,
    ) -> None:
        if not session_id or not message_id:
            return
        msg = self.conversations.get_message(session_id, message_id)
        if msg is None:
            return
        meta = dict(msg.metadata or {})
        pending = list(meta.get("pending_actions") or [])
        changed = False
        for entry in pending:
            if entry.get("job_id") == job_id or entry.get("kind") == "generate_image":
                entry["status"] = status
                if job_id:
                    entry["job_id"] = job_id
                changed = True
        if changed:
            meta["pending_actions"] = pending
            self.conversations.update_message_metadata(session_id, message_id, meta)

    def _on_job_complete(self, job) -> None:
        from vesnai.jobs import JobStatus

        if job.kind == "chat_generate_image":
            result = job.result or {}
            session_id = result.get("session_id")
            message_id = result.get("message_id")
            if job.status is JobStatus.SUCCEEDED:
                attachment = result.get("attachment") or {}
                if session_id and message_id:
                    self._set_pending_action_status(
                        session_id, message_id, job.id, "succeeded"
                    )
                if session_id and attachment.get("path"):
                    self.notifications.append(
                        kind="chat_image_ready",
                        title="Chat image ready",
                        session_id=session_id,
                        attachment_path=attachment.get("path"),
                        message_id=message_id,
                        note_path=result.get("note_path"),
                        image_path=result.get("okf_attachment"),
                    )
            elif job.status is JobStatus.FAILED:
                if session_id and message_id:
                    self._set_pending_action_status(
                        session_id, message_id, job.id, "failed"
                    )
                if session_id:
                    self.notifications.append(
                        kind="chat_image_failed",
                        title="Chat image failed",
                        session_id=session_id,
                        message_id=message_id,
                    )
            return
        if job.status is not JobStatus.SUCCEEDED:
            return
        if job.kind == "marena_review":
            for entry in (job.result or {}).get("critiques") or []:
                self.notifications.append(
                    kind="critique_ready",
                    title=f"Marena: {entry.get('title') or 'Critique'}",
                    source_path=entry.get("source_path"),
                    note_path=entry.get("critique_path"),
                )
            return
        if job.kind != "auto_illustrate":
            return
        result = job.result or {}
        source_path = result.get("source_path")
        image_path = result.get("generated")
        if not source_path or not image_path:
            return
        if result.get("created") is False:
            return
        title = ""
        if self.store.exists(source_path):
            title = self.store.read_concept(source_path).title or ""
        self.notifications.append(
            kind="image_ready",
            title=f"Image ready: {title}" if title else "Image ready",
            source_path=source_path,
            image_path=image_path,
        )

    def reconcile_illustrations(self) -> int:
        """Enqueue auto-illustrate for text notes still missing a generated image.

        Runs once on startup so work queued before a restart isn't lost.
        """
        if not self.settings.auto_illustrate or self.settings.image_engine == "none":
            return 0
        notes = self.notes.list()
        have_image = {
            c.source
            for c in notes.values()
            if c.is_generated and c.type == "GeneratedImage" and c.source
        }
        scheduled = 0
        for rel, concept in notes.items():
            if rel in have_image:
                continue
            if self._should_illustrate(rel, concept):
                self._schedule_illustration(rel)
                scheduled += 1
        return scheduled
