## Running drift-check locally

`scripts/drift-check.sh` enforces an invariant tied to the Phoenix self-hosted
runner's Docker daemon: every service declared in `stacks/*/docker-compose.yml`
that is not profile-gated must be running. On a developer laptop this script is
expected to exit non-zero because most Phoenix services are not running there.

Use these developer-side equivalents instead:

- Parser correctness:
  ```bash
  bats scripts/tests/drift-check.bats
  ```
  Install bats with `brew install bats-core` (macOS) or `apt install bats`
  (Debian/Ubuntu). All eight cases must pass.

- Compose validity:
  ```bash
  for f in stacks/*/docker-compose.yml; do
    (cd "$(dirname "$f")" && docker compose config >/dev/null) || echo "BAD: $f"
  done
  ```

- One-off ignore for an intentionally stopped stack:
  ```bash
  DRIFT_IGNORE=nextcloud,foo bash scripts/drift-check.sh
  ```

The authoritative drift signal is the `drift-check` GitHub Actions workflow on
the self-hosted runner. Local exit codes from `scripts/drift-check.sh` are
informational only.
