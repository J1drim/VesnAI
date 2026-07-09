#!/usr/bin/env bash
# Remove legacy kotlin-android from Flutter Android plugins (AGP 9+ built-in Kotlin).
# Targets exact versions from pubspec.lock. Re-run after `flutter pub get`.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$APP_DIR/pubspec.lock"
PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache/hosted/pub.dev}"
MARKER="vesnai-built-in-kotlin-patch"
PLUGINS=(file_picker share_plus mobile_scanner nsd_android speech_to_text quill_native_bridge_android)

python3 - "$LOCK" "$PUB_CACHE" "$MARKER" "${PLUGINS[@]}" <<'PY'
import pathlib
import re
import sys

lock_path = pathlib.Path(sys.argv[1])
pub_cache = pathlib.Path(sys.argv[2])
marker = sys.argv[3]
plugin_names = sys.argv[4:]

lock_text = lock_path.read_text()
versions: dict[str, str] = {}
current: str | None = None
for line in lock_text.splitlines():
    m = re.match(r"  (\w[\w_]*):", line)
    if m:
        current = m.group(1)
        continue
    if current and line.strip().startswith("version:"):
        versions[current] = line.split('"')[1]
        current = None

KOTLIN_OPTIONS = [
    """    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
""",
    """    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11
    }
""",
    """    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
""",
    """    kotlinOptions {
        jvmTarget = 17
    }
""",
    """    kotlinOptions {
        jvmTarget = '17'
    }
""",
    """    kotlinOptions {
        jvmTarget = '11'
    }
""",
]

def patch(path: pathlib.Path) -> bool:
    text = path.read_text()
    if marker in text and "kotlin-android" not in text and "org.jetbrains.kotlin.android" not in text:
        return False
    text = re.sub(r"\n// vesnai-built-in-kotlin-patch.*", "", text)
    text = text.replace("apply plugin: 'kotlin-android'\n", "")
    text = text.replace('apply plugin: "kotlin-android"\n', "")
    text = text.replace("apply plugin: 'org.jetbrains.kotlin.android'\n", "")
    for block in KOTLIN_OPTIONS:
        text = text.replace(block, "")
    text = text.replace(
        """    compileOptions {
        sourceCompatibility JavaVersion.VERSION_11
        targetCompatibility JavaVersion.VERSION_11
    }
""",
        """    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
""",
    )
    text = text.replace(
        """    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
""",
        """    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
""",
    )
    if marker not in text:
        text = text.replace(
            "apply plugin: 'com.android.library'\n",
            f"apply plugin: 'com.android.library'\n// {marker}: AGP 9+ built-in Kotlin\n",
            1,
        )
    path.write_text(text)
    return True

for name in plugin_names:
    version = versions.get(name)
    if not version:
        print(f"skip {name} (not in pubspec.lock)", file=sys.stderr)
        continue
    plugin_dir = pub_cache / f"{name}-{version}"
    gradle = plugin_dir / "android" / "build.gradle"
    if not gradle.exists():
        print(f"skip {name}-{version} (no android/build.gradle)", file=sys.stderr)
        continue
    if patch(gradle):
        print(f"patched {gradle}")
    else:
        print(f"unchanged {name}-{version}")
PY
