#!/usr/bin/env bash
set -euo pipefail

if ! command -v yq >/dev/null 2>&1; then
  echo "::error ::yq v4 is required but was not found on PATH"
  exit 1
fi

if ! yq --version 2>/dev/null | grep -Eq 'version v?4\.'; then
  echo "::error ::mikefarah yq v4 is required"
  yq --version || true
  exit 1
fi

compose_glob="${DRIFT_COMPOSE_GLOB:-stacks/*/docker-compose.yml}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

expected_records="$tmpdir/expected-records.txt"
expected="$tmpdir/expected.txt"
running_raw="$tmpdir/running-raw.txt"
running="$tmpdir/running.txt"
ignored="$tmpdir/ignored.txt"

: >"$expected_records"
: >"$running_raw"

printf '%s\n' "${DRIFT_IGNORE:-}" \
  | tr ',' '\n' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
  | awk 'NF' \
  | sort -u >"$ignored"

shopt -s nullglob
compose_files=($compose_glob)
shopt -u nullglob

for compose_file in "${compose_files[@]}"; do
  yq eval -rN '
    (.services // {}) | to_entries[] |
    select(((.value.profiles // []) | length) == 0) |
    [.key, (.value.container_name // .key)] | @tsv
  ' "$compose_file" \
    | awk 'NF' >>"$expected_records"
done

docker ps --format '{{.Names}}' | awk 'NF' >"$running_raw"

filter_expected() {
  local source_file="$1"
  local service_name container_name
  while IFS=$'\t' read -r service_name container_name; do
    if grep -qFx "$service_name" "$ignored" || grep -qFx "$container_name" "$ignored"; then
      continue
    fi
    printf '%s\n' "$container_name"
  done <"$source_file"
}

filter_running() {
  local source_file="$1"
  local container_name
  while IFS= read -r container_name; do
    if grep -qFx "$container_name" "$ignored"; then
      continue
    fi
    printf '%s\n' "$container_name"
  done <"$source_file"
}

filter_expected "$expected_records" | sort -u >"$expected"
filter_running "$running_raw" | sort -u >"$running"

missing=0

while IFS= read -r declared; do
  if grep -qFx "$declared" "$running"; then
    echo "✅ Running as declared: $declared"
  else
    echo "❌ Declared but not running: $declared"
    missing=1
  fi
done <"$expected"

while IFS= read -r active; do
  if ! grep -qFx "$active" "$expected"; then
    echo "⚠️  Running but not declared: $active"
  fi
done <"$running"

exit "$missing"
