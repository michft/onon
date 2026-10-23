#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT
assert_source() {
  [[ "$(latest_osm_source "$fixture_dir")" = "$1" ]] || die "unexpected cached OSM source"
}

assert_source ""
touch -t 202601020000 "$fixture_dir/australia-new.osm.pbf"
assert_source ""
printf 'fixture' > "$fixture_dir/australia-old.osm.pbf"
touch -t 202601010000 "$fixture_dir/australia-old.osm.pbf"
assert_source "$fixture_dir/australia-old.osm.pbf"
mkdir "$fixture_dir/australia-directory.osm.pbf"
assert_source "$fixture_dir/australia-old.osm.pbf"
printf 'fixture' > "$fixture_dir/australia-new.osm.pbf"
assert_source "$fixture_dir/australia-new.osm.pbf"
touch "$fixture_dir/oci.marker"
file_is_fresh "$fixture_dir/oci.marker" 7 || die "empty OCI marker should remain fresh"
printf 'OSM cache selection: 6 checks passed\n'
