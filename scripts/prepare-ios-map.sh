#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_command node
# Downloads are checksum-pinned; a cached preparation needs no network.
"$SCRIPT_DIR/download-protomaps-trial.sh"
node "$SCRIPT_DIR/prepare-ios-map.mts" "${ONON_DATA_ROOT:-$REPO_ROOT/.local/onon}/protomaps-trial"
