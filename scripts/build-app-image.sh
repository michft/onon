#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

require_command container
load_config
ensure_container_system

[[ -n "$ONON_WEB_IMAGE" ]] || die "ONON_WEB_IMAGE must name the local Web/API image"
log "building $ONON_WEB_IMAGE for linux/arm64"
container build --platform linux/arm64 --tag "$ONON_WEB_IMAGE" \
  --file "$INFRA_DIR/app/Containerfile" "$REPO_ROOT"
if container_exists "$WEB_CONTAINER"; then
  log "removing prior Web/API container so next start uses the new image"
  replace_runtime_container "$WEB_CONTAINER"
fi
log "built $ONON_WEB_IMAGE"
