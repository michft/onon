#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$REPO_ROOT/infra"
CONFIG_DIR="$INFRA_DIR/config"
LOCAL_ENV="$CONFIG_DIR/local.env"
IMAGES_ENV="$CONFIG_DIR/images.env"

log() { printf '[onon] %s\n' "$*"; }
warn() { printf '[onon] warning: %s\n' "$*" >&2; }
die() { printf '[onon] error: %s\n' "$*" >&2; exit 1; }

require_command() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

require_node24() {
  require_command node
  node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)' ||
    die "Node.js 24 or later is required for Protomaps TypeScript scripts"
}

load_config() {
  [[ -f "$IMAGES_ENV" ]] || die "missing $IMAGES_ENV"
  [[ -f "$LOCAL_ENV" ]] || die "missing $LOCAL_ENV; run scripts/bootstrap-local.sh first"
  # shellcheck disable=SC1090
  source "$IMAGES_ENV"
  # shellcheck disable=SC1090
  source "$LOCAL_ENV"

  : "${POSTGRES_IMAGE:?}" "${TILESERVER_IMAGE:?}" "${PLANETILER_IMAGE:?}"
  : "${POSTGRES_USER:?}" "${POSTGRES_DB:?}" "${POSTGRES_PASSWORD:?}"
  : "${ADMIN_TOKEN:?}" "${ONON_PUBLIC_HOST:?}"
  : "${ONON_NETWORK:?}" "${ONON_TILESERVER_PORT:?}" "${ONON_WEB_PORT:?}"
  [[ "$POSTGRES_USER" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "unsafe POSTGRES_USER"
  [[ "$POSTGRES_DB" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "unsafe POSTGRES_DB"

  ONON_DATA_ROOT="${ONON_DATA_ROOT:-$REPO_ROOT/.local/onon}"
  ONON_PAIRING_HOST="${ONON_PAIRING_HOST:-$ONON_PUBLIC_HOST}"
  [[ "$ONON_DATA_ROOT" = /* && "$ONON_DATA_ROOT" != / ]] || die "ONON_DATA_ROOT must be an absolute non-root path"
  POSTGRES_VOLUME="${ONON_POSTGRES_VOLUME:-onon-postgres-data}"
  POSTGRES_VOLUME_SIZE="${ONON_POSTGRES_VOLUME_SIZE:-20G}"
  TILESERVER_MEMORY="${ONON_TILESERVER_MEMORY:-2G}"
  REMOTE_DOWNLOAD_MAX_AGE_DAYS="${ONON_REMOTE_DOWNLOAD_MAX_AGE_DAYS:-7}"
  [[ "$POSTGRES_VOLUME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "unsafe ONON_POSTGRES_VOLUME"
  [[ "$POSTGRES_VOLUME_SIZE" =~ ^[1-9][0-9]*[KMGTP]?$ ]] || die "unsafe ONON_POSTGRES_VOLUME_SIZE"
  [[ "$TILESERVER_MEMORY" =~ ^[1-9][0-9]*[KMGTP]?$ ]] || die "unsafe ONON_TILESERVER_MEMORY"
  [[ "$REMOTE_DOWNLOAD_MAX_AGE_DAYS" =~ ^[0-9]+$ ]] || die "ONON_REMOTE_DOWNLOAD_MAX_AGE_DAYS must be a whole number"
  MAPS_DIR="$ONON_DATA_ROOT/maps"
  MAP_VERSIONS_DIR="$MAPS_DIR/versions"
  MAP_CANDIDATES_DIR="$MAPS_DIR/candidates"
  MAP_SOURCE_DIR="$MAPS_DIR/source"
  STYLE_ASSETS_DIR="$ONON_DATA_ROOT/style-assets"
  EXPORTS_DIR="$ONON_DATA_ROOT/exports"
  BACKUPS_DIR="$ONON_DATA_ROOT/backups"
  REMOTE_CACHE_DIR="$ONON_DATA_ROOT/remote-cache"

  POSTGRES_CONTAINER=onon-postgres
  TILESERVER_CONTAINER=onon-tileserver
  WEB_CONTAINER=onon-web-api
}

file_mtime_epoch() {
  local path="$1"
  stat -f '%m' "$path" 2>/dev/null || stat -c '%Y' "$path"
}

file_is_fresh() {
  local path="$1" max_age_days="${2:-$REMOTE_DOWNLOAD_MAX_AGE_DAYS}"
  local now modified max_age_seconds
  [[ -f "$path" && "$max_age_days" =~ ^[0-9]+$ ]] || return 1
  modified="$(file_mtime_epoch "$path")" || return 1
  now="$(date +%s)"
  max_age_seconds=$((max_age_days * 86400))
  (( max_age_seconds > 0 && now - modified < max_age_seconds ))
}

latest_osm_source() {
  local directory="$1" cached_source latest_source=""
  for cached_source in "$directory"/australia-*.osm.pbf; do
    [[ -f "$cached_source" && -s "$cached_source" ]] || continue
    if [[ -z "$latest_source" || "$cached_source" -nt "$latest_source" ]]; then latest_source="$cached_source"; fi
  done
  printf '%s' "$latest_source"
}

container_exists() { container list --all --quiet 2>/dev/null | grep -Fxq -- "$1"; }
container_running() { container list --quiet 2>/dev/null | grep -Fxq -- "$1"; }

ensure_container_system() {
  if ! container system status >/dev/null 2>&1; then
    log "starting Apple container services"
    container system start
  fi
}

ensure_network() {
  if ! container network list --quiet | grep -Fxq -- "$ONON_NETWORK"; then
    log "creating isolated application network $ONON_NETWORK"
    container network create "$ONON_NETWORK"
  fi
}

ensure_postgres_volume() {
  if ! container volume list --quiet | grep -Fxq -- "$POSTGRES_VOLUME"; then
    log "creating persistent PostgreSQL volume $POSTGRES_VOLUME ($POSTGRES_VOLUME_SIZE)"
    container volume create --label onon.service=postgres -s "$POSTGRES_VOLUME_SIZE" "$POSTGRES_VOLUME"
  fi
}

container_ipv4() {
  local name="$1" address
  address="$(container inspect "$name" | awk -F'"' '/"ipv4Address"/ { split($4, parts, "/"); print parts[1]; exit }')"
  [[ "$address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "could not resolve IPv4 address for $name"
  printf '%s\n' "$address"
}

wait_for_postgres() {
  local attempt
  for attempt in {1..60}; do
    if container exec "$POSTGRES_CONTAINER" pg_isready --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  container logs -n 50 "$POSTGRES_CONTAINER" >&2 || true
  die "PostgreSQL did not become ready"
}

start_postgres() {
  ensure_postgres_volume
  if container_running "$POSTGRES_CONTAINER"; then return 0; fi
  if container_exists "$POSTGRES_CONTAINER"; then
    log "starting existing PostgreSQL container"
    container start "$POSTGRES_CONTAINER"
  else
    log "creating PostgreSQL container"
    container run --detach --name "$POSTGRES_CONTAINER" --network "$ONON_NETWORK" \
      --env-file "$LOCAL_ENV" \
      --env "PGDATA=/var/lib/postgresql/data/pgdata" \
      --mount "type=volume,source=$POSTGRES_VOLUME,target=/var/lib/postgresql/data" \
      --shm-size 256M "$POSTGRES_IMAGE"
  fi
  wait_for_postgres
}

start_tileserver() {
  [[ -L "$MAPS_DIR/active.mbtiles" ]] || die "no active map; run scripts/refresh-map.sh"
  if container_running "$TILESERVER_CONTAINER"; then return 0; fi
  if container_exists "$TILESERVER_CONTAINER"; then
    log "starting existing TileServer GL container"
    container start "$TILESERVER_CONTAINER"
  else
    log "creating TileServer GL container"
    container run --detach --name "$TILESERVER_CONTAINER" --network "$ONON_NETWORK" \
      --memory "$TILESERVER_MEMORY" \
      --publish "${ONON_BIND_ADDRESS:-0.0.0.0}:${ONON_TILESERVER_PORT}:8080" \
      --env "TILESERVER_GL_ALLOWED_HOSTS=${ONON_TILESERVER_ALLOWED_HOSTS:-localhost,127.0.0.1},${ONON_PUBLIC_HOST},${ONON_PAIRING_HOST}" \
      --mount "type=bind,source=$INFRA_DIR/tileserver,target=/data/config,readonly" \
      --mount "type=bind,source=$MAPS_DIR,target=/data/mbtiles,readonly" \
      --mount "type=bind,source=$STYLE_ASSETS_DIR/fonts,target=/data/fonts,readonly" \
      --mount "type=bind,source=$STYLE_ASSETS_DIR/sprites,target=/data/sprites,readonly" \
      "$TILESERVER_IMAGE" --config /data/config/config.json
  fi
}

start_web() {
  local map_version="not-built" postgres_address tileserver_address
  [[ -n "${ONON_WEB_IMAGE:-}" ]] || { warn "ONON_WEB_IMAGE is empty; Web/API not started"; return 0; }
  if container_running "$WEB_CONTAINER"; then return 0; fi
  if container_exists "$WEB_CONTAINER"; then
    log "recreating Web/API container with current service addresses"
    container delete "$WEB_CONTAINER"
  else
    log "creating Web/API container"
  fi
  if [[ -L "$MAPS_DIR/active.mbtiles" ]]; then
    map_version="$(basename "$(readlink "$MAPS_DIR/active.mbtiles")" .mbtiles)"
  fi
  postgres_address="$(container_ipv4 "$POSTGRES_CONTAINER")"
  tileserver_address="$(container_ipv4 "$TILESERVER_CONTAINER")"
  container run --detach --name "$WEB_CONTAINER" --network "$ONON_NETWORK" \
    --publish "${ONON_BIND_ADDRESS:-0.0.0.0}:${ONON_WEB_PORT}:3000" \
    --env "DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${postgres_address}:5432/${POSTGRES_DB}" \
    --env "ADMIN_TOKEN=$ADMIN_TOKEN" \
    --env "PUBLIC_BASE_URL=http://${ONON_PAIRING_HOST}:${ONON_WEB_PORT}" \
    --env "TILESERVER_URL=http://${tileserver_address}:8080" \
    --env "PUBLIC_TILESERVER_URL=http://${ONON_PAIRING_HOST}:${ONON_TILESERVER_PORT}" \
    --env "CORS_ORIGIN=http://${ONON_PUBLIC_HOST}:${ONON_WEB_PORT}" \
    --env "MAP_VERSION=$map_version" \
    --mount "type=bind,source=$EXPORTS_DIR,target=/app/exports" \
    "$ONON_WEB_IMAGE"
}

replace_runtime_container() {
  local name="$1"
  if container_running "$name"; then container stop --time 20 "$name"; fi
  if container_exists "$name"; then container delete "$name"; fi
}
