"""Shared pytest fixtures."""

from __future__ import annotations

from pathlib import Path

import pytest

from vesnai.okf.bundle import BundleStore
from vesnai.providers.fakes import FakeClock

REPO_ROOT = Path(__file__).resolve().parents[2]
OKF_FIXTURES = REPO_ROOT / "fixtures" / "okf"


@pytest.fixture(autouse=True)
def _reset_rate_limits():
    """In-process rate limiters must not leak state between tests."""
    from vesnai import security
    from vesnai.api import routes

    security._pair_redeem_hits.clear()
    security._pair_redeem_global_hits.clear()
    routes._pair_code_hits.clear()
    yield
    security._pair_redeem_hits.clear()
    security._pair_redeem_global_hits.clear()
    routes._pair_code_hits.clear()


@pytest.fixture
def fake_clock() -> FakeClock:
    return FakeClock()


@pytest.fixture
def bundle(tmp_path: Path, fake_clock: FakeClock) -> BundleStore:
    return BundleStore(tmp_path / "knowledge", clock=fake_clock)


@pytest.fixture
def okf_fixtures_dir() -> Path:
    return OKF_FIXTURES
