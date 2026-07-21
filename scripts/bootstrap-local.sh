#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

require_command container
require_command openssl
require_command curl
require_command tar

if [[ ! -f "$LOCAL_ENV" ]]; then
  password="$(openssl rand -hex 32)"
  admin_token="$(openssl rand -hex 32)"
  local_host="$(scutil --get LocalHostName 2>/dev/null || hostname -s).local"
  sed \
    -e "s/generated-by-bootstrap/$password/" \
    -e "s/generated-admin-token/$admin_token/" \
    -e "s/generated-local-host/$local_host/" \
    "$CONFIG_DIR/local.env.example" >"$LOCAL_ENV"
  chmod 600 "$LOCAL_ENV"
  log "created $LOCAL_ENV"
fi

load_config
ensure_container_system
mkdir -p "$MAP_VERSIONS_DIR" "$MAP_CANDIDATES_DIR" "$MAP_SOURCE_DIR" \
  "$STYLE_ASSETS_DIR/fonts" "$STYLE_ASSETS_DIR/sprites" "$EXPORTS_DIR" "$BACKUPS_DIR"
ensure_network
ensure_postgres_volume

for image in "$POSTGRES_IMAGE" "$TILESERVER_IMAGE" "$PLANETILER_IMAGE"; do
  log "pulling $image for linux/arm64"
  container image pull --platform linux/arm64 "$image"
done

"$SCRIPT_DIR/build-app-image.sh"

if [[ ! -f "$STYLE_ASSETS_DIR/.fonts-installed-$OPENMAPTILES_FONTS_COMMIT" ]]; then
  asset_tmp="$(mktemp -d)"
  trap 'rm -rf -- "$asset_tmp"' EXIT
  log "installing pinned local font glyphs"
  curl --fail --location --retry 3 \
    "https://github.com/openmaptiles/fonts/archive/$OPENMAPTILES_FONTS_COMMIT.tar.gz" \
    --output "$asset_tmp/fonts.tgz"
  mkdir -p "$asset_tmp/fonts"
  tar -xzf "$asset_tmp/fonts.tgz" -C "$asset_tmp/fonts" --strip-components=1 \
    "fonts-$OPENMAPTILES_FONTS_COMMIT/Open Sans Regular" \
    "fonts-$OPENMAPTILES_FONTS_COMMIT/Open Sans Semibold"
  mkdir -p "$STYLE_ASSETS_DIR/fonts/Open Sans Regular" "$STYLE_ASSETS_DIR/fonts/Open Sans Semibold"
  cp -R "$asset_tmp/fonts/Open Sans Regular/." "$STYLE_ASSETS_DIR/fonts/Open Sans Regular/"
  cp -R "$asset_tmp/fonts/Open Sans Semibold/." "$STYLE_ASSETS_DIR/fonts/Open Sans Semibold/"
  touch "$STYLE_ASSETS_DIR/.fonts-installed-$OPENMAPTILES_FONTS_COMMIT"
fi

log "bootstrap complete; persistent files: $ONON_DATA_ROOT; PostgreSQL volume: $POSTGRES_VOLUME"
