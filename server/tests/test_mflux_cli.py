"""Tests for locating the isolated mflux-generate CLI."""

from __future__ import annotations

import pytest

from vesnai.runtime import mflux_cli


def test_find_mflux_generate_uses_uv_tool_path(tmp_path, monkeypatch):
    fake_bin = tmp_path / "mflux-generate"
    fake_bin.write_text("#!/bin/sh\n")
    fake_bin.chmod(0o755)

    monkeypatch.setattr(mflux_cli.shutil, "which", lambda name: None)
    monkeypatch.setattr(
        mflux_cli,
        "prepend_uv_tool_bin_to_path",
        lambda: None,
    )
    monkeypatch.setattr(
        mflux_cli.Path,
        "home",
        classmethod(lambda cls: tmp_path),
    )
    tool_root = tmp_path / ".local" / "share" / "uv" / "tools"
    link = tool_root / "mflux" / "bin" / "mflux-generate"
    link.parent.mkdir(parents=True)
    link.write_bytes(fake_bin.read_bytes())
    link.chmod(0o755)

    def fake_run(cmd, **kwargs):
        assert cmd == ["uv", "tool", "dir"]
        return type("Proc", (), {"stdout": str(tool_root), "returncode": 0})()

    monkeypatch.setattr(mflux_cli.subprocess, "run", fake_run)
    assert mflux_cli.find_mflux_generate() == str(link)


def test_install_mflux_tool_treats_already_installed_as_success(monkeypatch):
    monkeypatch.setattr(mflux_cli.shutil, "which", lambda name: "uv")

    def fake_run(cmd, **kwargs):
        return type(
            "Proc",
            (),
            {"returncode": 1, "stdout": "", "stderr": "`mflux` is already installed\n"},
        )()

    monkeypatch.setattr(mflux_cli.subprocess, "run", fake_run)
    mflux_cli.install_mflux_tool()  # should not raise


def test_install_mflux_tool_raises_on_other_failures(monkeypatch):
    monkeypatch.setattr(mflux_cli.shutil, "which", lambda name: "uv")

    def fake_run(cmd, **kwargs):
        return type(
            "Proc",
            (),
            {"returncode": 1, "stdout": "", "stderr": "network error"},
        )()

    monkeypatch.setattr(mflux_cli.subprocess, "run", fake_run)
    with pytest.raises(RuntimeError, match="network error"):
        mflux_cli.install_mflux_tool()
