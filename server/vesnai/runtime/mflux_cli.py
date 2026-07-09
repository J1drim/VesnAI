"""Locate the isolated ``mflux-generate`` CLI installed via ``uv tool install``.

uv links tool binaries into ``~/.local/bin``, which is often missing from PATH
when the server is started from an IDE or a shell that has not run
``uv tool update-shell``.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


def prepend_uv_tool_bin_to_path() -> None:
    """Ensure the default uv tool symlink dir is on PATH for this process."""
    local_bin = Path.home() / ".local" / "bin"
    if not local_bin.is_dir():
        return
    prefix = str(local_bin)
    path = os.environ.get("PATH", "")
    if prefix not in path.split(os.pathsep):
        os.environ["PATH"] = f"{prefix}{os.pathsep}{path}"


def find_mflux_generate() -> str | None:
    """Return an executable ``mflux-generate`` path, or ``None`` if not found."""
    prepend_uv_tool_bin_to_path()
    found = shutil.which("mflux-generate")
    if found:
        return found

    candidates: list[Path] = [
        Path.home() / ".local" / "bin" / "mflux-generate",
        Path.home() / ".local" / "share" / "uv" / "tools" / "mflux" / "bin" / "mflux-generate",
    ]
    if shutil.which("uv"):
        try:
            proc = subprocess.run(
                ["uv", "tool", "dir"],
                capture_output=True,
                text=True,
                check=True,
            )
            tool_root = Path(proc.stdout.strip())
            candidates.append(tool_root / "mflux" / "bin" / "mflux-generate")
        except (OSError, subprocess.CalledProcessError):
            pass

    for path in candidates:
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    return None


def install_mflux_tool() -> None:
    """Install or refresh the mflux uv tool (no-op if already present)."""
    if shutil.which("uv") is None:
        raise RuntimeError("uv is unavailable")
    proc = subprocess.run(["uv", "tool", "install", "mflux"], capture_output=True, text=True)
    if proc.returncode == 0:
        return
    combined = f"{proc.stdout}\n{proc.stderr}".lower()
    if "already installed" in combined:
        return
    raise RuntimeError(proc.stderr or proc.stdout or "`uv tool install mflux` failed")
