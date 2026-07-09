"""Git-versioned on-disk OKF bundle store.

The bundle directory is the single source of truth. Every mutation is committed
to git (history) and appended to the reserved ``log.md``. ``index.md`` is
regenerated as a directory listing. All paths are validated to stay inside the
bundle root (path-traversal protection).
"""

from __future__ import annotations

import io
import subprocess
import zipfile
from pathlib import Path

from vesnai.observability import get_logger
from vesnai.okf.model import RESERVED_FILENAMES, Concept
from vesnai.okf.parse import dump_concept, parse_concept
from vesnai.providers.base import Clock, SystemClock

log = get_logger("vesnai.okf.bundle")

CONCEPTS_GLOB = "**/*.md"


class BundleError(Exception):
    pass


class PathTraversalError(BundleError):
    pass


class BundleStore:
    def __init__(self, root: Path, clock: Clock | None = None, *, use_git: bool = True) -> None:
        self.root = Path(root).resolve()
        self.clock = clock or SystemClock()
        self.use_git = use_git
        self._observers: list = []
        self.root.mkdir(parents=True, exist_ok=True)
        if self.use_git:
            self._ensure_git()

    def add_observer(self, callback) -> None:
        """Register ``callback(rel_path: str, deleted: bool)`` fired on each change."""
        self._observers.append(callback)

    def _notify(self, rel_path: str, deleted: bool) -> None:
        for cb in self._observers:
            try:
                cb(rel_path, deleted)
            except Exception:  # noqa: BLE001
                log.warning("observer_error", path=rel_path)

    # ------------------------------------------------------------------ #
    # Path safety
    # ------------------------------------------------------------------ #
    def _resolve(self, rel_path: str) -> Path:
        if rel_path.startswith("/") or rel_path.startswith("\\"):
            raise PathTraversalError(f"absolute paths are not allowed: {rel_path!r}")
        candidate = (self.root / rel_path).resolve()
        try:
            candidate.relative_to(self.root)
        except ValueError as exc:
            raise PathTraversalError(f"path escapes bundle root: {rel_path!r}") from exc
        return candidate

    def rel(self, path: Path) -> str:
        return path.resolve().relative_to(self.root).as_posix()

    # ------------------------------------------------------------------ #
    # Concepts
    # ------------------------------------------------------------------ #
    def write_concept(self, rel_path: str, concept: Concept, *, message: str | None = None) -> None:
        if not rel_path.endswith(".md"):
            raise BundleError("concept path must end with .md")
        target = self._resolve(rel_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(dump_concept(concept), encoding="utf-8")
        self._append_log(f"write {rel_path}")
        self._regenerate_index()
        self._commit(message or f"write {rel_path}")
        self._notify(rel_path, False)

    def read_concept(self, rel_path: str) -> Concept:
        target = self._resolve(rel_path)
        if not target.exists():
            raise BundleError(f"concept not found: {rel_path}")
        return parse_concept(target.read_text(encoding="utf-8"))

    def delete_concept(self, rel_path: str, *, message: str | None = None) -> None:
        target = self._resolve(rel_path)
        if target.exists():
            target.unlink()
            self._append_log(f"delete {rel_path}")
            self._regenerate_index()
            self._commit(message or f"delete {rel_path}")
            self._notify(rel_path, True)

    def exists(self, rel_path: str) -> bool:
        return self._resolve(rel_path).exists()

    def list_paths(self) -> list[str]:
        paths: list[str] = []
        for p in sorted(self.root.glob(CONCEPTS_GLOB)):
            if ".git" in p.parts:
                continue
            rel = self.rel(p)
            if Path(rel).name in RESERVED_FILENAMES:
                continue
            paths.append(rel)
        return paths

    def list_concepts(self) -> dict[str, Concept]:
        out: dict[str, Concept] = {}
        for rel in self.list_paths():
            try:
                out[rel] = self.read_concept(rel)
            except Exception as exc:  # noqa: BLE001 - tolerate one bad file
                log.warning("skip_unparseable_concept", path=rel, error=str(exc))
        return out

    # ------------------------------------------------------------------ #
    # Attachments
    # ------------------------------------------------------------------ #
    def save_attachment(self, rel_path: str, data: bytes, *, message: str | None = None) -> str:
        target = self._resolve(rel_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        self._append_log(f"attach {rel_path} ({len(data)} bytes)")
        self._commit(message or f"attach {rel_path}")
        return rel_path

    def read_attachment(self, rel_path: str) -> bytes:
        return self._resolve(rel_path).read_bytes()

    def delete_attachment(self, rel_path: str, *, message: str | None = None) -> None:
        target = self._resolve(rel_path)
        if target.exists() and target.is_file():
            target.unlink()
            self._append_log(f"delete attachment {rel_path}")
            self._commit(message or f"delete attachment {rel_path}")

    def list_attachment_paths(self) -> list[str]:
        att_dir = self.root / "attachments"
        if not att_dir.is_dir():
            return []
        return [
            self.rel(p)
            for p in sorted(att_dir.rglob("*"))
            if p.is_file()
        ]

    # ------------------------------------------------------------------ #
    # Reserved files
    # ------------------------------------------------------------------ #
    def _append_log(self, line: str) -> None:
        log_path = self.root / "log.md"
        ts = self.clock.now().isoformat()
        header = "# Log\n\n" if not log_path.exists() else ""
        with log_path.open("a", encoding="utf-8") as fh:
            fh.write(f"{header}- {ts} {line}\n")

    def _regenerate_index(self) -> None:
        lines = ["# Index", ""]
        for rel in self.list_paths():
            try:
                concept = self.read_concept(rel)
                title = concept.title or rel
            except Exception:  # noqa: BLE001
                title = rel
            lines.append(f"- [{title}]({rel})")
        (self.root / "index.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    # ------------------------------------------------------------------ #
    # Git
    # ------------------------------------------------------------------ #
    def _git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", "-C", str(self.root), *args],
            capture_output=True,
            text=True,
            check=False,
        )

    def _ensure_git(self) -> None:
        if not (self.root / ".git").exists():
            self._git("init", "-q")
            self._git("config", "user.email", "vesnai@localhost")
            self._git("config", "user.name", "VesnAI")
            self._git("config", "commit.gpgsign", "false")

    def _commit(self, message: str) -> None:
        if not self.use_git:
            return
        self._git("add", "-A")
        result = self._git("commit", "-q", "-m", message)
        if result.returncode != 0 and "nothing to commit" not in (result.stdout + result.stderr):
            log.warning("git_commit_failed", message=message, stderr=result.stderr)

    def history(self, limit: int = 50) -> list[str]:
        result = self._git("log", f"-{limit}", "--pretty=%H %s")
        if result.returncode != 0:
            return []
        return [line for line in result.stdout.splitlines() if line]

    # ------------------------------------------------------------------ #
    # Backup / restore
    # ------------------------------------------------------------------ #
    def export_zip(self) -> bytes:
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for p in sorted(self.root.rglob("*")):
                if ".git" in p.parts or not p.is_file():
                    continue
                zf.write(p, arcname=self.rel(p))
        return buf.getvalue()

    def import_zip(self, data: bytes, *, message: str = "restore from backup") -> None:
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            for name in zf.namelist():
                if name.endswith("/"):
                    continue
                target = self._resolve(name)  # path-traversal safe
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(zf.read(name))
        self._commit(message)
