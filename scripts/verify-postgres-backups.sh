#!/usr/bin/env bash
set -uo pipefail

BACKUP_SCRIPT="${BACKUP_SCRIPT:-/opt/apiaries/backup-pg.sh}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/apiaries/backups/postgres}"
REQUIRED_BACKUP_MATCHES="${REQUIRED_BACKUP_MATCHES:-paperclip-postgres}"
RUN_BACKUP=1

failures=0
warnings=0
backup_log=""

usage() {
  cat <<'USAGE'
Usage: verify-postgres-backups.sh [--skip-run] [--script PATH] [--root PATH] [--require NAME]

Runs the Phoenix PostgreSQL backup script, checks for DONE errors=0, and verifies
that the newest backup directory contains non-empty backup files. Use --skip-run
to inspect only the latest existing backup directory.
USAGE
}

die_usage() {
  printf 'FAIL %s\n' "$1" >&2
  usage >&2
  exit 2
}

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

redact_output() {
  sed -E \
    -e 's#(postgres(ql)?://[^:/@]+:)[^@[:space:]]+@#\1<redacted>@#g' \
    -e 's#(PASSWORD=)[^[:space:]]+#\1<redacted>#g' \
    -e 's#(password=)[^[:space:]]+#\1<redacted>#g'
}

parse_args() {
  while (($#)); do
    case "$1" in
      --skip-run)
        RUN_BACKUP=0
        shift
        ;;
      --script)
        if (($# < 2)) || [[ -z "${2:-}" ]]; then
          die_usage "--script requires a path"
        fi
        BACKUP_SCRIPT="${2:-}"
        shift 2
        ;;
      --root)
        if (($# < 2)) || [[ -z "${2:-}" ]]; then
          die_usage "--root requires a path"
        fi
        BACKUP_ROOT="${2:-}"
        shift 2
        ;;
      --require)
        if (($# < 2)) || [[ -z "${2:-}" ]]; then
          die_usage "--require requires a filename match"
        fi
        REQUIRED_BACKUP_MATCHES="${REQUIRED_BACKUP_MATCHES} ${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown argument: $1"
        usage >&2
        exit 2
        ;;
    esac
  done
}

stat_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null
}

run_backup_script() {
  backup_log="$(mktemp)"
  if [[ ! -x "$BACKUP_SCRIPT" ]]; then
    fail "backup script is not executable: $BACKUP_SCRIPT"
    return
  fi

  if "$BACKUP_SCRIPT" >"$backup_log" 2>&1; then
    ok "$BACKUP_SCRIPT exited successfully"
  else
    fail "$BACKUP_SCRIPT exited with an error"
  fi

  if grep -q 'DONE errors=0' "$backup_log"; then
    ok "$BACKUP_SCRIPT reported DONE errors=0"
  else
    fail "$BACKUP_SCRIPT did not report DONE errors=0"
    tail -20 "$backup_log" | redact_output >&2
  fi
}

latest_backup_dir() {
  local newest_path=""
  local newest_mtime=-1
  local path
  local mtime

  while IFS= read -r -d '' path; do
    mtime="$(stat_mtime "$path" || printf '0')"
    if [[ "$mtime" =~ ^[0-9]+$ ]] && (( mtime > newest_mtime )); then
      newest_mtime="$mtime"
      newest_path="$path"
    fi
  done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

  printf '%s\n' "$newest_path"
}

verify_latest_backup() {
  local latest
  local file_count
  local match

  if [[ ! -d "$BACKUP_ROOT" ]]; then
    fail "backup root does not exist: $BACKUP_ROOT"
    return
  fi

  latest="$(latest_backup_dir)"
  if [[ -z "$latest" ]]; then
    fail "no backup directories found under $BACKUP_ROOT"
    return
  fi
  ok "latest backup directory: $latest"

  file_count="$(find "$latest" -type f -size +0c 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$file_count" =~ ^[0-9]+$ ]] && (( file_count > 0 )); then
    ok "$latest contains $file_count non-empty backup file(s)"
  else
    fail "$latest does not contain non-empty backup files"
  fi

  for match in $REQUIRED_BACKUP_MATCHES; do
    if find "$latest" -type f -name "*${match}*" -size +0c 2>/dev/null | grep -q .; then
      ok "$latest contains a non-empty backup matching *${match}*"
    else
      fail "$latest is missing a non-empty backup matching *${match}*"
    fi
  done
}

cleanup() {
  if [[ -n "$backup_log" && -f "$backup_log" ]]; then
    rm -f "$backup_log"
  fi
}

main() {
  trap cleanup EXIT
  parse_args "$@"

  if (( RUN_BACKUP == 1 )); then
    run_backup_script
  else
    ok "skipping backup script execution"
  fi

  verify_latest_backup

  printf '\nSUMMARY failures=%d warnings=%d\n' "$failures" "$warnings"
  if (( failures > 0 )); then
    exit 1
  fi
}

main "$@"
