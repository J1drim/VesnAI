#!/usr/bin/env python3
"""Write voice registration to the server data dir (no HTTP pairing required)."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from vesnai.secrets import SecretStore
from vesnai.voice_registration import (
    DEFAULT_SECRET_NAME,
    PROVIDER_OPENAI,
    PROVIDER_SIDECAR,
    VoiceRegistration,
    VoiceRegistrationStore,
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument(
        "--provider",
        choices=(PROVIDER_SIDECAR, PROVIDER_OPENAI),
        default=PROVIDER_SIDECAR,
    )
    parser.add_argument("--url", default="")
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--model", default="")
    parser.add_argument(
        "--voices-json",
        default="",
        help='JSON object of per-language voice IDs, e.g. {"pl":"my-voice-pl","en":"my-voice-en"}',
    )
    args = parser.parse_args()

    if args.voices_json:
        voices = json.loads(args.voices_json)
    elif args.provider == PROVIDER_OPENAI:
        voices = {"pl": "nova", "en": "nova"}
    else:
        parser.error("--voices-json is required for the sidecar provider")

    reg = VoiceRegistration(
        provider=args.provider,
        url=args.url,
        secret_name=DEFAULT_SECRET_NAME,
        voices=voices,
        model=args.model or None,
    )
    data_dir = args.data_dir
    data_dir.mkdir(parents=True, exist_ok=True)
    VoiceRegistrationStore(data_dir).save(reg)
    SecretStore(data_dir).set(DEFAULT_SECRET_NAME, args.api_key)
    print(f"voice registration written for provider={reg.provider} url={reg.resolved_url()}")


if __name__ == "__main__":
    main()
