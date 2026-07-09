"""Per-session FIFO queue for async chat turn processing."""

from __future__ import annotations

import asyncio
import json
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import TYPE_CHECKING

from vesnai.ids import uuid7
from vesnai.observability import get_logger
from vesnai.providers.base import ChatMessage, Clock, SystemClock

if TYPE_CHECKING:
    from vesnai.app_state import AppState

log = get_logger("vesnai.chat_turns")

_TURN_TIMEOUT_MSG = (
    "Sorry, this reply timed out. Try again or start a new chat for long tasks."
)
_TURN_FAILED_MSG = "Sorry, I couldn't complete that reply."
_TURN_INTERRUPTED_MSG = (
    "Sorry, this reply was interrupted. Please send your message again."
)


@dataclass
class PendingTurn:
    turn_id: str
    user_message_id: str
    message: str
    attachment_refs: list[dict]
    assistant_language: str | None
    assistant_message_id: str
    enqueued_at: str
    persist_transcript: bool = False
    location_context: dict | None = None

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, raw: dict) -> PendingTurn:
        return cls(
            turn_id=raw["turn_id"],
            user_message_id=raw["user_message_id"],
            message=raw.get("message", ""),
            attachment_refs=list(raw.get("attachment_refs") or []),
            assistant_language=raw.get("assistant_language"),
            assistant_message_id=raw["assistant_message_id"],
            enqueued_at=raw["enqueued_at"],
            persist_transcript=bool(raw.get("persist_transcript", False)),
            location_context=raw.get("location_context"),
        )


class SessionTurnQueue:
    """Persisted FIFO queue for one chat session."""

    def __init__(self, data_dir: Path | str, session_id: str) -> None:
        self._dir = Path(data_dir) / "conversations" / session_id
        self._dir.mkdir(parents=True, exist_ok=True)
        self._path = self._dir / "queue.json"
        self._inflight_path = self._dir / "inflight.json"
        self.session_id = session_id

    def load(self) -> list[PendingTurn]:
        if not self._path.exists():
            return []
        try:
            raw = json.loads(self._path.read_text(encoding="utf-8"))
            return [PendingTurn.from_dict(item) for item in raw]
        except (json.JSONDecodeError, KeyError, TypeError):
            return []

    def save(self, turns: list[PendingTurn]) -> None:
        if not turns:
            if self._path.exists():
                self._path.unlink()
            return
        self._path.write_text(
            json.dumps([t.to_dict() for t in turns], ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def enqueue(self, turn: PendingTurn) -> int:
        items = self.load()
        items.append(turn)
        self.save(items)
        return len(items)

    def peek(self) -> PendingTurn | None:
        items = self.load()
        return items[0] if items else None

    def remove_first(self) -> PendingTurn | None:
        items = self.load()
        if not items:
            return None
        turn = items.pop(0)
        self.save(items)
        return turn

    def pop(self) -> PendingTurn | None:
        """Legacy alias — prefer peek/remove_first so turns survive until processed."""
        return self.remove_first()

    def depth(self) -> int:
        return len(self.load())

    def save_inflight(self, turn: PendingTurn) -> None:
        self._inflight_path.write_text(
            json.dumps(turn.to_dict(), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def load_inflight(self) -> PendingTurn | None:
        if not self._inflight_path.exists():
            return None
        try:
            raw = json.loads(self._inflight_path.read_text(encoding="utf-8"))
            return PendingTurn.from_dict(raw)
        except (json.JSONDecodeError, KeyError, TypeError):
            return None

    def clear_inflight(self) -> None:
        if self._inflight_path.exists():
            self._inflight_path.unlink()

    def has_pending_work(self) -> bool:
        return self.depth() > 0 or self._inflight_path.exists()


class ChatTurnProcessor:
    """Drains per-session turn queues in the background."""

    def __init__(self, state: AppState, clock: Clock | None = None) -> None:
        self._state = state
        self.clock = clock or SystemClock()
        self._locks: dict[str, asyncio.Lock] = {}
        self._draining: set[str] = set()

    def _queue(self, session_id: str) -> SessionTurnQueue:
        return SessionTurnQueue(self._state.settings.data_dir, session_id)

    def _lock_for(self, session_id: str) -> asyncio.Lock:
        if session_id not in self._locks:
            self._locks[session_id] = asyncio.Lock()
        return self._locks[session_id]

    def enqueue(
        self,
        session_id: str,
        *,
        user_message_id: str,
        message: str,
        attachment_refs: list[dict],
        assistant_language: str | None,
        assistant_message_id: str,
        persist_transcript: bool = False,
        location_context: dict | None = None,
    ) -> tuple[PendingTurn, int]:
        now = self.clock.now().isoformat()
        turn = PendingTurn(
            turn_id=uuid7(int(self.clock.now().timestamp() * 1000)),
            user_message_id=user_message_id,
            message=message,
            attachment_refs=list(attachment_refs),
            assistant_language=assistant_language,
            assistant_message_id=assistant_message_id,
            enqueued_at=now,
            persist_transcript=persist_transcript,
            location_context=location_context,
        )
        position = self._queue(session_id).enqueue(turn)
        return turn, position

    def kick(self, session_id: str) -> None:
        """Schedule drain from a running event loop (use kick_async in async routes)."""
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = asyncio.get_event_loop()
        if session_id in self._draining:
            return
        self._draining.add(session_id)
        loop.create_task(self._drain_session(session_id))

    async def kick_async(self, session_id: str) -> None:
        if session_id in self._draining:
            return
        self._draining.add(session_id)
        asyncio.create_task(self._drain_session(session_id))

    def recover_stale_assistant_messages(self) -> int:
        """Mark long-empty assistant placeholders as failed (orphaned turns)."""
        max_age_min = self._state.settings.stale_assistant_message_minutes
        recovered = 0
        for convo in self._state.conversations.list_all():
            for msg in convo.messages:
                if msg.role != "assistant" or msg.content.strip():
                    continue
                if not _ts_older_than_minutes(msg.ts, max_age_min, self.clock):
                    continue
                try:
                    self._state.conversations.update_message_content(
                        convo.id,
                        msg.id,
                        _TURN_INTERRUPTED_MSG,
                    )
                    self._state.conversations.update_message_metadata(
                        convo.id,
                        msg.id,
                        {"turn_failed": True},
                    )
                    recovered += 1
                except KeyError:
                    continue
        if recovered:
            log.info("chat_turn_recovered_stale", count=recovered)
        return recovered

    def resume_all(self) -> None:
        self.recover_stale_assistant_messages()
        base = Path(self._state.settings.data_dir) / "conversations"
        if not base.exists():
            return
        for session_dir in base.iterdir():
            if not session_dir.is_dir():
                continue
            queue = SessionTurnQueue(self._state.settings.data_dir, session_dir.name)
            if queue.has_pending_work():
                self.kick(session_dir.name)

    async def wait_until_idle(self, session_id: str, timeout: float = 5.0) -> None:
        deadline = asyncio.get_running_loop().time() + timeout
        while True:
            if session_id not in self._draining and not self._queue(session_id).has_pending_work():
                return
            if asyncio.get_running_loop().time() > deadline:
                raise TimeoutError(f"session {session_id} turn queue did not drain")
            await asyncio.sleep(0.02)

    async def _drain_session(self, session_id: str) -> None:
        lock = self._lock_for(session_id)
        async with lock:
            try:
                while True:
                    queue = self._queue(session_id)
                    turn = queue.peek()
                    if turn is None:
                        turn = queue.load_inflight()
                        if turn is None:
                            break
                        queue.enqueue(turn)
                        turn = queue.peek()
                    if turn is None:
                        break
                    queue.save_inflight(turn)
                    try:
                        await self._process_turn(session_id, turn)
                    finally:
                        queue.clear_inflight()
                        next_turn = queue.peek()
                        if next_turn is not None and next_turn.turn_id == turn.turn_id:
                            queue.remove_first()
            finally:
                self._draining.discard(session_id)
                if self._queue(session_id).has_pending_work():
                    self.kick(session_id)
                else:
                    await self._maybe_memory_review(session_id)

    async def _maybe_memory_review(self, session_id: str) -> None:
        convo = self._state.conversations.get(session_id)
        if convo is None:
            return
        if convo.turns_since_memory < self._state.settings.memory_review_interval_turns:
            return
        asyncio.create_task(self._run_memory_review(session_id))

    async def _run_memory_review(self, session_id: str) -> None:
        try:
            await asyncio.to_thread(self._state.memory_review.run_review, session_id)
        except Exception as exc:  # noqa: BLE001
            log.warning("memory_review_failed", session_id=session_id, error=str(exc))

    async def _process_turn(self, session_id: str, turn: PendingTurn) -> None:
        from vesnai.ai.chat_media import ChatAttachment

        convo = self._state.conversations.get(session_id)
        if convo is None:
            log.warning("chat_turn_missing_session", session_id=session_id)
            return

        history: list[ChatMessage] = []
        for msg in convo.messages:
            if msg.id == turn.user_message_id:
                break
            history.append(ChatMessage(role=msg.role, content=msg.content))

        max_hist = self._state.settings.chat_history_max_messages
        if max_hist > 0 and len(history) > max_hist:
            history = history[-max_hist:]

        attachments = [
            ChatAttachment(
                path=a["path"],
                kind=a.get("kind", "file"),
                filename=a.get("filename", a["path"]),
                mime=a.get("mime", ""),
            )
            for a in turn.attachment_refs
            if a.get("path")
        ]

        from vesnai.ai.chat_language import resolve_language

        language = resolve_language(
            user_setting=turn.assistant_language,
            session_language=convo.language,
            text=turn.message,
        )

        timeout = float(self._state.settings.chat_turn_timeout_seconds)

        try:
            from vesnai.ai.turn_context import TurnContext

            turn_ctx = TurnContext.from_location_dict(
                turn.location_context, language=language
            )
            turn_result = await asyncio.wait_for(
                asyncio.to_thread(
                    self._state.chat.run,
                    turn.message,
                    history=history,
                    memory=self._state.memory.read_for_prompt(),
                    language=language,
                    attachments=attachments if attachments else None,
                    session_id=session_id,
                    assistant_message_id=turn.assistant_message_id,
                    turn_context=turn_ctx,
                ),
                timeout=timeout,
            )
            self._state.conversations.update_message_content(
                session_id, turn.assistant_message_id, turn_result.content
            )
            if turn_result.pending_actions:
                self._state.conversations.update_message_metadata(
                    session_id,
                    turn.assistant_message_id,
                    {"pending_actions": turn_result.pending_actions},
                )
            pending_jobs = turn_result.pending_jobs or []
            pending_image = any(
                j.get("kind") == "chat_generate_image" for j in pending_jobs
            )
            if not pending_image:
                from vesnai.ai.chat_image_ingest import ingest_message_external_images

                ingested = ingest_message_external_images(
                    self._state.conversations,
                    session_id,
                    turn.assistant_message_id,
                    turn_result.content,
                )
                if ingested != turn_result.content:
                    self._state.conversations.update_message_content(
                        session_id, turn.assistant_message_id, ingested
                    )
            convo = self._state.conversations.get(session_id)
            self._state.chat.persist_session_transcript(
                session_id,
                convo.title if convo else "Chat",
                turn.message,
                turn_result,
            )
            memory_updated = any(
                t.get("tool") == "update_memory"
                and isinstance(t.get("result"), dict)
                and t["result"].get("success")
                for t in turn_result.tool_calls
            )
            if memory_updated:
                self._state.conversations.set_turns_since_memory(session_id, 0)
            else:
                self._state.conversations.increment_turns_since_memory(session_id)

            self._state.trajectories.append(
                {
                    "session_id": session_id,
                    "user_message_id": turn.user_message_id,
                    "message": turn.message[:500],
                    "tool_calls": [
                        {"tool": t.get("tool"), "result": t.get("result")}
                        for t in turn_result.tool_calls
                    ],
                    "assistant_snippet": (turn_result.content or "")[:500],
                    "audit": (
                        turn_result.audit.to_trajectory_dict()
                        if turn_result.audit is not None
                        else None
                    ),
                    "ts": self.clock.now().isoformat(),
                }
            )

            self._state.maybe_run_tool_policy_review()
            self._state.maybe_run_marena_review()

            self._state.conversations.refresh_language(session_id)
            pending_jobs = turn_result.pending_jobs or []
            pending_image = any(
                j.get("kind") == "chat_generate_image" for j in pending_jobs
            )
            from vesnai.ai.chat import note_paths_from_tool_calls

            created_notes = note_paths_from_tool_calls(turn_result.tool_calls)
            self._state.notifications.append(
                kind="chat_turn_ready",
                title="Chat reply ready",
                session_id=session_id,
                message_id=turn.assistant_message_id,
                attachment_path=None,
                note_path=created_notes[0] if created_notes else None,
                pending_image=pending_image,
            )
            if pending_image:
                pass  # chat_image_ready fires when FLUX job completes
        except TimeoutError:
            log.error(
                "chat_turn_timeout",
                session_id=session_id,
                turn_id=turn.turn_id,
                timeout_seconds=timeout,
            )
            self._fail_turn(
                session_id,
                turn.assistant_message_id,
                _TURN_TIMEOUT_MSG,
            )
        except Exception as exc:  # noqa: BLE001
            log.error(
                "chat_turn_failed",
                session_id=session_id,
                turn_id=turn.turn_id,
                error=str(exc),
            )
            self._fail_turn(
                session_id,
                turn.assistant_message_id,
                _TURN_FAILED_MSG,
            )

    def _fail_turn(
        self, session_id: str, assistant_message_id: str, message: str
    ) -> None:
        self._state.conversations.update_message_content(
            session_id,
            assistant_message_id,
            message,
        )
        self._state.conversations.update_message_metadata(
            session_id,
            assistant_message_id,
            {"turn_failed": True},
        )
        self._state.notifications.append(
            kind="chat_turn_failed",
            title="Chat reply failed",
            session_id=session_id,
            message_id=assistant_message_id,
        )


def _ts_older_than_minutes(ts: str, minutes: float, clock: Clock) -> bool:
    if not ts or minutes <= 0:
        return False
    try:
        created = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return False
    if created.tzinfo is None:
        created = created.replace(tzinfo=UTC)
    age = clock.now() - created.astimezone(UTC)
    return age.total_seconds() > minutes * 60
