#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_command container
require_command shasum
load_config
container_running "$POSTGRES_CONTAINER" || die "PostgreSQL is not running"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="$BACKUPS_DIR/$stamp"
mkdir -p "$backup_dir"
log "dumping PostgreSQL to $backup_dir/database.dump"
container exec "$POSTGRES_CONTAINER" pg_dump \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --format=custom \
  >"$backup_dir/database.dump"

tar -czf "$backup_dir/infra-config.tgz" -C "$REPO_ROOT" \
  infra/config/images.env infra/tileserver infra/maps/sydney-service-area.geojson
{
  printf 'created_utc=%s\n' "$stamp"
  printf 'postgres_image=%s\n' "$POSTGRES_IMAGE"
  printf 'postgres_volume=%s\n' "$POSTGRES_VOLUME"
  printf 'tileserver_image=%s\n' "$TILESERVER_IMAGE"
  printf 'planetiler_image=%s\n' "$PLANETILER_IMAGE"
  if [[ -L "$MAPS_DIR/active.mbtiles" ]]; then printf 'active_map=%s\n' "$(readlink "$MAPS_DIR/active.mbtiles")"; fi
} >"$backup_dir/manifest.txt"
(cd "$backup_dir" && shasum -a 256 database.dump infra-config.tgz manifest.txt >SHA256SUMS)
log "backup complete: $backup_dir"
