#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
for command in pnpm python3 curl; do require_command "$command"; done
data_root="${ONON_DATA_ROOT:-$REPO_ROOT/.local/onon}"
[[ "$data_root" = /* && "$data_root" != / ]] || die "ONON_DATA_ROOT must be an absolute non-root path"
trial_dir="$data_root/protomaps-trial"
[[ -x "$trial_dir/tools/pmtiles" && -f "$trial_dir/sydney.pmtiles" && -f "$trial_dir/assets/light.json" ]] || die "run scripts/download-protomaps-trial.sh first"
cd "$REPO_ROOT"
ONON_DATA_ROOT="$data_root" pnpm --filter @onon/web exec vite build --config vite.protomaps.config.ts
cp "$trial_dir/assets/light.json" "$trial_dir/site/"
cp -R "$trial_dir/assets/fonts" "$trial_dir/assets/sprites" "$trial_dir/site/"
cp "$trial_dir/assets/vendor/basemaps-LICENSE.md" "$trial_dir/site/"
tile_pid=""
web_pid=""
cleanup() {
  [[ -z "$web_pid" ]] || kill "$web_pid" 2>/dev/null || true
  [[ -z "$tile_pid" ]] || kill "$tile_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM
"$trial_dir/tools/pmtiles" serve "$trial_dir" --interface=127.0.0.1 --port=8082 \
  --public-url=http://127.0.0.1:8082 --cors=http://127.0.0.1:8083,http://localhost:8083 &
tile_pid=$!
for attempt in {1..20}; do
  kill -0 "$tile_pid" 2>/dev/null || die "tile server stopped"
  if curl --fail --silent http://127.0.0.1:8082/sydney.json >/dev/null; then break; fi
  sleep 0.2
done
curl --fail --silent http://127.0.0.1:8082/sydney.json >/dev/null || die "tile server did not become ready"
python3 -m http.server 8083 --bind 127.0.0.1 --directory "$trial_dir/site" &
web_pid=$!
log "open http://127.0.0.1:8083/protomaps.html (Ctrl-C stops both servers)"
wait "$web_pid"
