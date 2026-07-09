"""FLUX.1-schnell image generation via the mflux CLI (Apple Silicon / MLX).

mflux pins recent torch/numpy that conflict with Chatterbox TTS, so it is never
imported in-process: it is installed as an isolated CLI tool (``uv tool install
mflux``) and invoked via the ``mflux-generate`` subprocess. This keeps image
generation and the bilingual voice working from the same server.

Black Forest Labs gated ``black-forest-labs/FLUX.1-schnell`` on HuggingFace, so
pulling the official repo (the default here) needs an authenticated HF token
(``huggingface-cli login`` or ``HF_TOKEN``). For a no-auth setup, point
``VESNAI_FLUX_MODEL`` at an ungated, pre-quantized mflux mirror of the same
Apache-2.0 schnell weights (see ``docs/DEPLOYMENT.md``).
"""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from vesnai.providers.base import GeneratedImage
from vesnai.runtime.mflux_cli import find_mflux_generate

# Official Apache-2.0 schnell weights (gated; needs HF auth).
DEFAULT_FLUX_MODEL = "schnell"
# Ungated, pre-quantized mflux mirror of the same weights (no HF login needed).
UNGATED_FLUX_MIRROR = "dhairyashil/FLUX.1-schnell-mflux-4bit"


class MfluxImageProvider:
    def __init__(
        self,
        model: str = DEFAULT_FLUX_MODEL,
        *,
        base_model: str | None = None,
        quantize: int | None = 8,
        steps: int = 2,
    ) -> None:
        self.model = model
        # base_model is required by mflux when ``model`` is a third-party HF repo
        # or local path (it tells mflux which architecture/config to assume).
        self.base_model = base_model
        # Pre-quantized mirrors must NOT be re-quantized, so quantize defaults to
        # None; set it (e.g. 8) only when pointing at the full official repo.
        self.quantize = quantize
        self.steps = steps

    def generate(self, prompt: str, *, seed: int | None = None) -> GeneratedImage:
        binary = find_mflux_generate()
        if binary is None:
            raise RuntimeError(
                "mflux-generate CLI not found. Install it in its own environment with "
                "`uv tool install mflux` (kept isolated from Chatterbox's torch/numpy pins)."
            )
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "generated.png"
            cmd = [binary, "--model", self.model]
            if self.base_model:
                cmd.extend(["--base-model", self.base_model])
            cmd.extend(
                [
                    "--prompt",
                    prompt,
                    "--output",
                    str(out),
                    "--steps",
                    str(self.steps),
                ]
            )
            if self.quantize is not None:
                cmd.extend(["-q", str(self.quantize)])
            if seed is not None:
                cmd.extend(["--seed", str(seed)])
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode != 0:
                raise RuntimeError(_explain_failure(self.model, proc.stderr, proc.stdout))
            return GeneratedImage(data=out.read_bytes(), mime_type="image/png", prompt=prompt)


def _explain_failure(model: str, stderr: str, stdout: str) -> str:
    """Turn mflux's captured output into an actionable error message."""
    detail = (stderr or stdout or "").strip()
    lowered = detail.lower()
    if "gatedrepoerror" in lowered or "access to model" in lowered or "is restricted" in lowered:
        return (
            f"mflux could not download '{model}': the HuggingFace repo is gated. "
            "Authenticate with `huggingface-cli login` (or set HF_TOKEN) after "
            "accepting the model license at huggingface.co/black-forest-labs/FLUX.1-schnell. "
            f"For a no-auth setup instead, set VESNAI_FLUX_MODEL={UNGATED_FLUX_MIRROR}, "
            "VESNAI_FLUX_BASE_MODEL=schnell and leave VESNAI_FLUX_QUANTIZE unset.\n\n"
            f"{detail}"
        )
    return f"mflux-generate failed for model '{model}':\n{detail}"
