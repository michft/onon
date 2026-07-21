#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_command container
load_config

container system status || true
printf '\n%-22s %s\n' SERVICE STATUS
for name in "$POSTGRES_CONTAINER" "$TILESERVER_CONTAINER" "$WEB_CONTAINER"; do
  if container_running "$name"; then state=running; elif container_exists "$name"; then state=stopped; else state=missing; fi
  printf '%-22s %s\n' "$name" "$state"
done

if container_running "$POSTGRES_CONTAINER"; then
  container exec "$POSTGRES_CONTAINER" pg_isready --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" || true
fi
if container_running "$TILESERVER_CONTAINER"; then
  curl --fail --silent --show-error --max-time 3 "http://127.0.0.1:$ONON_TILESERVER_PORT/data/sydney.json" >/dev/null \
    && printf 'TileServer health: ok\n' || printf 'TileServer health: failed\n'
fi
if [[ -L "$MAPS_DIR/active.mbtiles" ]]; then
  printf 'Active map: %s\n' "$(readlink "$MAPS_DIR/active.mbtiles")"
else
  printf 'Active map: none\n'
fi
printf 'PostgreSQL volume: %s\n' "$POSTGRES_VOLUME"
du -sh "$ONON_DATA_ROOT" "$MAPS_DIR" "$BACKUPS_DIR" 2>/dev/null || true
