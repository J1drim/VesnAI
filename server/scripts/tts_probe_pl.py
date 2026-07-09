"""Synthesize a Polish phrase with Chatterbox so you can A/B inference settings.

This loads the real Chatterbox model (needs the ``chatterbox`` extra installed)
and writes a WAV you can listen to, without starting the server. Sweep the
``--cfg-weight`` / ``--temperature`` / ``--exaggeration`` flags to find the
clearest Polish, then set the winning values as ``VESNAI_TTS_*`` env vars.

Example:

    uv run --extra chatterbox python scripts/tts_probe_pl.py \
        --text "Dzisiaj zaplanowałam trzy rzeczy dla ciebie." \
        --cfg-weight 0.5 --temperature 0.6
"""

from __future__ import annotations

import argparse
from pathlib import Path

from vesnai.ai.tts_text import prepare_for_tts
from vesnai.config import Settings
from vesnai.providers.chatterbox import ChatterboxTTSProvider

_DEFAULT_TEXT = "Cześć, jestem Wiosna. Dzisiaj zaplanowałam dla ciebie trzy rzeczy."


def main() -> None:
    settings = Settings()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--text", default=_DEFAULT_TEXT, help="Polish text to speak")
    parser.add_argument("--language", default="pl", help="Language id (pl|en)")
    parser.add_argument("--output", type=Path, default=Path("probe_pl.wav"))
    parser.add_argument("--reference-wav", type=Path, default=None)
    parser.add_argument("--cfg-weight", type=float, default=settings.tts_cfg_weight)
    parser.add_argument("--temperature", type=float, default=settings.tts_temperature)
    parser.add_argument(
        "--exaggeration", type=float, default=settings.tts_exaggeration
    )
    parser.add_argument(
        "--repetition-penalty", type=float, default=settings.tts_repetition_penalty
    )
    args = parser.parse_args()

    reference = args.reference_wav or settings.resolved_tts_reference_wav
    provider = ChatterboxTTSProvider(
        reference,
        exaggeration=args.exaggeration,
        cfg_weight=args.cfg_weight,
        temperature=args.temperature,
        repetition_penalty=args.repetition_penalty,
    )

    print(
        f"reference={reference}\n"
        f"cfg_weight={args.cfg_weight} temperature={args.temperature} "
        f"exaggeration={args.exaggeration} repetition_penalty={args.repetition_penalty}"
    )
    audio = provider.synthesize(prepare_for_tts(args.text), language=args.language)
    args.output.write_bytes(audio)
    print(f"wrote {len(audio)} bytes to {args.output.resolve()}")


if __name__ == "__main__":
    main()
