# drift-check-hardening-v1

Tag: `drift-check-hardening-v1`
Date: 2026-05-01
Authorized by: Eric Bien

## Summary

Closes the `drift-check` failure first observed in run #25166018349 and removes
the latent fragilities in the awk-based parser. No stack behavior changed
beyond making `nextcloud` opt-in.

## Changes (PR #7)

- Replaced the inline awk parser with `scripts/drift-check.sh`, a yq-based
  implementation that handles multi-document YAML, inline `profiles: [...]`,
  and `container_name` overrides.
- Profile-gated every service in `stacks/nextcloud/` with
  `profiles: ["nextcloud"]`. The stack is now opt-in.
- Bumped `actions/checkout@v4` → `actions/checkout@v5`, clearing the
  Node.js 20 deprecation warning ahead of the 2026-06-02 forced Node 24
  cutover.
- Added a `workflow_dispatch` `ignore` input that maps to `DRIFT_IGNORE`.
- Added bats test suite `scripts/tests/drift-check.bats` (8 cases) with a
  `ci` job in the workflow.

## Verification

- Self-hosted `check`: green on `main` (run id: 25229680802).
- `ci` (bats suite): 8/8 green.
- Compose validation: green across all stacks.
- Local developer run on Mac Air M4 returns exit 1 by design; see
  `CONTRIBUTING.md` for the documented developer-side checks.

## Operational guarantees

No DB writes, DNS changes, secret rotations, or tenant-facing changes were
introduced. The Easypawn read-only contract from
`easypawn-readonly-v1` is unaffected.
