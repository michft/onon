#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_command node
require_command shasum
# Downloads are checksum-pinned; a cached preparation needs no network.
"$SCRIPT_DIR/download-protomaps-trial.sh"
trial_dir="${ONON_DATA_ROOT:-$REPO_ROOT/.local/onon}/protomaps-trial"
tool="$trial_dir/tools/pmtiles"
IFS=$'\t' read -r bundle_file bundle_hash source_build < <(node --input-type=module - \
  "$REPO_ROOT/apps/web/src/protomaps-regions.ts" "$trial_dir/provenance/bundle-area.geojson" <<'JS'
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const { nativeBundle, nativeBundleArea } = await import(pathToFileURL(process.argv[2]).href);
writeFileSync(process.argv[3], `${JSON.stringify(nativeBundleArea())}\n`);
console.log([nativeBundle.file, nativeBundle.sha256, nativeBundle.sourceBuild].join('\t'));
JS
)
archive="$trial_dir/$bundle_file"
valid() { [[ -f "$1" ]] && [[ "$(shasum -a 256 "$1" | awk '{print $1}')" = "$bundle_hash" ]]; }
if ! valid "$archive"; then
  log "extracting pinned iPhone bundle; dated upstream builds have limited retention"
  "$tool" extract "https://build.protomaps.com/$source_build.pmtiles" "$archive.part" \
    --region="$trial_dir/provenance/bundle-area.geojson" --minzoom=0 --maxzoom=15
  valid "$archive.part" || die "$bundle_file checksum mismatch"
  mv "$archive.part" "$archive"
fi
"$tool" verify "$archive"
"$tool" show "$archive" --metadata > "$trial_dir/provenance/bundle-metadata.json"
node "$SCRIPT_DIR/prepare-ios-map.mts" "$trial_dir"
