"""Hermes-style background memory review (update_memory only)."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

from vesnai.ai.tool_schemas import UPDATE_MEMORY_TOOL
from vesnai.providers.base import ChatMessage

if TYPE_CHECKING:
    from vesnai.ai.conversations import ConversationStore
    from vesnai.ai.selftune import DurableMemoryStore
    from vesnai.providers.base import AIProvider

MEMORY_REVIEW_PROMPT = (
    "Review the recent conversation for durable facts, user preferences, or active project "
    "focus worth saving. Use update_memory only when something stable and future-relevant "
    "was revealed. Prefer add for new facts; replace when correcting prior memory; remove "
    "when obsolete. Most reviews should produce zero writes. Reply briefly if nothing to save."
)


class MemoryReviewAgent:
    MAX_ITERATIONS = 5

    def __init__(
        self,
        ai: AIProvider,
        memory: DurableMemoryStore,
        conversations: ConversationStore,
        *,
        interval_turns: int = 10,
    ) -> None:
        self.ai = ai
        self.memory = memory
        self.conversations = conversations
        self.interval_turns = interval_turns

    def run_review(self, session_id: str) -> list[dict]:
        convo = self.conversations.get(session_id)
        if convo is None:
            return []
        recent = convo.messages[-20:]
        if not recent:
            return []
        transcript = "\n".join(
            f"{m.role}: {m.content[:500]}" for m in recent if m.content.strip()
        )
        memory_ctx = self.memory.read_for_prompt()
        messages = [
            ChatMessage(role="system", content=MEMORY_REVIEW_PROMPT),
            ChatMessage(
                role="user",
                content=f"Current memory:\n{memory_ctx or '(empty)'}\n\nConversation:\n{transcript}",
            ),
        ]
        executed: list[dict] = []
        for _ in range(self.MAX_ITERATIONS):
            reply = self.ai.chat(messages, tools=[UPDATE_MEMORY_TOOL])
            if not reply.tool_calls:
                break
            messages.append(reply)
            for call in reply.tool_calls:
                if call.name != "update_memory":
                    result = {"success": False, "error": "only update_memory allowed"}
                else:
                    result = self.memory.apply(
                        call.arguments.get("action", "add"),
                        call.arguments.get("target", "memory"),
                        call.arguments.get("entry", ""),
                        replace_match=call.arguments.get("replace_match"),
                    )
                executed.append({"tool": call.name, "arguments": call.arguments, "result": result})
                messages.append(
                    ChatMessage(role="tool", name=call.name, content=json.dumps(result))
                )
        if any(
            e.get("tool") == "update_memory"
            and isinstance(e.get("result"), dict)
            and e["result"].get("success")
            for e in executed
        ):
            self.conversations.set_turns_since_memory(session_id, 0)
        return executed
