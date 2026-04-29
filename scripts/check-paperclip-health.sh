#!/usr/bin/env bash
set -Eeuo pipefail

APP_CONTAINER="${APP_CONTAINER:-paperclip}"
DB_CONTAINER="${DB_CONTAINER:-paperclip-postgres}"
PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
HTTP_EXPECTED="${HTTP_EXPECTED:-200}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-10}"
RUNTIME_VOLUME="${RUNTIME_VOLUME:-paperclip_runtime}"
RUNTIME_OWNER="${RUNTIME_OWNER:-1000:1000}"
CONFIG_PATH="${CONFIG_PATH:-/paperclip/instances/default/config.json}"
DISALLOWED_DB_PORT="${DISALLOWED_DB_PORT:-5435}"

errors=0

usage() {
  cat <<'USAGE'
Usage: scripts/check-paperclip-health.sh

Read-only Paperclip health checks for the Phoenix host. The script does not
restart, stop, recreate, or modify containers.

Environment overrides:
  APP_CONTAINER        default: paperclip
  DB_CONTAINER         default: paperclip-postgres
  PAPERCLIP_URL        default: http://127.0.0.1:3100
  HTTP_EXPECTED        default: 200
  HTTP_TIMEOUT         default: 10
  RUNTIME_VOLUME       default: paperclip_runtime
  RUNTIME_OWNER        default: 1000:1000
  CONFIG_PATH          default: /paperclip/instances/default/config.json
  DISALLOWED_DB_PORT   default: 5435
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

pass() {
  printf 'OK %s\n' "$*"
}

warn() {
  printf 'WARN %s\n' "$*" >&2
}

fail() {
  printf 'ERROR %s\n' "$*" >&2
  errors=$((errors + 1))
}

finish() {
  if (( errors > 0 )); then
    printf 'DONE errors=%d\n' "$errors" >&2
    exit 1
  fi

  printf 'DONE errors=0\n'
}

missing=0
for cmd in docker curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "required command not found: $cmd"
    missing=1
  fi
done

if (( missing > 0 )); then
  finish
fi

app_running=0
if docker inspect "$APP_CONTAINER" >/dev/null 2>&1; then
  app_state="$(docker inspect -f '{{.State.Running}}' "$APP_CONTAINER" 2>/dev/null || true)"
  if [[ "$app_state" == "true" ]]; then
    pass "$APP_CONTAINER is running"
    app_running=1
  else
    fail "$APP_CONTAINER exists but is not running"
  fi
else
  fail "$APP_CONTAINER container is missing"
fi

http_code="$(curl -sS -o /dev/null -I --max-time "$HTTP_TIMEOUT" -w '%{http_code}' "$PAPERCLIP_URL" 2>/dev/null || true)"
if [[ "$http_code" == "$HTTP_EXPECTED" ]]; then
  pass "$PAPERCLIP_URL returned HTTP $http_code"
else
  fail "$PAPERCLIP_URL returned HTTP ${http_code:-no-response}, expected $HTTP_EXPECTED"
fi

if docker inspect "$DB_CONTAINER" >/dev/null 2>&1; then
  db_state="$(docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null || true)"
  if [[ "$db_state" == "true" ]]; then
    pass "$DB_CONTAINER is running"
  else
    fail "$DB_CONTAINER exists but is not running"
  fi

  db_health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$DB_CONTAINER" 2>/dev/null || true)"
  if [[ "$db_health" == "healthy" ]]; then
    pass "$DB_CONTAINER healthcheck is healthy"
  else
    fail "$DB_CONTAINER healthcheck is ${db_health:-unknown}, expected healthy"
  fi

  db_ports="$(docker port "$DB_CONTAINER" 2>/dev/null || true)"
  if [[ -z "$db_ports" ]]; then
    pass "$DB_CONTAINER has no published host ports"
  else
    fail "$DB_CONTAINER has published host ports: $(printf '%s' "$db_ports" | tr '\n' ';')"
  fi
else
  fail "$DB_CONTAINER container is missing"
fi

if command -v ss >/dev/null 2>&1; then
  if ss -H -tln "sport = :$DISALLOWED_DB_PORT" 2>/dev/null | grep -q .; then
    fail "host port $DISALLOWED_DB_PORT is listening"
  else
    pass "host port $DISALLOWED_DB_PORT is not listening"
  fi
elif command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$DISALLOWED_DB_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    fail "host port $DISALLOWED_DB_PORT is listening"
  else
    pass "host port $DISALLOWED_DB_PORT is not listening"
  fi
else
  warn "skipping host port check; neither ss nor lsof is available"
fi

runtime_mount="$(docker volume inspect "$RUNTIME_VOLUME" -f '{{.Mountpoint}}' 2>/dev/null || true)"
if [[ -n "$runtime_mount" ]]; then
  pass "$RUNTIME_VOLUME exists at $runtime_mount"
  if [[ -d "$runtime_mount" ]]; then
    runtime_owner="$(stat -c '%u:%g' "$runtime_mount" 2>/dev/null || stat -f '%u:%g' "$runtime_mount" 2>/dev/null || true)"
    if [[ "$runtime_owner" == "$RUNTIME_OWNER" ]]; then
      pass "$RUNTIME_VOLUME owner is $RUNTIME_OWNER"
    else
      fail "$RUNTIME_VOLUME owner is ${runtime_owner:-unknown}, expected $RUNTIME_OWNER"
    fi
  else
    fail "$RUNTIME_VOLUME mountpoint is not a directory: $runtime_mount"
  fi
else
  fail "$RUNTIME_VOLUME volume is missing"
fi

if (( app_running > 0 )); then
  if docker exec "$APP_CONTAINER" sh -c '[ "${HOME:-}" = "/paperclip" ]' >/dev/null 2>&1; then
    pass "$APP_CONTAINER HOME is /paperclip"
  else
    fail "$APP_CONTAINER HOME is not /paperclip"
  fi

  if docker exec "$APP_CONTAINER" sh -c '[ "${PAPERCLIP_HOME:-}" = "/paperclip" ]' >/dev/null 2>&1; then
    pass "$APP_CONTAINER PAPERCLIP_HOME is /paperclip"
  else
    fail "$APP_CONTAINER PAPERCLIP_HOME is not /paperclip"
  fi

  if docker exec "$APP_CONTAINER" sh -c '[ "${PAPERCLIP_CONFIG:-}" = "$1" ]' sh "$CONFIG_PATH" >/dev/null 2>&1; then
    pass "$APP_CONTAINER PAPERCLIP_CONFIG is $CONFIG_PATH"
  else
    fail "$APP_CONTAINER PAPERCLIP_CONFIG is not $CONFIG_PATH"
  fi

  if docker exec "$APP_CONTAINER" test -f "$CONFIG_PATH" >/dev/null 2>&1; then
    pass "$CONFIG_PATH exists in $APP_CONTAINER"

    if docker exec "$APP_CONTAINER" grep -q '/root/.paperclip' "$CONFIG_PATH" >/dev/null 2>&1; then
      fail "$CONFIG_PATH still references /root/.paperclip"
    else
      pass "$CONFIG_PATH does not reference /root/.paperclip"
    fi

    if docker exec "$APP_CONTAINER" grep -q '172\.17\.0\.1:5435' "$CONFIG_PATH" >/dev/null 2>&1; then
      fail "$CONFIG_PATH still references 172.17.0.1:5435"
    else
      pass "$CONFIG_PATH does not reference 172.17.0.1:5435"
    fi
  else
    fail "$CONFIG_PATH is missing in $APP_CONTAINER"
  fi
else
  warn "skipping in-container config checks because $APP_CONTAINER is not running"
fi

finish
