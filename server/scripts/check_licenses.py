"""Fail CI if any installed dependency uses a disallowed (non-commercial) license.

Uses ``pip-licenses`` JSON output. The allow-list reflects docs/LICENSING.md.
Disallowed examples: SSPL (MongoDB), GPL-3.0 (copyleft for linked code),
non-commercial RAIL variants.
"""

from __future__ import annotations

import json
import subprocess
import sys

ALLOWED_SUBSTRINGS = [
    "MIT",
    "BSD",
    "Apache",
    "Python Software Foundation",
    "PSF",
    "ISC",
    "Mozilla",
    "MPL",
    "LGPL",
    "Public Domain",
    "Unlicense",
    "HPND",
    "Zlib",
]

# Hard-deny regardless of anything else.
DENIED_SUBSTRINGS = ["SSPL", "Commons Clause", "Non-Commercial", "NonCommercial"]

# Packages allowed despite an unrecognized/UNKNOWN classifier (manually vetted).
KNOWN_EXCEPTIONS = {"vesnai-server"}


def main() -> int:
    out = subprocess.run(
        ["pip-licenses", "--format=json", "--with-system"],
        capture_output=True,
        text=True,
        check=True,
    )
    packages = json.loads(out.stdout)
    violations: list[str] = []
    for pkg in packages:
        name = pkg["Name"]
        lic = pkg["License"] or "UNKNOWN"
        if name in KNOWN_EXCEPTIONS:
            continue
        if any(d.lower() in lic.lower() for d in DENIED_SUBSTRINGS):
            violations.append(f"{name}: DENIED license {lic!r}")
            continue
        if not any(a.lower() in lic.lower() for a in ALLOWED_SUBSTRINGS):
            violations.append(f"{name}: unrecognized license {lic!r} (review required)")

    if violations:
        print("License compliance violations:")
        for v in violations:
            print(f"  - {v}")
        return 1
    print(f"License check passed for {len(packages)} packages.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
