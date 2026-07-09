"""Tool policy review agent tests."""

from __future__ import annotations

import json

from vesnai.ai.selftune import TrajectoryLog
from vesnai.ai.tool_policy_review import ToolPolicyReviewAgent, ToolPolicyStore, _parse_bullets
from vesnai.providers.fakes import FakeAIProvider, FakeClock


class _BulletFake(FakeAIProvider):
    def complete(self, prompt: str, *, temperature: float = 0.2, think: bool = False) -> str:
        return json.dumps({"bullets": ["Always call generate_image before claiming an image."]})


def test_parse_bullets():
    raw = '{"bullets": ["rule one", "rule two"]}'
    assert _parse_bullets(raw) == ["rule one", "rule two"]


def test_policy_review_updates_file(tmp_path):
    clock = FakeClock()
    traj = TrajectoryLog(tmp_path / "data")
    policy = ToolPolicyStore(tmp_path / "data")
    for _ in range(3):
        traj.append(
            {
                "message": "draw me",
                "tool_calls": [],
                "assistant_snippet": "Here is your image",
                "audit": {"missing_actions": ["generate_image"], "source": "llm"},
            }
        )
    agent = ToolPolicyReviewAgent(
        _BulletFake(), traj, policy, min_failures=3, clock=clock
    )
    assert agent.run_if_due(interval_hours=0) is True
    assert "generate_image" in policy.read()
