# Phoenix Infrastructure

## Phoenix Paperclip Operations

Paperclip was recovered on Phoenix on 2026-04-28. The operational source of truth is the recovery runbook at `runbooks/paperclip-recovery-2026-04-28.md`.

Production guardrails:

- Do not restart or recreate Paperclip containers during routine checks.
- Paperclip should answer on `http://127.0.0.1:3100`.
- `paperclip-postgres` should be reachable only inside Docker on `5432/tcp`; host port `5435` must stay closed.
- The Paperclip runtime volume is `paperclip_runtime`, mounted at `/paperclip`.
- `PAPERCLIP_CONFIG` must point to `/paperclip/instances/default/config.json`.
- Runtime config paths must use `/paperclip`, not `/root/.paperclip`.
- The runtime volume must remain owned by UID:GID `1000:1000`.
- Keep Paperclip database and auth secrets outside this repository. Use host-managed environment files or secret storage.

Repo-side helpers:

```bash
./scripts/check-paperclip-health.sh
./scripts/verify-postgres-backups.sh
./scripts/verify-postgres-backups.sh --skip-run
./scripts/snapshot-rotate.sh
./scripts/snapshot-rotate.sh --apply --keep 14
```

`check-paperclip-health.sh` performs read-only checks against HTTP, Docker container state, Postgres exposure, runtime mounts, config path normalization, and runtime volume ownership.

`verify-postgres-backups.sh` runs `/opt/apiaries/backup-pg.sh` by default, checks for `DONE errors=0`, and verifies that the latest Postgres backup directory contains non-empty files. Use `--skip-run` to inspect the latest backup without creating a new backup artifact.

`snapshot-rotate.sh` is dry-run by default. It protects snapshots with `fixed` in the filename unless `--include-fixed` is provided. Use `--apply` only after confirming the fixed snapshot has an off-host copy.

The compose file under `stacks/paperclip/docker-compose.yml` documents the desired hardened shape. Applying it to Phoenix changes production, so do that only during an explicit maintenance window.
