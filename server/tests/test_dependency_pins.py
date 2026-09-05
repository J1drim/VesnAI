"""Keep runtime installers and the image register aligned with reviewed pins."""

import tomllib
from pathlib import Path

import yaml

from vesnai.runtime.mflux_cli import MFLUX_TOOL_SPEC


def test_mflux_bootstrap_matches_locked_image_extra():
    root = Path(__file__).resolve().parents[1]
    lock = tomllib.loads((root / "uv.lock").read_text())
    versions = {p["version"] for p in lock["package"] if p["name"] == "mflux"}
    assert versions == {MFLUX_TOOL_SPEC.split("==")[1]}


def test_container_image_register_matches_build_and_compose():
    root = Path(__file__).resolve().parents[1]
    images = yaml.safe_load((root / "compose-images.lock.yaml").read_text())["images"]
    dockerfile = (root / "Dockerfile").read_text()
    compose = yaml.safe_load((root / "docker-compose.yml").read_text())
    for name in ("python", "uv"):
        assert f"{images[name]['upstream']}@{images[name]['digest']}" in dockerfile
    for name in ("qdrant", "searxng"):
        assert compose["services"][name]["image"].endswith(images[name]["digest"])
    assert "uv sync --locked" in dockerfile
    assert "uv pip install --system" not in dockerfile
