#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
for command in pnpm node curl; do require_command "$command"; done
data_root="${ONON_DATA_ROOT:-$REPO_ROOT/.local/onon}"
trial_dir="${ONON_PROTOMAPS_TRIAL_DIR:-$data_root/protomaps-trial}"
# Validate all advertised URLs, binds and output paths before building or starting anything.
public_origin="$(node "$SCRIPT_DIR/protomaps-http.mts" --check-config)"
tile_port="${ONON_PROTOMAPS_TILE_PORT:-8082}"
[[ -x "$trial_dir/tools/pmtiles" && -f "$trial_dir/sydney.pmtiles" && -f "$trial_dir/assets/vendor/basemaps.js" ]] || die "missing retained trial cache; run scripts/download-protomaps-trial.sh explicitly first"
cd "$REPO_ROOT"
ONON_DATA_ROOT="$data_root" pnpm --filter @onon/web exec vite build --config vite.protomaps.config.ts
node "$SCRIPT_DIR/protomaps-http.mts" --prepare
tile_pid=""
web_pid=""
cleanup() {
  [[ -z "$web_pid" ]] || kill "$web_pid" 2>/dev/null || true
  [[ -z "$tile_pid" ]] || kill "$tile_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM
"$trial_dir/tools/pmtiles" serve "$trial_dir" --interface=127.0.0.1 --port="$tile_port" \
  --public-url="$public_origin" --cors="$public_origin" &
tile_pid=$!
for attempt in {1..20}; do
  kill -0 "$tile_pid" 2>/dev/null || die "tile server stopped"
  if curl --fail --silent "http://127.0.0.1:$tile_port/sydney.json" >/dev/null; then break; fi
  sleep 0.2
done
kill -0 "$tile_pid" 2>/dev/null || die "tile server stopped"
curl --fail --silent "http://127.0.0.1:$tile_port/sydney.json" >/dev/null || die "tile server did not become ready"
node "$SCRIPT_DIR/protomaps-http.mts" &
web_pid=$!
log "open $public_origin/protomaps.html (Ctrl-C stops both servers)"
wait "$web_pid"
