#!/usr/bin/env bash
set -Eeuo pipefail

SNAPSHOT_DIR="${SNAPSHOT_DIR:-/opt/apiaries/snapshots}"
SNAPSHOT_PATTERN="${SNAPSHOT_PATTERN:-phoenix-paperclip-*.tar.gz}"
KEEP="${KEEP:-7}"
APPLY=0
PROTECT_FIXED=1

usage() {
  cat <<'USAGE'
Usage: scripts/snapshot-rotate.sh [--apply] [options]

Dry-run rotation for Phoenix Paperclip snapshots. By default it only reports
what would be removed. Pass --apply to delete old matching snapshots.

Options:
  --apply              delete old snapshots after listing them
  --keep N             keep N newest non-protected snapshots; default: 7
  --snapshot-dir PATH  default: /opt/apiaries/snapshots
  --pattern GLOB       default: phoenix-paperclip-*.tar.gz
  --include-fixed      allow phoenix-paperclip-fixed-*.tar.gz snapshots to rotate
  -h, --help           show this help
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --keep)
      KEEP="${2:?missing value for --keep}"
      shift 2
      ;;
    --snapshot-dir)
      SNAPSHOT_DIR="${2:?missing value for --snapshot-dir}"
      shift 2
      ;;
    --pattern)
      SNAPSHOT_PATTERN="${2:?missing value for --pattern}"
      shift 2
      ;;
    --include-fixed)
      PROTECT_FIXED=0
      shift
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

if ! [[ "$KEEP" =~ ^[0-9]+$ ]] || (( KEEP < 1 )); then
  printf 'KEEP must be a positive integer\n' >&2
  exit 2
fi

if [[ "$SNAPSHOT_DIR" != /* ]]; then
  printf 'SNAPSHOT_DIR must be an absolute path: %s\n' "$SNAPSHOT_DIR" >&2
  exit 2
fi

if [[ "$SNAPSHOT_PATTERN" == */* ]]; then
  printf 'SNAPSHOT_PATTERN must be a filename glob, not a path: %s\n' "$SNAPSHOT_PATTERN" >&2
  exit 2
fi

if [[ ! -d "$SNAPSHOT_DIR" ]]; then
  printf 'Snapshot directory does not exist: %s\n' "$SNAPSHOT_DIR" >&2
  exit 1
fi

snapshot_entries=()
while IFS= read -r -d '' path; do
  mtime="$(stat -c '%Y' "$path" 2>/dev/null || stat -f '%m' "$path" 2>/dev/null || true)"
  if [[ "$mtime" =~ ^[0-9]+$ ]]; then
    snapshot_entries+=("$mtime $path")
  else
    printf 'Skipping snapshot with unreadable mtime: %s\n' "$path" >&2
  fi
done < <(find "$SNAPSHOT_DIR" -maxdepth 1 -type f -name "$SNAPSHOT_PATTERN" -print0 2>/dev/null)

snapshots=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  snapshots+=("${line#* }")
done < <(printf '%s\n' "${snapshot_entries[@]}" | sort -nr)

if (( ${#snapshots[@]} == 0 )); then
  printf 'No snapshots matched %s/%s\n' "$SNAPSHOT_DIR" "$SNAPSHOT_PATTERN"
  printf 'DONE deleted=0\n'
  exit 0
fi

printf 'Found %d snapshot(s) matching %s/%s\n' "${#snapshots[@]}" "$SNAPSHOT_DIR" "$SNAPSHOT_PATTERN"
if (( APPLY == 0 )); then
  printf 'Mode: dry run\n'
else
  printf 'Mode: apply\n'
fi

kept=0
delete_list=()
for path in "${snapshots[@]}"; do
  base="${path##*/}"

  if (( PROTECT_FIXED > 0 )) && [[ "$base" == phoenix-paperclip-fixed-*.tar.gz ]]; then
    printf 'keep protected %s\n' "$path"
    continue
  fi

  if (( kept < KEEP )); then
    kept=$((kept + 1))
    printf 'keep recent %s\n' "$path"
  else
    delete_list+=("$path")
  fi
done

if (( ${#delete_list[@]} == 0 )); then
  printf 'No snapshots eligible for deletion\n'
  printf 'DONE deleted=0\n'
  exit 0
fi

deleted=0
for path in "${delete_list[@]}"; do
  if (( APPLY > 0 )); then
    rm -f -- "$path"
    deleted=$((deleted + 1))
    printf 'deleted %s\n' "$path"
  else
    printf 'would delete %s\n' "$path"
  fi
done

if (( APPLY > 0 )); then
  printf 'DONE deleted=%d\n' "$deleted"
else
  printf 'DRY RUN deleted=0 would_delete=%d\n' "${#delete_list[@]}"
fi
