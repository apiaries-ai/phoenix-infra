# Runbook — drift-check

## Purpose
Confirm that every always-on service declared in `stacks/*/docker-compose.yml`
is running on the Phoenix self-hosted runner. Profile-gated services are
intentionally excluded.

## Triggers
- `schedule:` cron in `.github/workflows/drift-check.yml`.
- Manual `workflow_dispatch` from the Actions tab. Optional `ignore` input
  accepts a comma-separated list of service names.

## Reading a failure

The script emits one of:
- `✅ Running as declared: <name>` — healthy.
- `❌ Declared but not running: <name>` — fail. Exit 1.
- `⚠️  Running but not declared: <name>` — informational. Exit 0 alone.

## Triage flow

1. Identify the offending service from the `❌` line.
2. Decide intent:
   - Service should be running → SSH to Phoenix and:
     ```bash
     cd /srv/phoenix/stacks/<name>
     docker compose up -d
     ```
   - Service is meant to be opt-in → add `profiles: ["<name>"]` to every
     service in that stack and open a PR.
   - Service is deprecated → remove the stack directory in a PR.
3. Re-run drift-check from the Actions tab and confirm green.

## Bypass for one run only

Dispatch the workflow with `ignore: <name>` to skip a known-stopped stack
for a single run without editing any files.

## Known opt-in stacks
- `nextcloud` — see `stacks/nextcloud/README.md`.

## Escalation
- Primary: @ericbien
- Secondary: Phoenix infra channel in the Apiaries workspace.
