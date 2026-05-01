# Phoenix Infrastructure

[![drift-check](https://github.com/apiaries-ai/phoenix-infra/actions/workflows/drift-check.yml/badge.svg?branch=main)](https://github.com/apiaries-ai/phoenix-infra/actions/workflows/drift-check.yml)

## Phoenix Paperclip Operations

Paperclip was recovered on Phoenix on 2026-04-28. The current operating model is:

- App URL on the Phoenix host: `http://127.0.0.1:3100`
- App container: `paperclip`
- Database container: `paperclip-postgres`
- Postgres is Docker-internal only on `paperclip-postgres:5432`
- Host port `5435` must not be listening or published
- Runtime volume: `paperclip_runtime`
- Container home: `/paperclip`
- Runtime config: `/paperclip/instances/default/config.json`
- Runtime volume ownership: `1000:1000`

Useful checks:

```bash
scripts/check-paperclip-health.sh
scripts/verify-postgres-backups.sh
scripts/verify-postgres-backups.sh --run
scripts/snapshot-rotate.sh
scripts/snapshot-rotate.sh --apply
```

`check-paperclip-health.sh` is read-only and verifies the container state, HTTP response, internal-only Postgres posture, runtime volume ownership, and normalized runtime config paths.

`verify-postgres-backups.sh` is read-only by default. Use `--run` when you explicitly want to execute `/opt/apiaries/backup-pg.sh` and require `DONE errors=0`.

`snapshot-rotate.sh` is a dry run by default. Use `--apply` only when intentionally deleting old matching snapshots. Fixed snapshots named `phoenix-paperclip-fixed-*.tar.gz` are protected unless `--include-fixed` is passed.

Operational guardrails:

- Do not restart or recreate production containers during routine health checks.
- Do not publish Paperclip Postgres on host port `5435`.
- Do not mount `/root/.paperclip` into the container.
- Do not put secrets in Git; use untracked `.env` files or host-managed secret injection.
- Rotate `BETTER_AUTH_SECRET` only during a maintenance window because it can invalidate sessions.

Recovery details are in [runbooks/paperclip-recovery-2026-04-28.md](runbooks/paperclip-recovery-2026-04-28.md).
