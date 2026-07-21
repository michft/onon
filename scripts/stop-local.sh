#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_command container
load_config

for name in "$WEB_CONTAINER" "$TILESERVER_CONTAINER" "$POSTGRES_CONTAINER"; do
  if container_running "$name"; then
    log "stopping $name"
    container stop --time 30 "$name"
  fi
done
log "services stopped; containers and persistent data retained"
