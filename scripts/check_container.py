"""Smoke-test a built image using an isolated container and disposable volume.

Usage: python3 scripts/check_container.py vesnai/upgrade-smoke:20260905
Does not start Compose or mount any existing host data/volume.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
import urllib.request
import uuid


def docker(*args: str) -> str:
    return subprocess.check_output(["docker", *args], text=True).strip()


def main() -> None:
    image = sys.argv[1]
    name = f"vesnai-upgrade-smoke-{uuid.uuid4().hex}"
    created = False
    try:
        docker(
            "run", "-d", "--name", name, "-p", "127.0.0.1::8443",
            "-e", "VESNAI_OFFLINE_ONLY=true", image,
            "serve", "--host", "0.0.0.0", "--port", "8443", "--no-tls",
            "--knowledge-dir", "/data/knowledge", "--data-dir", "/data/state",
        )
        created = True

        def ready() -> None:
            port = docker("port", name, "8443/tcp").split(":")[-1]
            for _ in range(60):
                try:
                    with urllib.request.urlopen(
                        f"http://127.0.0.1:{port}/readyz", timeout=2
                    ) as response:
                        if json.load(response) == {"status": "ready"}:
                            return
                except (OSError, ValueError):
                    pass
                time.sleep(1)
            raise RuntimeError("Isolated server never became ready")

        ready()
        docker("exec", name, "python", "-c", """
import importlib.metadata as metadata
import tomllib
from pathlib import Path
lock = tomllib.loads(Path('/app/uv.lock').read_text())
allowed = {(p['name'].replace('_', '-').lower(), p['version']) for p in lock['package']}
for dist in metadata.distributions():
    assert (dist.name.replace('_', '-').lower(), dist.version) in allowed, dist.name
Path('/data/knowledge/container-smoke.md').write_text('Persistent smoke-test data\\n')
""")
        docker("restart", name)
        ready()
        docker("exec", name, "python", "-c", """
from pathlib import Path
assert Path('/data/knowledge/container-smoke.md').read_text() == 'Persistent smoke-test data\\n'
""")
        print("PASS: locked runtime, readiness, restart and isolated data persistence")
    finally:
        if created:
            # Exact UUID-named test container and its own anonymous volume only.
            subprocess.run(["docker", "rm", "-f", "-v", name], check=True)


if __name__ == "__main__":
    main()
