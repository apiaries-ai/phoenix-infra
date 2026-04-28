#!/usr/bin/env bash
set -uo pipefail

SNAPSHOT_DIR="${SNAPSHOT_DIR:-/opt/apiaries/snapshots}"
SNAPSHOT_PATTERN="${SNAPSHOT_PATTERN:-phoenix-paperclip-*.tar.gz}"
KEEP="${KEEP:-7}"
APPLY=0
INCLUDE_FIXED=0

usage() {
  cat <<'USAGE'
Usage: snapshot-rotate.sh [--apply] [--dir PATH] [--pattern GLOB] [--keep COUNT] [--include-fixed]

Plans rotation for Phoenix Paperclip snapshots. The default mode is a dry run.
Snapshots with "fixed" in the filename are protected unless --include-fixed is set.
USAGE
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

stat_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null
}

snapshot_list() {
  local snapshot
  local mtime

  while IFS= read -r -d '' snapshot; do
    mtime="$(stat_mtime "$snapshot" || printf '0')"
    printf '%s %s\n' "$mtime" "$snapshot"
  done < <(find "$SNAPSHOT_DIR" -maxdepth 1 -type f -name "$SNAPSHOT_PATTERN" -print0 2>/dev/null)
}

parse_args() {
  while (($#)); do
    case "$1" in
      --apply)
        APPLY=1
        shift
        ;;
      --dir)
        if (($# < 2)) || [[ -z "${2:-}" ]]; then
          fail "--dir requires a path"
        fi
        SNAPSHOT_DIR="${2:-}"
        shift 2
        ;;
      --pattern)
        if (($# < 2)) || [[ -z "${2:-}" ]]; then
          fail "--pattern requires a glob"
        fi
        SNAPSHOT_PATTERN="${2:-}"
        shift 2
        ;;
      --keep)
        if (($# < 2)) || [[ -z "${2:-}" ]]; then
          fail "--keep requires a count"
        fi
        KEEP="${2:-}"
        shift 2
        ;;
      --include-fixed)
        INCLUDE_FIXED=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown argument: $1"
        ;;
    esac
  done
}

validate_inputs() {
  if [[ ! "$KEEP" =~ ^[0-9]+$ ]]; then
    fail "--keep must be a non-negative integer"
  fi

  if [[ -z "$SNAPSHOT_DIR" || ! -d "$SNAPSHOT_DIR" ]]; then
    fail "snapshot directory does not exist: $SNAPSHOT_DIR"
  fi
}

main() {
  local kept=0
  local remove_count=0
  local total=0
  local line
  local snapshot
  local base
  local action
  local fixed_protection="enabled"
  local candidates=()

  parse_args "$@"
  validate_inputs

  printf 'Snapshot directory: %s\n' "$SNAPSHOT_DIR"
  printf 'Snapshot pattern:   %s\n' "$SNAPSHOT_PATTERN"
  printf 'Keep newest:        %s\n' "$KEEP"
  if (( APPLY == 1 )); then
    printf 'Mode:               apply\n\n'
  else
    printf 'Mode:               dry-run\n\n'
  fi
  if (( INCLUDE_FIXED == 1 )); then
    fixed_protection="disabled"
  fi

  while IFS= read -r line; do
    snapshot="${line#* }"
    [[ -z "$snapshot" ]] && continue
    total=$((total + 1))
    base="$(basename "$snapshot")"

    if (( INCLUDE_FIXED == 0 )) && [[ "$base" == *fixed* ]]; then
      printf 'PROTECT fixed snapshot %s\n' "$snapshot"
      continue
    fi

    if (( kept < KEEP )); then
      kept=$((kept + 1))
      printf 'KEEP newest[%d] %s\n' "$kept" "$snapshot"
    else
      candidates+=("$snapshot")
    fi
  done < <(snapshot_list | sort -rn)

  printf '\n'
  for snapshot in "${candidates[@]}"; do
    remove_count=$((remove_count + 1))
    if (( APPLY == 1 )); then
      rm -f -- "$snapshot"
      action="REMOVED"
    else
      action="WOULD_REMOVE"
    fi
    printf '%s %s\n' "$action" "$snapshot"
  done

  printf '\nSUMMARY total=%d kept=%d rotation_candidates=%d fixed_protection=%s\n' "$total" "$kept" "$remove_count" "$fixed_protection"
  if (( APPLY == 0 )); then
    printf 'Dry run only. Re-run with --apply to remove rotation candidates.\n'
  fi
}

main "$@"
