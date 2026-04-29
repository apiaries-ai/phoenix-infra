#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/opt/apiaries/backups/postgres}"
BACKUP_SCRIPT="${BACKUP_SCRIPT:-/opt/apiaries/backup-pg.sh}"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"
RUN_BACKUP=0
errors=0
log_file=""

usage() {
  cat <<'USAGE'
Usage: scripts/verify-postgres-backups.sh [--run] [options]

Verifies Phoenix PostgreSQL backup state. By default this is read-only: it
checks the backup script path and the newest backup directory. With --run, it
executes the configured backup script and requires "DONE errors=0" in output.

Options:
  --run                 execute the backup script before verifying latest output
  --backup-root PATH    default: /opt/apiaries/backups/postgres
  --script PATH         default: /opt/apiaries/backup-pg.sh
  --max-age-hours N     default: 24; use 0 to skip age check
  -h, --help            show this help
USAGE
}

cleanup() {
  if [[ -n "$log_file" && -f "$log_file" ]]; then
    rm -f "$log_file"
  fi
}
trap cleanup EXIT

pass() {
  printf 'OK %s\n' "$*"
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

while (( $# > 0 )); do
  case "$1" in
    --run)
      RUN_BACKUP=1
      shift
      ;;
    --backup-root)
      BACKUP_ROOT="${2:?missing value for --backup-root}"
      shift 2
      ;;
    --script)
      BACKUP_SCRIPT="${2:?missing value for --script}"
      shift 2
      ;;
    --max-age-hours)
      MAX_AGE_HOURS="${2:?missing value for --max-age-hours}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$MAX_AGE_HOURS" =~ ^[0-9]+$ ]]; then
  printf 'MAX_AGE_HOURS must be a non-negative integer\n' >&2
  exit 2
fi

latest_backup_dir() {
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort | tail -n 1
}

if [[ -x "$BACKUP_SCRIPT" ]]; then
  pass "backup script is executable: $BACKUP_SCRIPT"
else
  fail "backup script is missing or not executable: $BACKUP_SCRIPT"
fi

if [[ -d "$BACKUP_ROOT" ]]; then
  pass "backup root exists: $BACKUP_ROOT"
else
  fail "backup root is missing: $BACKUP_ROOT"
fi

if (( RUN_BACKUP > 0 )); then
  if [[ -x "$BACKUP_SCRIPT" ]]; then
    log_file="$(mktemp)"
    set +e
    "$BACKUP_SCRIPT" 2>&1 | tee "$log_file"
    backup_rc=${PIPESTATUS[0]}
    set -e

    if (( backup_rc == 0 )); then
      pass "backup script exited 0"
    else
      fail "backup script exited $backup_rc"
    fi

    if grep -q '^DONE errors=0$' "$log_file"; then
      pass "backup script reported DONE errors=0"
    else
      fail "backup script did not report DONE errors=0"
    fi
  fi
fi

if [[ -d "$BACKUP_ROOT" ]]; then
  latest="$(latest_backup_dir)"
  if [[ -n "$latest" ]]; then
    pass "latest backup directory: $latest"

    file_count="$(find "$latest" -type f -size +0c 2>/dev/null | wc -l | tr -d '[:space:]')"
    if [[ "$file_count" =~ ^[0-9]+$ && "$file_count" -gt 0 ]]; then
      pass "latest backup contains $file_count non-empty file(s)"
    else
      fail "latest backup contains no non-empty files: $latest"
    fi

    if (( MAX_AGE_HOURS > 0 )); then
      latest_mtime="$(stat -c '%Y' "$latest" 2>/dev/null || stat -f '%m' "$latest" 2>/dev/null || true)"
      if [[ "$latest_mtime" =~ ^[0-9]+$ ]]; then
        now="$(date +%s)"
        age_seconds=$((now - latest_mtime))
        max_age_seconds=$((MAX_AGE_HOURS * 3600))
        if (( age_seconds <= max_age_seconds )); then
          pass "latest backup age is within ${MAX_AGE_HOURS}h"
        else
          fail "latest backup is older than ${MAX_AGE_HOURS}h"
        fi
      else
        fail "could not determine mtime for latest backup: $latest"
      fi
    fi
  else
    fail "no backup directories found under $BACKUP_ROOT"
  fi
fi

finish
