"""Idle-time adversarial note critic ("Marena", the antithesis of Vesna).

When the user is idle, Marena walks through new or modified user notes and
plays devil's advocate: she hunts for loopholes in the logic, missing facts,
unhandled corner cases and (optionally, via web search) competing prior art.
If — and only if — she finds substantive issues, she writes a ``Critique``
note linked back to the original, marked with ``vesnai.critic: marena``.

Each note is reviewed at most once per version: after a review the original's
frontmatter is stamped with ``vesnai.marena_reviewed_version``. Editing a note
bumps its version and re-queues it; unchanged notes are never re-reviewed.
Notes marked done are skipped.
"""

from __future__ import annotations

import json
import logging

from vesnai.notes import NoteInput, NoteService
from vesnai.okf.model import Origin
from vesnai.providers.base import AIProvider, Clock, SystemClock

log = logging.getLogger(__name__)

MARENA_MARKER_KEY = "critic"
MARENA_MARKER_VALUE = "marena"
MARENA_REVIEWED_KEY = "marena_reviewed_version"
CRITIQUE_TYPE = "Critique"

CRITIC_PROMPT = (
    "You are Marena, a rigorous, adversarial reviewer of a user's personal note. "
    "You are the opposite of a cheerleader: your job is to find real weaknesses.\n"
    "Look for: logical loopholes, missing facts the plan depends on, unhandled "
    "corner cases, risky assumptions, and existing competition/prior art.\n"
    "Reply with JSON only, matching exactly:\n"
    '{"has_issues": boolean, "title": string, "critique": string, '
    '"search_query": string or null}\n'
    "Rules:\n"
    "- has_issues: true only for substantive problems. If the note is sound, "
    "trivial, or purely factual (a shopping list, a diary entry), return "
    "has_issues=false and empty strings.\n"
    "- critique: concise markdown (bullet points) naming each concrete gap or "
    "risk. No praise, no filler.\n"
    "- title: short critique title in the note's language.\n"
    "- search_query: a web query to find competing solutions or contradicting "
    "facts, or null if the critique needs no outside evidence.\n"
    "- Write the critique in the same language as the note.\n"
)

# Note types that are system bookkeeping / generated artifacts — never critiqued.
SKIP_TYPES = frozenset(
    {
        CRITIQUE_TYPE,
        "GeneratedImage",
        "GeneratedCaption",
        "ChatTranscript",
        "Research",
        "Memory",
        "UserModel",
        "Playbook",
    }
)
SKIP_PREFIXES = ("memory/", "profile/", "chats/")


def _parse_critique(raw: str) -> dict | None:
    text = (raw or "").strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    return data


class MarenaReviewAgent:
    def __init__(
        self,
        ai: AIProvider,
        notes: NoteService,
        *,
        search_agent=None,
        web_search: bool = True,
        search_languages: list[str] | None = None,
        max_notes_per_run: int = 3,
        clock: Clock | None = None,
    ) -> None:
        self.ai = ai
        self.notes = notes
        self.search_agent = search_agent
        self.web_search = web_search
        self.search_languages = search_languages or ["en"]
        self.max_notes_per_run = max_notes_per_run
        self.clock = clock or SystemClock()
        self._last_run_ts: float | None = None

    # -- candidate selection ------------------------------------------------

    def candidates(self) -> list[str]:
        """User notes that are new or modified since Marena's last review."""
        out: list[str] = []
        for path, concept in self.notes.list().items():
            if ".conflict-" in path:
                continue
            if any(path.startswith(p) for p in SKIP_PREFIXES):
                continue
            if concept.origin is Origin.GENERATED:
                continue
            if (concept.type or "Note") in SKIP_TYPES:
                continue
            if concept.vesnai.get("done"):
                continue
            if not (concept.body or "").strip():
                continue
            version = int(concept.vesnai.get("version", 1))
            reviewed = concept.vesnai.get(MARENA_REVIEWED_KEY)
            if reviewed is not None and int(reviewed) >= version:
                continue
            out.append(path)
        return out

    # -- scheduling ----------------------------------------------------------

    def should_run(self, *, interval_hours: float) -> bool:
        if self._last_run_ts is None:
            return True
        return self.clock.monotonic() - self._last_run_ts >= interval_hours * 3600

    def mark_ran(self) -> None:
        self._last_run_ts = self.clock.monotonic()

    # -- review --------------------------------------------------------------

    def _find_references(self, query: str) -> str:
        """Optional web-search step: competing solutions / contradicting facts."""
        if not (self.web_search and self.search_agent and query.strip()):
            return ""
        try:
            result = self.search_agent.run_for_chat(
                query,
                languages=self.search_languages,
                max_seconds=30.0,
                max_results_per_query=3,
                save_as_note=False,
            )
        except Exception:
            log.exception("marena_web_search_failed")
            return ""
        sources = result.get("sources") or []
        if not sources:
            return ""
        lines = ["", "## References found online", ""]
        for s in sources[:5]:
            title = s.get("title") or s.get("url") or ""
            url = s.get("url") or ""
            snippet = (s.get("snippet") or "").strip()
            entry = f"- [{title}]({url})"
            if snippet:
                entry += f" — {snippet}"
            lines.append(entry)
        return "\n".join(lines)

    def _stamp_reviewed(self, path: str, version: int) -> None:
        # Written via the store directly so stamping does not bump the note's
        # version (which would immediately re-queue it).
        concept = self.notes.get(path)
        concept.vesnai[MARENA_REVIEWED_KEY] = version
        self.notes.store.write_concept(
            path, concept, message=f"marena reviewed v{version}"
        )

    def review_note(self, path: str) -> str | None:
        """Review one note. Returns the created critique path, or None."""
        concept = self.notes.get(path)
        version = int(concept.vesnai.get("version", 1))
        note_text = (
            f"Title: {concept.title or '(untitled)'}\n"
            f"Type: {concept.type or 'Note'}\n"
            f"Tags: {', '.join(concept.tags)}\n\n"
            f"{(concept.body or '').strip()}"
        )[:8000]
        raw = self.ai.complete(
            f"{CRITIC_PROMPT}\nNote under review:\n{note_text}",
            temperature=0.0,
            think=True,
        )
        parsed = _parse_critique(raw)
        if parsed is None or not parsed.get("has_issues"):
            self._stamp_reviewed(path, version)
            return None
        critique = str(parsed.get("critique") or "").strip()
        if not critique:
            self._stamp_reviewed(path, version)
            return None
        title = str(parsed.get("title") or "").strip() or (
            f"Critique: {concept.title or path}"
        )
        search_query = parsed.get("search_query")
        references = self._find_references(str(search_query or ""))
        body = critique + references

        rel, critique_concept = self.notes.create(
            NoteInput(
                title=title,
                body=body,
                type=CRITIQUE_TYPE,
                tags=["critique", "marena"],
                origin=Origin.GENERATED,
                source=path,
                links=[path],
            )
        )
        critique_concept.vesnai[MARENA_MARKER_KEY] = MARENA_MARKER_VALUE
        self.notes.store.write_concept(
            rel, critique_concept, message="mark marena critique"
        )
        self._stamp_reviewed(path, version)
        return rel

    def run_once(self, *, max_notes: int | None = None) -> list[dict]:
        """Review up to ``max_notes`` candidates. Returns created critiques as
        ``{"critique_path", "source_path", "title"}`` dicts."""
        limit = max_notes if max_notes is not None else self.max_notes_per_run
        created: list[dict] = []
        for path in self.candidates()[: max(0, limit)]:
            try:
                rel = self.review_note(path)
            except Exception:
                log.exception("marena_review_failed path=%s", path)
                continue
            if rel:
                created.append(
                    {
                        "critique_path": rel,
                        "source_path": path,
                        "title": self.notes.get(rel).title or "Critique",
                    }
                )
        self.mark_ran()
        return created
