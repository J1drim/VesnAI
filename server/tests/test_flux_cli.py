"""FLUX image provider must require the isolated mflux-generate CLI."""

from __future__ import annotations

import subprocess

import pytest

from vesnai.providers.flux import MfluxImageProvider


def test_generate_raises_clear_error_without_cli(monkeypatch):
    # Simulate the CLI being absent (e.g. running in the Chatterbox env).
    monkeypatch.setattr("vesnai.providers.flux.find_mflux_generate", lambda: None)
    provider = MfluxImageProvider()
    with pytest.raises(RuntimeError, match="uv tool install mflux"):
        provider.generate("a calm forest at dawn")


def _fake_run(returncode: int, stderr: str = "", stdout: str = ""):
    def run(cmd, **kwargs):
        return subprocess.CompletedProcess(cmd, returncode, stdout=stdout, stderr=stderr)

    return run


def test_generate_surfaces_mflux_stderr(monkeypatch):
    monkeypatch.setattr("vesnai.providers.flux.find_mflux_generate", lambda: "/bin/mflux-generate")
    monkeypatch.setattr(
        "vesnai.providers.flux.subprocess.run",
        _fake_run(1, stderr="boom: out of memory"),
    )
    provider = MfluxImageProvider()
    with pytest.raises(RuntimeError, match="boom: out of memory"):
        provider.generate("a calm forest at dawn")


def test_generate_explains_gated_repo(monkeypatch):
    monkeypatch.setattr("vesnai.providers.flux.find_mflux_generate", lambda: "/bin/mflux-generate")
    gated = "GatedRepoError: Access to model black-forest-labs/FLUX.1-schnell is restricted."
    monkeypatch.setattr(
        "vesnai.providers.flux.subprocess.run", _fake_run(1, stderr=gated)
    )
    provider = MfluxImageProvider(model="schnell", base_model=None, quantize=8)
    with pytest.raises(RuntimeError, match="huggingface-cli login"):
        provider.generate("a calm forest at dawn")


def test_generate_builds_cmd_for_third_party_repo(monkeypatch):
    captured = {}

    def run(cmd, **kwargs):
        captured["cmd"] = cmd
        # Write the expected output file so read_bytes succeeds.
        out = cmd[cmd.index("--output") + 1]
        from pathlib import Path

        Path(out).write_bytes(b"PNG")
        return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

    monkeypatch.setattr("vesnai.providers.flux.find_mflux_generate", lambda: "/bin/mflux-generate")
    monkeypatch.setattr("vesnai.providers.flux.subprocess.run", run)
    provider = MfluxImageProvider(
        model="dhairyashil/FLUX.1-schnell-mflux-4bit", base_model="schnell", quantize=None
    )
    image = provider.generate("a meadow", seed=0)
    cmd = captured["cmd"]
    assert "--base-model" in cmd and "schnell" in cmd
    # Pre-quantized mirror must not be re-quantized.
    assert "-q" not in cmd
    assert image.data == b"PNG"
