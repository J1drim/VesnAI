#!/usr/bin/env bash
#
# VesnAI launcher for macOS / Linux.
#
# Detects your OS, runs the local server, and installs / updates / runs the
# Flutter client. On Windows use scripts/vesnai.ps1 instead.
#
#   ./scripts/vesnai.sh setup-https            # install mkcert + trusted dev certificate
#   ./scripts/vesnai.sh server                 # run the local server (HTTPS by default)
#   ./scripts/vesnai.sh client install         # build + install the desktop app
#   ./scripts/vesnai.sh client install --device android  # release APK + mkcert CA
#   ./scripts/vesnai.sh client install --device ios      # release on iPhone/iPad
#   ./scripts/vesnai.sh client update          # rebuild + replace an install
#   ./scripts/vesnai.sh client run             # hot-run the app on a device
#   ./scripts/vesnai.sh doctor                 # check prerequisites
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$ROOT/server"
APP_DIR="$ROOT/app"
TLS_CERT="$SERVER_DIR/localhost.pem"
TLS_KEY="$SERVER_DIR/localhost-key.pem"

# --------------------------------------------------------------------------- #
# Pretty logging
# --------------------------------------------------------------------------- #
if [ -t 1 ]; then
  C_RESET="\033[0m"; C_BLUE="\033[34m"; C_GREEN="\033[32m"
  C_YELLOW="\033[33m"; C_RED="\033[31m"; C_BOLD="\033[1m"
else
  C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""
fi
info()  { printf "${C_BLUE}==>${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GREEN}✓${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}!${C_RESET} %s\n" "$*" >&2; }
die()   { printf "${C_RED}✗ %s${C_RESET}\n" "$*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# OS detection
# --------------------------------------------------------------------------- #
detect_os() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin*) echo macos ;;
    Linux*)  echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}
OS="$(detect_os)"

have() { command -v "$1" >/dev/null 2>&1; }

# uv tool install puts binaries in ~/.local/bin; many shells don't load that until
# `uv tool update-shell` has been run. Keep the current script (and server child)
# working immediately, and persist the snippet for future terminals.
ensure_uv_tool_path() {
  local local_bin="${HOME}/.local/bin"
  [ -d "$local_bin" ] || return 0
  case ":${PATH}:" in
    *":${local_bin}:"*) ;;
    *) export PATH="${local_bin}:${PATH:-}" ;;
  esac
}

persist_uv_tool_path() {
  have uv || return 0
  # Idempotent: writes ~/.zshenv / ~/.bashrc snippet if needed.
  uv tool update-shell >/dev/null 2>&1 || true
  ensure_uv_tool_path
}

# --------------------------------------------------------------------------- #
# Prerequisite checks
# --------------------------------------------------------------------------- #
need_uv() {
  if ! have uv; then
    warn "uv (Python package manager) is not installed."
    case "$OS" in
      macos) echo "    Install with: brew install uv  (or: curl -LsSf https://astral.sh/uv/install.sh | sh)" ;;
      linux) echo "    Install with: curl -LsSf https://astral.sh/uv/install.sh | sh" ;;
    esac
    die "uv is required to run the server."
  fi
  ensure_uv_tool_path
}

need_flutter() {
  have flutter || die "flutter is not installed. Get it from https://docs.flutter.dev/get-started/install"
}

# AGP 9+ built-in Kotlin: patch plugins that still apply kotlin-android unconditionally.
patch_flutter_android_plugins() {
  local script="$APP_DIR/tool/patch_built_in_kotlin_plugins.sh"
  if [ -x "$script" ]; then
    "$script"
  elif [ -f "$script" ]; then
    bash "$script"
  fi
}

# Sync Python deps. Online mode needs the optional ``ai`` extra (ollama, qdrant, …).
sync_server_deps() {
  local offline="$1"
  # A stale VIRTUAL_ENV from another project confuses uv; use the server's .venv.
  unset VIRTUAL_ENV
  if [ "$offline" = true ]; then
    info "Syncing server dependencies (uv sync)…"
    (cd "$SERVER_DIR" && uv sync)
  else
    # Online stack: LLM/embeddings/search/STT in-process; TTS is a separate sidecar
    # the user registers in Settings → Voice service.
    info "Syncing server dependencies (uv sync --extra ai)…"
    (cd "$SERVER_DIR" && uv sync --extra ai)
    # FLUX image gen lives in its own isolated env (its torch/numpy pins clash
    # with Chatterbox). Install the mflux-generate CLI tool (idempotent).
    info "Installing FLUX image CLI (uv tool install mflux)…"
    uv tool install mflux >/dev/null 2>&1 || true
    persist_uv_tool_path
    if ! have mflux-generate; then
      warn "mflux-generate not found after install; image generation will be unavailable"
    fi
  fi
}

check_ollama_runtime() {
  if ! have ollama; then
    warn "Ollama is not installed — online mode needs it: https://ollama.com"
    return 1
  fi
  if ! ollama list >/dev/null 2>&1; then
    warn "Ollama is installed but not running. Start the Ollama app or run: ollama serve"
    return 1
  fi
  return 0
}

# --------------------------------------------------------------------------- #
# HTTPS (mkcert)
# --------------------------------------------------------------------------- #
install_mkcert() {
  info "Installing mkcert (locally-trusted TLS certificates)…"
  case "$OS" in
    macos)
      if have brew; then
        brew install mkcert
      else
        die "Homebrew is required to install mkcert on macOS. Install from https://brew.sh"
      fi
      ;;
    linux)
      if have apt-get; then
        sudo apt-get update -qq
        sudo apt-get install -y libnss3-tools
        if have apt-get && apt-cache show mkcert >/dev/null 2>&1; then
          sudo apt-get install -y mkcert
        elif have brew; then
          brew install mkcert
        else
          local ver="v1.4.4" arch="amd64"
          case "$(uname -m)" in
            aarch64|arm64) arch="arm64" ;;
          esac
          local dest="$HOME/.local/bin/mkcert"
          mkdir -p "$(dirname "$dest")"
          curl -fsSL "https://github.com/FiloSottile/mkcert/releases/download/${ver}/mkcert-${ver}-linux-${arch}" \
            -o "$dest"
          chmod +x "$dest"
          export PATH="$HOME/.local/bin:$PATH"
        fi
      elif have brew; then
        brew install mkcert
      else
        die "Install mkcert manually: https://github.com/FiloSottile/mkcert#installation"
      fi
      ;;
    *)
      die "Automatic mkcert install is not supported on $OS. See https://github.com/FiloSottile/mkcert"
      ;;
  esac
  have mkcert || die "mkcert install finished but the mkcert command is still missing."
  ok "mkcert installed."
}

# Hostnames/IPs covered by the dev certificate (LAN discovery + local clients).
tls_sans() {
  local host short lan
  host="$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)"
  short="$(hostname -s 2>/dev/null || true)"
  lan="$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || true)"
  printf '%s\n' localhost 127.0.0.1 ::1
  [ -n "$host" ] && [ "$host" != localhost ] && printf '%s\n' "$host"
  [ -n "$short" ] && [ "$short" != localhost ] && [ "$short" != "$host" ] && printf '%s\n' "$short"
  [ -n "$lan" ] && printf '%s\n' "$lan"
}

generate_tls_certs() {
  have mkcert || install_mkcert
  info "Installing the local CA into your system trust store (mkcert -install)…"
  if ! mkcert -install 2>/dev/null; then
    warn "Could not install the mkcert CA (sudo/password may be required)."
    warn "Run this once in Terminal so browsers trust HTTPS: mkcert -install"
  fi
  info "Generating TLS certificate for VesnAI…"
  mkdir -p "$SERVER_DIR"
  local -a mkcert_args=()
  while IFS= read -r san; do
    [ -n "$san" ] && mkcert_args+=("$san")
  done < <(tls_sans)
  (cd "$SERVER_DIR" && mkcert -cert-file localhost.pem -key-file localhost-key.pem "${mkcert_args[@]}")
  [ -f "$TLS_CERT" ] && [ -f "$TLS_KEY" ] || die "Certificate generation failed."
  ok "Certificate: $TLS_CERT"
  ok "Private key: $TLS_KEY"
  ok "Trusted by browsers on this machine (mkcert CA)."
  bundle_mobile_mkcert_ca
}

mkcert_root_ca() {
  have mkcert || return 1
  local caroot
  caroot="$(mkcert -CAROOT 2>/dev/null || true)"
  [ -n "$caroot" ] && [ -f "$caroot/rootCA.pem" ] || return 1
  echo "$caroot/rootCA.pem"
}

# Embed the mkcert root CA so dev app builds trust the dev HTTPS server.
# Only used together with --dart-define=TRUST_DEV_MKCERT_CA=true (see
# lib/data/http_client_factory.dart); release/store builds ignore the asset.
bundle_mobile_mkcert_ca() {
  local ca
  ca="$(mkcert_root_ca)" || die "mkcert root CA not found. Run: ./scripts/vesnai.sh setup-https"
  local flutter_dest="$APP_DIR/assets/certs/mkcert_root_ca.pem"
  mkdir -p "$(dirname "$flutter_dest")"
  cp "$ca" "$flutter_dest"
  ok "Bundled mkcert root CA (assets/certs for app TLS in dev builds)."
}

need_adb() {
  if ! have adb; then
    die "adb not found. Install Android SDK platform-tools and ensure adb is on PATH."
  fi
}

pick_adb_device() {
  local serial="${ANDROID_SERIAL:-}"
  if [ -n "$serial" ]; then
    echo "$serial"
    return 0
  fi
  adb devices 2>/dev/null | awk '/\tdevice$/{print $1; exit}'
}

install_mkcert_ca_on_android_device() {
  local ca device
  ca="$(mkcert_root_ca)" || return 0
  device="$(pick_adb_device)"
  [ -n "$device" ] || return 0
  info "Copying mkcert root CA to the device (optional, for system-wide trust)…"
  adb -s "$device" push "$ca" /sdcard/Download/mkcert-rootCA.pem >/dev/null
  ok "Optional: on the phone open Settings → Security → Install certificate → CA certificate."
  ok "The VesnAI dev build already trusts this CA (bundled asset); installing it"
  ok "as a user CA additionally covers WebView/native traffic in debug builds."
}

ios_mkcert_ca_instructions() {
  local ca
  ca="$(mkcert_root_ca)" || return 0
  warn "Install the mkcert root CA on your iPhone/iPad (one-time, for HTTPS to your server):"
  echo "  1. AirDrop or email the file to the device:"
  echo "     $ca"
  echo "  2. Settings → General → VPN & Device Management → install the profile"
  echo "  3. Settings → General → About → Certificate Trust Settings → enable full trust"
  if [ "$OS" = macos ]; then
    info "Opening the CA in Finder…"
    open -R "$ca" 2>/dev/null || true
  fi
}

verb_capitalize() {
  local word="$1"
  case "$word" in
    install) echo "Installing" ;;
    update)  echo "Updating" ;;
    *) echo "$word" ;;
  esac
}

ensure_tls_certs() {
  if [ -f "$TLS_CERT" ] && [ -f "$TLS_KEY" ]; then
    return 0
  fi
  generate_tls_certs
}

cmd_setup_https() {
  generate_tls_certs
  echo
  ok "HTTPS is ready. Start the server with: ./scripts/vesnai.sh server"
  echo "   Then open https://localhost:8443/docs"
}

# --------------------------------------------------------------------------- #
# server
# --------------------------------------------------------------------------- #
cmd_server() {
  local port=8443 knowledge_dir="$SERVER_DIR/knowledge" data_dir="$SERVER_DIR/data"
  local offline=true tls=auto host=0.0.0.0
  while [ $# -gt 0 ]; do
    case "$1" in
      --port) port="$2"; shift 2 ;;
      --host) host="$2"; shift 2 ;;
      --knowledge-dir) knowledge_dir="$2"; shift 2 ;;
      --data-dir) data_dir="$2"; shift 2 ;;
      --online) offline=false; shift ;;
      --offline) offline=true; shift ;;
      --tls) tls=on; shift ;;
      --no-tls) tls=off; shift ;;
      *) die "Unknown server option: $1" ;;
    esac
  done

  need_uv
  sync_server_deps "$offline"

  if [ "$offline" = false ]; then
    check_ollama_runtime || true
    info "Online mode — starting full local stack (Docker, Ollama, models, Qdrant, SearXNG)…"
  fi

  local serve_args=(--knowledge-dir "$knowledge_dir" --data-dir "$data_dir" --port "$port" --host "$host")
  [ "$offline" = true ] && serve_args+=(--offline) || serve_args+=(--no-offline)

  # Resolve a LAN IP so phones/tablets get a reachable URL (not localhost).
  local lan_ip
  lan_ip="$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || true)"
  [ -n "$lan_ip" ] || lan_ip="$host"

  local scheme=https
  if [ "$tls" != off ]; then
    ensure_tls_certs
    serve_args+=(--tls --cert "$TLS_CERT" --key "$TLS_KEY")
    ok "HTTPS enabled — server at https://localhost:$port (docs: /docs)"
  else
    scheme=http
    serve_args+=(--no-tls)
    warn "TLS disabled — server at http://localhost:$port"
  fi

  ok "Pair phones/tablets at: $scheme://$lan_ip:$port  (use this URL in the app, not localhost)"
  [ "$offline" = true ] && info "Offline mode (deterministic fake AI providers)." \
                        || info "Online mode — bootstrap runs inside the server (may take several minutes on first start)."
  info "Press Ctrl+C to stop."
  unset VIRTUAL_ENV
  (cd "$SERVER_DIR" && exec uv run vesnai serve "${serve_args[@]}")
}

# --------------------------------------------------------------------------- #
# pair
# --------------------------------------------------------------------------- #
cmd_pair() {
  local data_dir="$SERVER_DIR/data" url="" config=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --data-dir) data_dir="$2"; shift 2 ;;
      --url) url="$2"; shift 2 ;;
      --config) config="$2"; shift 2 ;;
      *) die "Unknown pair option: $1" ;;
    esac
  done
  need_uv
  unset VIRTUAL_ENV
  local args=(--data-dir "$data_dir")
  [ -n "$url" ] && args+=(--url "$url")
  [ -n "$config" ] && args+=(--config "$config")
  (cd "$SERVER_DIR" && exec uv run vesnai pair "${args[@]}")
}

# --------------------------------------------------------------------------- #
# client
# --------------------------------------------------------------------------- #

# Default desktop build target for the current OS.
default_desktop_target() {
  case "$OS" in
    macos) echo macos ;;
    linux) echo linux ;;
    *) echo "" ;;
  esac
}

ensure_platform() {
  # Flutter desktop folders may not exist yet (e.g. linux). Scaffold on demand.
  local target="$1"
  if [ ! -d "$APP_DIR/$target" ]; then
    info "Adding missing '$target' platform to the Flutter project…"
    (cd "$APP_DIR" && flutter create --platforms="$target" .)
  fi
}

# Launcher builds are dev builds for your own devices: opt in to trusting the
# dev mkcert CA (release/store builds keep the safe default of public CAs only).
DEV_CA_DEFINE="--dart-define=TRUST_DEV_MKCERT_CA=true"

client_build_and_deploy() {
  local target="$1" verb="$2"   # verb = install | update (just for messaging)
  local verb_msg; verb_msg="$(verb_capitalize "$verb")"
  need_flutter
  info "Fetching Flutter packages (flutter pub get)…"
  (cd "$APP_DIR" && flutter pub get)
  patch_flutter_android_plugins

  case "$target" in
    macos)
      ensure_platform macos
      info "Building macOS release…"
      (cd "$APP_DIR" && flutter build macos --release "$DEV_CA_DEFINE")
      local rel="$APP_DIR/build/macos/Build/Products/Release"
      local bundle; bundle="$(ls -d "$rel"/*.app 2>/dev/null | head -1 || true)"
      [ -n "$bundle" ] || die "Build succeeded but no .app was found in $rel"
      local dest="/Applications"; [ -w "$dest" ] || dest="$HOME/Applications"
      mkdir -p "$dest"
      local name; name="$(basename "$bundle")"
      info "$verb_msg $name → $dest"
      rm -rf "$dest/$name"
      ditto "$bundle" "$dest/$name"
      ok "$name is ${verb}ed in $dest. Launch it from Finder or Spotlight."
      ;;
    linux)
      ensure_platform linux
      info "Building Linux release…"
      (cd "$APP_DIR" && flutter build linux --release "$DEV_CA_DEFINE")
      local bundle; bundle="$(ls -d "$APP_DIR"/build/linux/*/release/bundle 2>/dev/null | head -1 || true)"
      [ -n "$bundle" ] || die "Build succeeded but no bundle was found under build/linux."
      local dest="$HOME/.local/share/vesnai"
      local bindir="$HOME/.local/bin"
      info "$verb_msg to $dest"
      rm -rf "$dest"; mkdir -p "$dest" "$bindir"
      cp -a "$bundle/." "$dest/"
      local exe; exe="$(find "$dest" -maxdepth 1 -type f -perm -u+x ! -name '*.so*' | head -1 || true)"
      if [ -n "$exe" ]; then
        ln -sf "$exe" "$bindir/vesnai-app"
        ok "Installed. Run with: vesnai-app  (ensure $bindir is on your PATH)"
      else
        ok "Installed to $dest."
      fi
      ;;
    android)
      ensure_platform android
      ensure_tls_certs
      bundle_mobile_mkcert_ca
      info "Building Android release APK…"
      (cd "$APP_DIR" && flutter build apk --release "$DEV_CA_DEFINE")
      local apk="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
      [ -f "$apk" ] || die "Build succeeded but APK not found at $apk"
      need_adb
      local device; device="$(pick_adb_device)"
      [ -n "$device" ] || die "No Android device or emulator connected (check: adb devices)."
      info "$verb_msg release APK on ${device}…"
      adb -s "$device" install -r "$apk"
      install_mkcert_ca_on_android_device
      ok "VesnAI ${verb}ed on Android ($device)."
      ;;
    ios)
      [ "$OS" = macos ] || die "iOS builds require macOS with Xcode installed."
      ensure_platform ios
      ensure_tls_certs
      bundle_mobile_mkcert_ca
      info "Building iOS release…"
      (cd "$APP_DIR" && flutter build ios --release "$DEV_CA_DEFINE")
      info "$verb_msg on connected iOS device (requires code signing in Xcode)…"
      if ! (cd "$APP_DIR" && flutter install --release); then
        warn "flutter install failed — open ios/Runner.xcworkspace in Xcode,"
        warn "select your Team under Signing & Capabilities, then re-run:"
        warn "  ./scripts/vesnai.sh client install --device ios"
        die "iOS install did not complete."
      fi
      ios_mkcert_ca_instructions
      ok "VesnAI ${verb}ed on iOS."
      ;;
    *)
      die "Unknown install target: $target (use macos, linux, android, or ios)."
      ;;
  esac
}

cmd_client() {
  local action="run" target=""
  while [ $# -gt 0 ]; do
    case "$1" in
      run|install|update) action="$1"; shift ;;
      --device|--target) target="$2"; shift 2 ;;
      *) die "Unknown client option: $1" ;;
    esac
  done
  [ -n "$target" ] || target="$(default_desktop_target)"

  case "$action" in
    install) client_build_and_deploy "$target" install ;;
    update)  client_build_and_deploy "$target" update ;;
    run)
      need_flutter
      info "Fetching Flutter packages (flutter pub get)…"
      (cd "$APP_DIR" && flutter pub get)
      patch_flutter_android_plugins
      if [ "$target" = android ] || [ "$target" = ios ]; then
        ensure_tls_certs
        bundle_mobile_mkcert_ca
      fi
      if [ -n "$target" ]; then
        info "Launching the client on '$target'…"
        (cd "$APP_DIR" && exec flutter run "$DEV_CA_DEFINE" -d "$target")
      else
        info "Launching the client (Flutter will pick a device)…"
        (cd "$APP_DIR" && exec flutter run "$DEV_CA_DEFINE")
      fi
      ;;
  esac
}

# --------------------------------------------------------------------------- #
# doctor
# --------------------------------------------------------------------------- #
cmd_doctor() {
  info "Detected OS: ${C_BOLD}$OS${C_RESET}"
  printf "\n%s\n" "Prerequisites:"
  if have uv; then ok "uv         $(uv --version 2>/dev/null)"; else warn "uv         missing (needed for the server)"; fi
  if have uv; then
    ensure_uv_tool_path
    if have mflux-generate; then
      ok "mflux      $(command -v mflux-generate)"
    else
      warn "mflux      mflux-generate missing (run: ./scripts/vesnai.sh server --online)"
    fi
  fi
  if have flutter; then ok "flutter    $(flutter --version 2>/dev/null | head -1)"; else warn "flutter    missing (needed for the client)"; fi
  if have mkcert; then ok "mkcert     $(mkcert -CAROOT 2>/dev/null | sed 's|^|CA: |')"; else warn "mkcert     missing (run: ./scripts/vesnai.sh setup-https)"; fi
  if [ -f "$TLS_CERT" ]; then ok "tls cert   $TLS_CERT"; else warn "tls cert   missing (run: ./scripts/vesnai.sh setup-https)"; fi
  if have ollama; then ok "ollama     present (local models)"; else warn "ollama     missing (optional, for --online local models)"; fi
  if have adb; then ok "adb        $(adb version 2>/dev/null | head -1)"; else warn "adb        missing (needed for Android install)"; fi
  printf "\n%s\n" "Paths:"
  echo "  server: $SERVER_DIR"
  echo "  app:    $APP_DIR"
}

# --------------------------------------------------------------------------- #
# usage
# --------------------------------------------------------------------------- #
usage() {
  cat <<EOF
${C_BOLD}VesnAI launcher${C_RESET} (OS: $OS)

Usage: ./scripts/vesnai.sh <command> [options]

Commands:
  setup-https             Install mkcert (if needed) and generate a trusted dev certificate
  server [options]        Run the local server over HTTPS (syncs deps first)
    --port N              Port (default 8443)
    --knowledge-dir DIR   OKF bundle directory (default server/knowledge)
    --data-dir DIR        State/index directory (default server/data)
    --online | --offline  Use local models (Ollama) vs. offline (default offline)
    --no-tls              Disable HTTPS (default: HTTPS with mkcert)

  client <run|install|update> [--device <macos|linux|windows|android|ios>]
    run                   Hot-run the app on a device/emulator (default)
    install               Build a release and install (desktop, Android APK, or iOS)
    update                Rebuild and replace an existing install

  compose <backup|upgrade|restore|pin-digest>  Docker sidecar backup / digest upgrade (see docs/DEPLOYMENT.md)

  Voice output (TTS) is not bundled: register any HTTP TTS service or an
  OpenAI-compatible speech API in the app (Settings -> Voice service).
  See docs/TTS_SIDECAR.md.

  doctor                  Check installed prerequisites
  pair [options]          Mint a pairing code (run on the server host)
    --data-dir DIR        State directory (default server/data)
    --url URL             Server base URL (default https://127.0.0.1:8443)
    --config PATH         Path to vesnai.yaml

Examples:
  ./scripts/vesnai.sh setup-https
  ./scripts/vesnai.sh server --online
  ./scripts/vesnai.sh pair
  ./scripts/vesnai.sh client install
  ./scripts/vesnai.sh client install --device android
  ./scripts/vesnai.sh client install --device ios
  ./scripts/vesnai.sh client run --device android
EOF
}

main() {
  [ "$OS" = unknown ] && warn "Unrecognized OS; assuming a POSIX shell."
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    server) cmd_server "$@" ;;
    compose) exec "$SCRIPT_DIR/compose-sidecars.sh" "$@" ;;
    setup-https) cmd_setup_https "$@" ;;
    client) cmd_client "$@" ;;
    doctor) cmd_doctor "$@" ;;
    pair) cmd_pair "$@" ;;
    ""|-h|--help|help) usage ;;
    *) warn "Unknown command: $cmd"; echo; usage; exit 1 ;;
  esac
}
main "$@"
