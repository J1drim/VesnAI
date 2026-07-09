#!/usr/bin/env bash
#
# Backup and upgrade Qdrant / SearXNG sidecars started from server/docker-compose.yml.
#
#   ./scripts/compose-sidecars.sh backup              # tar qdrant-data volume
#   ./scripts/compose-sidecars.sh upgrade             # backup, pull, recreate sidecars
#   ./scripts/compose-sidecars.sh restore ARCHIVE.tgz # restore qdrant volume from backup
#   ./scripts/compose-sidecars.sh pin-digest IMAGE  # print digest after docker pull
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$ROOT/server"
COMPOSE_FILE="$SERVER_DIR/docker-compose.yml"
BACKUP_DIR="${VESNAI_COMPOSE_BACKUP_DIR:-$HOME/VesnAI/backups/compose}"

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

need_docker() {
  command -v docker >/dev/null 2>&1 || die "docker is required"
  docker info >/dev/null 2>&1 || die "Docker daemon is not running"
}

searxng_secret() {
  # Per-deploy secret, generated once into server/data (matches the server
  # bootstrap). Compose interpolation requires SEARXNG_SECRET to be set.
  local secret_file="$SERVER_DIR/data/searxng_secret"
  if [ -z "${SEARXNG_SECRET:-}" ]; then
    if [ ! -f "$secret_file" ]; then
      mkdir -p "$SERVER_DIR/data"
      if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32 > "$secret_file"
      else
        head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$secret_file"
      fi
      chmod 600 "$secret_file"
    fi
    SEARXNG_SECRET="$(cat "$secret_file")"
    export SEARXNG_SECRET
  fi
}

compose() {
  searxng_secret
  docker compose -f "$COMPOSE_FILE" "$@"
}

find_qdrant_volume() {
  local vol
  vol="$(docker volume ls -q -f "label=com.docker.compose.volume=qdrant-data" | head -1 || true)"
  if [ -z "$vol" ]; then
    # Volume may exist before labels were applied; fall back to common project names.
    for candidate in server_qdrant-data vesnai_qdrant-data second_brain_project_qdrant-data; do
      if docker volume inspect "$candidate" >/dev/null 2>&1; then
        echo "$candidate"
        return 0
      fi
    done
    die "Could not find qdrant-data Docker volume. Start sidecars once: cd server && docker compose up -d qdrant"
  fi
  echo "$vol"
}

cmd_backup() {
  need_docker
  local vol stamp archive
  vol="$(find_qdrant_volume)"
  stamp="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  archive="$BACKUP_DIR/qdrant-${stamp}.tar.gz"
  info "Backing up Docker volume ${C_BOLD}$vol${C_RESET} → $archive"
  docker run --rm \
    -v "${vol}:/source:ro" \
    -v "${BACKUP_DIR}:/backup" \
    alpine:3.20 \
    tar czf "/backup/qdrant-${stamp}.tar.gz" -C /source .
  ok "Qdrant volume backup written ($(du -h "$archive" | awk '{print $1}'))"
  warn "Notes and attachments live in your OKF knowledge dir — also run POST /v1/backup (encrypted) before major upgrades."
}

cmd_restore() {
  need_docker
  local archive="${1:-}"
  [ -n "$archive" ] || die "Usage: $0 restore ARCHIVE.tar.gz"
  [ -f "$archive" ] || die "Archive not found: $archive"
  archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
  local vol
  vol="$(find_qdrant_volume)"
  warn "This replaces all data in volume $vol from $archive"
  read -r -p "Continue? [y/N] " confirm
  case "$confirm" in
    y|Y|yes|YES) ;;
    *) die "Aborted." ;;
  esac
  info "Stopping Qdrant..."
  compose stop qdrant >/dev/null 2>&1 || true
  info "Restoring volume ${vol}..."
  docker run --rm \
    -v "${vol}:/data" \
    -v "$(dirname "$archive"):/backup:ro" \
    alpine:3.20 \
    sh -c 'rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true; tar xzf "/backup/$(basename "$1")" -C /data' _ "$archive"
  info "Starting Qdrant..."
  compose up -d qdrant
  ok "Restore complete. Restart the VesnAI server if it is running."
}

wait_sidecar_health() {
  local deadline=$((SECONDS + 120))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if compose ps qdrant searxng 2>/dev/null | grep -q "(healthy)"; then
      if compose ps qdrant 2>/dev/null | grep -q "(healthy)" && compose ps searxng 2>/dev/null | grep -q "(healthy)"; then
        return 0
      fi
    fi
    sleep 2
  done
  warn "Timed out waiting for healthy sidecars — check: docker compose -f $COMPOSE_FILE ps"
  return 1
}

cmd_upgrade() {
  need_docker
  info "Step 1/4 — backup Qdrant volume"
  cmd_backup
  info "Step 2/4 — pull pinned images (qdrant, searxng)"
  compose pull qdrant searxng
  info "Step 3/4 — recreate sidecars"
  compose up -d qdrant searxng
  info "Step 4/4 — wait for health checks"
  if wait_sidecar_health; then
    ok "Sidecars upgraded and healthy"
  else
    warn "Upgrade finished but health checks did not pass. Restore with: $0 restore <latest-backup>"
    exit 1
  fi
  ok "If semantic search looks empty, restart the VesnAI server — it reindexes notes into Qdrant on startup."
}

cmd_pin_digest() {
  need_docker
  local image="${1:-}"
  [ -n "$image" ] || die "Usage: $0 pin-digest IMAGE (e.g. qdrant/qdrant:v1.13.2)"
  info "Pulling ${image}..."
  docker pull "$image"
  local digest
  digest="$(docker inspect --format '{{index .RepoDigests 0}}' "$image" 2>/dev/null || true)"
  [ -n "$digest" ] || die "Could not read digest for $image"
  ok "$digest"
  echo
  echo "Update server/docker-compose.yml and server/compose-images.lock.yaml, then run:"
  echo "  ./scripts/compose-sidecars.sh backup"
  echo "  ./scripts/compose-sidecars.sh upgrade"
}

usage() {
  cat <<EOF
${C_BOLD}VesnAI Docker sidecar maintenance${C_RESET}

Usage: ./scripts/compose-sidecars.sh <command>

Commands:
  backup                 Tar the qdrant-data volume to ${BACKUP_DIR}
  upgrade                Backup, pull pinned images, recreate qdrant + searxng
  restore ARCHIVE.tgz    Restore qdrant-data from a backup tarball
  pin-digest IMAGE       Pull IMAGE and print its digest for compose lock updates

Environment:
  VESNAI_COMPOSE_BACKUP_DIR   Backup output directory (default: ~/VesnAI/backups/compose)

See docs/DEPLOYMENT.md § "Upgrading pinned sidecar images".
EOF
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    backup) cmd_backup ;;
    upgrade) cmd_upgrade ;;
    restore) cmd_restore "${1:-}" ;;
    pin-digest) cmd_pin_digest "${1:-}" ;;
    ""|-h|--help|help) usage ;;
    *) warn "Unknown command: $cmd"; echo; usage; exit 1 ;;
  esac
}

main "$@"
