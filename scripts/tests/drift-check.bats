#!/usr/bin/env bats

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/repo"
  export FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  export SCRIPT="$BATS_TEST_DIRNAME/../drift-check.sh"
  mkdir -p "$TEST_ROOT/stacks/test" "$FAKE_BIN"
}

write_compose() {
  local stack="${1:-test}"
  mkdir -p "$TEST_ROOT/stacks/$stack"
  cat >"$TEST_ROOT/stacks/$stack/docker-compose.yml"
}

fake_docker_ps() {
  cat >"$FAKE_BIN/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "ps" ]]; then
  printf '%s\n' ${DOCKER_PS_NAMES:-}
  exit 0
fi
echo "unexpected docker invocation: $*" >&2
exit 2
SH
  chmod +x "$FAKE_BIN/docker"
}

run_drift_check() {
  (cd "$TEST_ROOT" && PATH="$FAKE_BIN:$PATH" "$SCRIPT")
}

@test "service with no profiles and matching running container passes" {
  write_compose <<'YAML'
services:
  app:
    image: alpine
YAML
  fake_docker_ps
  export DOCKER_PS_NAMES="app"

  run run_drift_check

  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ Running as declared: app"* ]]
}

@test "service with profiles and not running is ignored" {
  write_compose <<'YAML'
services:
  optional:
    image: alpine
    profiles:
      - optional
YAML
  fake_docker_ps
  export DOCKER_PS_NAMES=""

  run run_drift_check

  [ "$status" -eq 0 ]
  [[ "$output" != *"Declared but not running"* ]]
}

@test "container_name override is matched instead of service key" {
  write_compose <<'YAML'
services:
  app:
    image: alpine
    container_name: phoenix-app
YAML
  fake_docker_ps
  export DOCKER_PS_NAMES="phoenix-app"

  run run_drift_check

  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ Running as declared: phoenix-app"* ]]
  [[ "$output" != *"Running as declared: app"* ]]
}

@test "declared but not running service exits 1" {
  write_compose <<'YAML'
services:
  app:
    image: alpine
YAML
  fake_docker_ps
  export DOCKER_PS_NAMES=""

  run run_drift_check

  [ "$status" -eq 1 ]
  [[ "$output" == *"❌ Declared but not running: app"* ]]
}

@test "running but undeclared service warns only" {
  write_compose <<'YAML'
services:
  app:
    image: alpine
YAML
  fake_docker_ps
  export DOCKER_PS_NAMES="app extra"

  run run_drift_check

  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ Running as declared: app"* ]]
  [[ "$output" == *"⚠️  Running but not declared: extra"* ]]
}

@test "DRIFT_IGNORE skips missing services" {
  write_compose <<'YAML'
services:
  foo:
    image: alpine
  bar:
    image: alpine
  baz:
    image: alpine
YAML
  fake_docker_ps
  export DOCKER_PS_NAMES="baz"
  export DRIFT_IGNORE="foo,bar"

  run run_drift_check

  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ Running as declared: baz"* ]]
  [[ "$output" != *"foo"* ]]
  [[ "$output" != *"bar"* ]]
}

@test "multi-document YAML parses declared services" {
  write_compose <<'YAML'
---
services:
  app:
    image: alpine
---
services:
  worker:
    image: alpine
    container_name: worker-container
YAML
  fake_docker_ps
  export DOCKER_PS_NAMES="app worker-container"

  run run_drift_check

  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ Running as declared: app"* ]]
  [[ "$output" == *"✅ Running as declared: worker-container"* ]]
}

@test "inline profiles form is recognized as gated" {
  write_compose <<'YAML'
services:
  optional:
    image: alpine
    profiles: ["x"]
YAML
  fake_docker_ps
  export DOCKER_PS_NAMES=""

  run run_drift_check

  [ "$status" -eq 0 ]
  [[ "$output" != *"Declared but not running"* ]]
}
