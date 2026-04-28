#!/usr/bin/env bash
set -uo pipefail

PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
PAPERCLIP_CONTAINER="${PAPERCLIP_CONTAINER:-paperclip}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-paperclip-postgres}"
RUNTIME_VOLUME="${RUNTIME_VOLUME:-paperclip_runtime}"
CONFIG_PATH="${CONFIG_PATH:-/paperclip/instances/default/config.json}"
FORBIDDEN_HOST_PORT="${FORBIDDEN_HOST_PORT:-5435}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"

failures=0
warnings=0

ok() {
  printf 'OK   %s\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf 'WARN %s\n' "$1" >&2
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL %s\n' "$1" >&2
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing required command: $1"
    return 1
  fi
  return 0
}

check_http() {
  local status

  status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time "$CURL_TIMEOUT" "$PAPERCLIP_URL" 2>/dev/null)"
  if [[ "$status" == "200" ]]; then
    ok "Paperclip returned HTTP 200 at $PAPERCLIP_URL"
  else
    fail "Paperclip returned HTTP ${status:-000} at $PAPERCLIP_URL"
  fi
}

container_running() {
  local name="$1"
  local running

  running="$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)"
  if [[ "$running" == "true" ]]; then
    ok "container $name is running"
  else
    fail "container $name is not running"
  fi
}

check_postgres_health() {
  local health

  container_running "$POSTGRES_CONTAINER"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$POSTGRES_CONTAINER" 2>/dev/null || true)"
  if [[ "$health" == "healthy" ]]; then
    ok "$POSTGRES_CONTAINER healthcheck is healthy"
  elif [[ -n "$health" ]]; then
    fail "$POSTGRES_CONTAINER healthcheck is $health"
  else
    warn "$POSTGRES_CONTAINER has no Docker healthcheck status"
  fi
}

check_app_env() {
  local app_env

  app_env="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$PAPERCLIP_CONTAINER" 2>/dev/null || true)"
  if printf '%s\n' "$app_env" | grep -qx 'PAPERCLIP_HOME=/paperclip'; then
    ok "$PAPERCLIP_CONTAINER has PAPERCLIP_HOME=/paperclip"
  else
    fail "$PAPERCLIP_CONTAINER is missing PAPERCLIP_HOME=/paperclip"
  fi

  if printf '%s\n' "$app_env" | grep -qx "PAPERCLIP_CONFIG=${CONFIG_PATH}"; then
    ok "$PAPERCLIP_CONTAINER has PAPERCLIP_CONFIG=$CONFIG_PATH"
  else
    fail "$PAPERCLIP_CONTAINER is missing PAPERCLIP_CONFIG=$CONFIG_PATH"
  fi

  if printf '%s\n' "$app_env" | grep -q '^DATABASE_URL=.*5435'; then
    fail "$PAPERCLIP_CONTAINER DATABASE_URL still references port 5435"
  elif printf '%s\n' "$app_env" | grep -q '^DATABASE_URL=.*paperclip-postgres:5432'; then
    ok "$PAPERCLIP_CONTAINER DATABASE_URL targets paperclip-postgres:5432"
  else
    warn "$PAPERCLIP_CONTAINER DATABASE_URL was not recognized as paperclip-postgres:5432"
  fi
}

check_postgres_not_published() {
  local published

  published="$(docker port "$POSTGRES_CONTAINER" 5432/tcp 2>/dev/null || true)"
  if [[ -z "$published" ]]; then
    ok "$POSTGRES_CONTAINER:5432 is Docker-internal only"
  else
    fail "$POSTGRES_CONTAINER:5432 is published on the host"
  fi
}

check_forbidden_port_closed() {
  if command -v ss >/dev/null 2>&1; then
    if ss -H -tln | awk '{print $4}' | grep -Eq "(^|[:.])${FORBIDDEN_HOST_PORT}$"; then
      fail "host port $FORBIDDEN_HOST_PORT is listening"
    else
      ok "host port $FORBIDDEN_HOST_PORT is not listening"
    fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$FORBIDDEN_HOST_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      fail "host port $FORBIDDEN_HOST_PORT is listening"
    else
      ok "host port $FORBIDDEN_HOST_PORT is not listening"
    fi
  else
    warn "cannot verify host port $FORBIDDEN_HOST_PORT; neither ss nor lsof is installed"
  fi
}

check_runtime_mount() {
  local mounts

  if ! docker volume inspect "$RUNTIME_VOLUME" >/dev/null 2>&1; then
    fail "runtime volume $RUNTIME_VOLUME does not exist"
    return
  fi
  ok "runtime volume $RUNTIME_VOLUME exists"

  mounts="$(docker inspect -f '{{range .Mounts}}{{printf "%s:%s:%s\n" .Type .Name .Destination}}{{end}}' "$PAPERCLIP_CONTAINER" 2>/dev/null || true)"
  if printf '%s\n' "$mounts" | grep -qx "volume:${RUNTIME_VOLUME}:/paperclip"; then
    ok "$RUNTIME_VOLUME is mounted at /paperclip"
  else
    fail "$RUNTIME_VOLUME is not mounted at /paperclip"
  fi

  if printf '%s\n' "$mounts" | grep -q ':/root/.paperclip$'; then
    fail "a volume is mounted at /root/.paperclip"
  else
    ok "no volume is mounted at /root/.paperclip"
  fi
}

check_runtime_config() {
  local mountpoint
  local cfg
  local owner

  mountpoint="$(docker volume inspect "$RUNTIME_VOLUME" -f '{{.Mountpoint}}' 2>/dev/null || true)"
  if [[ -z "$mountpoint" ]]; then
    return
  fi

  cfg="$mountpoint/instances/default/config.json"
  if [[ -r "$cfg" ]]; then
    if grep -q '/root/.paperclip' "$cfg"; then
      fail "$CONFIG_PATH still references /root/.paperclip"
    else
      ok "$CONFIG_PATH does not reference /root/.paperclip"
    fi

    if grep -q '172.17.0.1:5435' "$cfg"; then
      fail "$CONFIG_PATH still references 172.17.0.1:5435"
    else
      ok "$CONFIG_PATH does not reference 172.17.0.1:5435"
    fi
  else
    warn "cannot read $cfg; run with sufficient host permissions to verify config contents"
  fi

  if owner="$(stat -c '%u:%g' "$mountpoint" 2>/dev/null || stat -f '%u:%g' "$mountpoint" 2>/dev/null)"; then
    if [[ "$owner" == "1000:1000" ]]; then
      ok "$RUNTIME_VOLUME mountpoint is owned by 1000:1000"
    else
      fail "$RUNTIME_VOLUME mountpoint is owned by $owner, expected 1000:1000"
    fi
  else
    warn "cannot stat $mountpoint to verify 1000:1000 ownership"
  fi
}

main() {
  need_cmd curl
  need_cmd docker

  if (( failures == 0 )); then
    check_http
    container_running "$PAPERCLIP_CONTAINER"
    check_app_env
    check_postgres_health
    check_postgres_not_published
    check_forbidden_port_closed
    check_runtime_mount
    check_runtime_config
  fi

  printf '\nSUMMARY failures=%d warnings=%d\n' "$failures" "$warnings"
  if (( failures > 0 )); then
    exit 1
  fi
}

main "$@"
