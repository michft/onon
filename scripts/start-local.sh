#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_command container
load_config
ensure_container_system
ensure_network
start_postgres
start_tileserver
start_web
log "local services started"
