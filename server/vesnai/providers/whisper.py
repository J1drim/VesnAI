"""whisper.cpp speech-to-text (MIT, local)."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path


def find_whisper_binary(explicit: str | None = None) -> str:
    if explicit and Path(explicit).exists():
        return explicit
    for name in ("whisper-cli", "whisper-cpp", "main"):
        path = shutil.which(name)
        if path:
            return path
    raise FileNotFoundError("whisper.cpp CLI not found (whisper-cli / whisper-cpp)")


class WhisperCppSTTProvider:
    def __init__(self, model_path: Path, *, binary: str | None = None) -> None:
        self.model_path = model_path
        self.binary = find_whisper_binary(binary)

    def transcribe(self, audio: bytes, *, language: str | None = None) -> str:
        with tempfile.TemporaryDirectory() as tmp:
            wav = Path(tmp) / "input.wav"
            out_prefix = Path(tmp) / "out"
            wav.write_bytes(audio)
            cmd = [
                self.binary,
                "-m",
                str(self.model_path),
                "-f",
                str(wav),
                "-otxt",
                "-of",
                str(out_prefix),
            ]
            if language:
                cmd.extend(["-l", language])
            subprocess.run(cmd, check=True, capture_output=True, text=True)
            txt = Path(f"{out_prefix}.txt")
            return txt.read_text(encoding="utf-8").strip() if txt.exists() else ""
