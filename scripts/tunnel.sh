#!/usr/bin/env sh
# Expose the local VesnAI server through a public-HTTPS tunnel.
# See docs/REMOTE_ACCESS.md for the security model before using this.
set -eu

PORT=8443
TOOL="${1:-}"
[ $# -gt 0 ] && shift

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

usage() {
  cat <<EOF
Usage: ./scripts/tunnel.sh <pinggy|ngrok|cloudflared> [--port N]

Starts a public HTTPS tunnel to the local VesnAI server (default port 8443).
The server should run loopback-only without its own TLS:

  cd server && uv run vesnai serve --host 127.0.0.1 --port $PORT --no-tls

Read docs/REMOTE_ACCESS.md first (pairing security, rate limits, revocation).
EOF
}

case "$TOOL" in
  pinggy|ngrok|cloudflared) ;;
  *) usage; exit 2 ;;
esac

# Refuse to start a tunnel to nothing: check the server answers locally.
if command -v curl >/dev/null 2>&1; then
  if ! curl -fsk --max-time 3 "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1 \
     && ! curl -fsk --max-time 3 "https://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    echo "No server answering on 127.0.0.1:${PORT}." >&2
    echo "Start it first:  cd server && uv run vesnai serve --host 127.0.0.1 --port ${PORT} --no-tls" >&2
    exit 1
  fi
fi

cat <<EOF
Before exposing the server (docs/REMOTE_ACCESS.md):
  - pair your own devices first (\`uv run vesnai pair\` on this host)
  - all tunnel traffic shares one IP: rate limits are global behind the tunnel
  - revoke lost devices in the app (Settings -> Unpair)

Use the https:// URL printed below as the server URL in the app.
Press Ctrl-C to stop exposing the server.

EOF

case "$TOOL" in
  pinggy)
    exec ssh -p 443 -R0:127.0.0.1:"$PORT" qr@a.pinggy.io
    ;;
  ngrok)
    command -v ngrok >/dev/null 2>&1 || { echo "ngrok not installed (https://ngrok.com/download)" >&2; exit 1; }
    exec ngrok http "$PORT"
    ;;
  cloudflared)
    command -v cloudflared >/dev/null 2>&1 || { echo "cloudflared not installed (https://developers.cloudflare.com/cloudflare-tunnel/)" >&2; exit 1; }
    exec cloudflared tunnel --url "http://127.0.0.1:${PORT}"
    ;;
esac
