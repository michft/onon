#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_command container
[[ $# -eq 1 ]] || die "usage: scripts/restore-local.sh /absolute/path/to/database.dump"
dump="$1"
[[ "$dump" = /* && -f "$dump" ]] || die "dump must be an existing absolute path"
load_config
container_running "$POSTGRES_CONTAINER" || die "PostgreSQL is not running"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
stage="${POSTGRES_DB}_restore_${stamp}"
archive="${POSTGRES_DB}_before_${stamp}"
web_was_running=false
container_running "$WEB_CONTAINER" && web_was_running=true

container exec -i "$POSTGRES_CONTAINER" pg_restore --list <"$dump" >/dev/null
container exec "$POSTGRES_CONTAINER" createdb --username "$POSTGRES_USER" --template template0 "$stage"
restore_failed=true
rollback_stage() {
  if [[ "$restore_failed" = true ]]; then
    warn "restore failed; staging database $stage retained for inspection"
  fi
}
trap rollback_stage EXIT INT TERM

log "restoring into staging database $stage"
container exec -i "$POSTGRES_CONTAINER" pg_restore --exit-on-error --no-owner --no-privileges \
  --username "$POSTGRES_USER" --dbname "$stage" <"$dump"
container exec "$POSTGRES_CONTAINER" psql --username "$POSTGRES_USER" --dbname "$stage" \
  --no-psqlrc --tuples-only --command 'SELECT 1;' | grep -q 1

if [[ "$web_was_running" = true ]]; then container stop --time 30 "$WEB_CONTAINER"; fi
container exec -i "$POSTGRES_CONTAINER" psql --username "$POSTGRES_USER" --dbname postgres --no-psqlrc \
  --set "old_name=$POSTGRES_DB" --set "archive_name=$archive" <<'SQL'
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
 WHERE datname = :'old_name' AND pid <> pg_backend_pid();
ALTER DATABASE :"old_name" RENAME TO :"archive_name";
SQL
if ! container exec -i "$POSTGRES_CONTAINER" psql --username "$POSTGRES_USER" --dbname postgres --no-psqlrc \
  --set "old_name=$POSTGRES_DB" --set "stage_name=$stage" <<'SQL'
ALTER DATABASE :"stage_name" RENAME TO :"old_name";
SQL
then
  warn "database switch failed; restoring original database name"
  container exec -i "$POSTGRES_CONTAINER" psql --username "$POSTGRES_USER" --dbname postgres --no-psqlrc \
    --set "old_name=$POSTGRES_DB" --set "archive_name=$archive" <<'SQL'
ALTER DATABASE :"archive_name" RENAME TO :"old_name";
SQL
  if [[ "$web_was_running" = true ]]; then container start "$WEB_CONTAINER" || true; fi
  die "restore validation succeeded but activation failed"
fi
restore_failed=false
trap - EXIT INT TERM

if [[ "$web_was_running" = true ]]; then
  replace_runtime_container "$WEB_CONTAINER"
  start_web
fi
log "restore active; prior database retained as $archive"
