#!/usr/bin/env python3
"""Fail CI if direct Flutter deps drift too far behind pub.dev.

Parses direct dependencies from app/pubspec.yaml (skips SDK/path deps), runs
``dart pub outdated --json``, and fails when any direct package is two or more
major versions behind the latest stable release.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_DIR = ROOT / "app"
PUBSPEC = APP_DIR / "pubspec.yaml"

SKIP_DIRECT = frozenset({"flutter", "flutter_localizations", "intl"})


def parse_direct_deps(pubspec_text: str) -> dict[str, str]:
    """Return {name: constraint} for direct dependencies."""
    in_deps = False
    deps: dict[str, str] = {}
    for line in pubspec_text.splitlines():
        if re.match(r"^dependencies:\s*$", line):
            in_deps = True
            continue
        if in_deps and re.match(r"^[a-zA-Z_].*:", line) and not line.startswith(" "):
            break
        if not in_deps:
            continue
        match = re.match(r"^  ([a-zA-Z0-9_]+):\s*(.+)$", line)
        if not match:
            continue
        name, spec = match.group(1), match.group(2).strip()
        if spec.startswith("path:") or spec.startswith("sdk:"):
            continue
        if name in SKIP_DIRECT:
            continue
        deps[name] = spec
    return deps


def major(version: str) -> int:
    cleaned = version.lstrip("^v")
    return int(cleaned.split(".")[0])


def main() -> int:
    if not PUBSPEC.is_file():
        print(f"Missing {PUBSPEC}", file=sys.stderr)
        return 1

    direct = parse_direct_deps(PUBSPEC.read_text(encoding="utf-8"))
    out = subprocess.run(
        ["dart", "pub", "outdated", "--json"],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    data = json.loads(out.stdout)
    packages = {p["package"]: p for p in data.get("packages", [])}

    stale: list[str] = []
    for name in sorted(direct):
        info = packages.get(name)
        if info is None:
            continue
        latest = info.get("latest") or {}
        latest_ver = latest.get("version")
        if not latest_ver:
            continue
        current_ver = info.get("current") or {}
        current = current_ver.get("version") or direct[name].lstrip("^")
        if major(latest_ver) - major(current) >= 2:
            stale.append(f"{name}: current {current}, latest {latest_ver}")

    if stale:
        print("Direct Flutter dependencies are two or more major versions behind:")
        for line in stale:
            print(f"  - {line}")
        print("\nRun: cd app && flutter pub outdated && flutter pub upgrade --major-versions")
        return 1

    print(f"Direct dependency freshness check passed ({len(direct)} packages).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
