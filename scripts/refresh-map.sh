#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_command container
require_command curl
require_command sqlite3
require_command shasum
load_config
ensure_container_system

version="$(date -u +%Y%m%dT%H%M%SZ)"
candidate_dir="$MAP_CANDIDATES_DIR/$version"
candidate="$candidate_dir/candidate.mbtiles"
source_pbf="${ONON_SOURCE_PBF:-}"
final="$MAP_VERSIONS_DIR/sydney-$version.mbtiles"
smoke_name="onon-map-smoke-$version"

mkdir -p "$candidate_dir" "$MAP_SOURCE_DIR" "$MAP_VERSIONS_DIR"
cleanup() {
  if container_running "$smoke_name"; then container stop --time 10 "$smoke_name" >/dev/null 2>&1 || true; fi
  if container_exists "$smoke_name"; then container delete "$smoke_name" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT INT TERM

if [[ -n "$source_pbf" ]]; then
  [[ "$source_pbf" = "$MAP_SOURCE_DIR/"* && -s "$source_pbf" ]] \
    || die "ONON_SOURCE_PBF must be an existing non-empty file under $MAP_SOURCE_DIR"
  log "using cached OSM input: $source_pbf"
else
  latest_source=""
  for cached_source in "$MAP_SOURCE_DIR"/australia-*.osm.pbf; do
    [[ -f "$cached_source" ]] || continue
    if [[ -z "$latest_source" || "$cached_source" -nt "$latest_source" ]]; then latest_source="$cached_source"; fi
  done
  if [[ -n "$latest_source" ]] && file_is_fresh "$latest_source"; then
    source_pbf="$latest_source"
    log "using OSM input newer than $REMOTE_DOWNLOAD_MAX_AGE_DAYS days: $source_pbf"
  else
    source_pbf="$MAP_SOURCE_DIR/australia-$version.osm.pbf"
    log "downloading OSM input; cache is missing or at least $REMOTE_DOWNLOAD_MAX_AGE_DAYS days old"
    curl --fail --location --retry 3 --continue-at - --progress-bar "$ONON_OSM_PBF_URL" --output "$source_pbf.part"
    mv "$source_pbf.part" "$source_pbf"
  fi
fi

log "building candidate $version for bounds $ONON_SERVICE_BOUNDS"
container run --rm --name "onon-planetiler-$version" \
  --memory "${ONON_PLANETILER_CONTAINER_MEMORY:-10G}" --cpus "${ONON_PLANETILER_CPUS:-4}" \
  --env "JAVA_TOOL_OPTIONS=-Xmx${ONON_PLANETILER_MEMORY:-8G}" \
  --mount "type=bind,source=$ONON_DATA_ROOT,target=/data" \
  "$PLANETILER_IMAGE" --download \
  --osm-path="/data/maps/source/$(basename "$source_pbf")" \
  --output="/data/maps/candidates/$version/candidate.mbtiles" \
  --bounds="$ONON_SERVICE_BOUNDS"

[[ -s "$candidate" ]] || die "Planetiler did not produce $candidate"
[[ "$(sqlite3 "$candidate" 'PRAGMA quick_check;')" = ok ]] || die "candidate MBTiles failed SQLite quick_check"
tile_count="$(sqlite3 "$candidate" 'SELECT count(*) FROM tiles;')"
[[ "$tile_count" =~ ^[1-9][0-9]*$ ]] || die "candidate contains no tiles"

log "smoke-testing candidate through TileServer GL ($tile_count tiles)"
container run --rm --detach --name "$smoke_name" \
  --publish "127.0.0.1:${ONON_MAP_SMOKE_PORT:-18081}:8080" \
  --mount "type=bind,source=$candidate_dir,target=/data/mbtiles,readonly" \
  --mount "type=bind,source=$INFRA_DIR/tileserver,target=/data/config,readonly" \
  "$TILESERVER_IMAGE" --config /data/config/smoke-config.json
smoke_ok=false
for _attempt in {1..30}; do
  if curl --fail --silent --max-time 2 "http://127.0.0.1:${ONON_MAP_SMOKE_PORT:-18081}/data/candidate.json" >/dev/null; then
    smoke_ok=true
    break
  fi
  sleep 1
done
[[ "$smoke_ok" = true ]] || { container logs -n 100 "$smoke_name" >&2 || true; die "candidate TileServer smoke test failed"; }
cleanup

mv "$candidate" "$final"
source_sha256="$(shasum -a 256 "$source_pbf" | awk '{print $1}')"
archive_sha256="$(shasum -a 256 "$final" | awk '{print $1}')"
{
  printf 'version=%s\n' "$version"
  printf 'source=%s\n' "$source_pbf"
  printf 'source_url=%s\n' "$ONON_OSM_PBF_URL"
  printf 'source_sha256=%s\n' "$source_sha256"
  printf 'archive_sha256=%s\n' "$archive_sha256"
  printf 'bounds=%s\n' "$ONON_SERVICE_BOUNDS"
  printf 'tile_count=%s\n' "$tile_count"
} >"$final.manifest.txt"
old_target=""
[[ -L "$MAPS_DIR/active.mbtiles" ]] && old_target="$(readlink "$MAPS_DIR/active.mbtiles")"
ln -s "versions/$(basename "$final")" "$MAPS_DIR/.active-$version"
mv -f "$MAPS_DIR/.active-$version" "$MAPS_DIR/active.mbtiles"

if container_exists "$TILESERVER_CONTAINER"; then
  log "recreating TileServer GL to activate $version"
  replace_runtime_container "$TILESERVER_CONTAINER"
  if ! start_tileserver; then
    warn "activation failed; restoring previous map"
    if [[ -n "$old_target" ]]; then
      ln -s "$old_target" "$MAPS_DIR/.active-rollback"
      mv -f "$MAPS_DIR/.active-rollback" "$MAPS_DIR/active.mbtiles"
      start_tileserver || true
    else
      unlink "$MAPS_DIR/active.mbtiles"
    fi
    exit 1
  fi
fi

log "activated $(basename "$final"); older archives and source files retained"
