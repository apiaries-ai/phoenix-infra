# Paperclip Recovery Runbook — 2026-04-28

## Final state

Phoenix Paperclip was recovered and verified operational.

```text
paperclip               Up                  0.0.0.0:3100->3100/tcp
paperclip-postgres      Up healthy          5432/tcp
HTTP                    HTTP/1.1 200 OK
Host DB port 5435       NOT listening
Backup script           DONE errors=0
Snapshot                /opt/apiaries/snapshots/phoenix-paperclip-fixed-20260428-1255.tar.gz
```

## Working architecture

- Host: `phoenix-lan` / `phoenix-01-r7920`
- App container: `paperclip`
- DB container: `paperclip-postgres`
- App URL on host: `http://127.0.0.1:3100`
- Postgres: Docker-internal only, `paperclip-postgres:5432`
- Host port `5435`: removed; should not be listening
- Runtime volume: `paperclip_runtime`
- Runtime mount: `/paperclip`
- Runtime config: `/paperclip/instances/default/config.json`
- Runtime UID/GID ownership: `1000:1000`

## Root cause

Paperclip initially failed after the DB hardening because the container does not use `/root/.paperclip` as its home. Diagnostics showed:

```text
HOME=/paperclip
PAPERCLIP_HOME=/paperclip
PAPERCLIP_CONFIG=/paperclip/instances/default/config.json
uid=1000(node) gid=1000(node)
```

The image also contained a fallback `/app/.env` with:

```text
DATABASE_URL=postgres://paperclip:<redacted>@127.0.0.1:5432/paperclip
```

When the runtime config was not mounted at `/paperclip`, Paperclip fell back to the embedded/default local Postgres path and failed with `ECONNREFUSED 127.0.0.1:5432`.

After mounting config correctly, Paperclip then failed with:

```text
EACCES: permission denied, mkdir '/root/.paperclip/instances/default/logs'
```

That was because paths inside `config.json` still referenced host paths. Rewriting `/root/.paperclip` to `/paperclip` fixed logging, storage, and secret path resolution.

## Final docker-compose shape

The final compose should use an internal Postgres service, no `5435:5432` host port mapping, and mount `paperclip_runtime` at `/paperclip`.

```yaml
services:
  postgres:
    image: postgres:17
    container_name: paperclip-postgres
    environment:
      POSTGRES_USER: paperclip
      POSTGRES_PASSWORD: ${PAPERCLIP_POSTGRES_PASSWORD}
      POSTGRES_DB: paperclip
    command: ["postgres", "-c", "listen_addresses=*", "-c", "unix_socket_directories="]
    volumes:
      - paperclip_pgdata:/var/lib/postgresql/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -p 5432 -U paperclip || exit 1"]
      interval: 5s
      timeout: 5s
      retries: 20
      start_period: 10s

  paperclip:
    image: paperclip-server:latest
    container_name: paperclip
    privileged: true
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      NODE_ENV: production
      PORT: "3100"
      SERVE_UI: "true"
      PAPERCLIP_HOME: /paperclip
      PAPERCLIP_CONFIG: /paperclip/instances/default/config.json
      DATABASE_URL: postgres://paperclip:${PAPERCLIP_POSTGRES_PASSWORD}@paperclip-postgres:5432/paperclip
    ports:
      - "3100:3100"
    restart: unless-stopped
    volumes:
      - paperclip_runtime:/paperclip

volumes:
  paperclip_pgdata:
  paperclip_runtime:
    external: true
```

## Critical runtime config normalization

Run this only when the runtime volume/config needs repair.

```bash
RUNTIME_VOL=$(docker volume inspect paperclip_runtime -f "{{ .Mountpoint }}")
CFG="$RUNTIME_VOL/instances/default/config.json"

cp "$CFG" "$CFG.bak.$(date +%s)"
sed -i "s|/root/.paperclip|/paperclip|g" "$CFG"
sed -i "s|172.17.0.1:5435|paperclip-postgres:5432|g" "$CFG"

mkdir -p "$RUNTIME_VOL/instances/default/logs"
mkdir -p "$RUNTIME_VOL/instances/default/data/storage"
mkdir -p "$RUNTIME_VOL/instances/default/secrets"

chown -R 1000:1000 "$RUNTIME_VOL"
chmod -R u+rwX "$RUNTIME_VOL"
```

## Verification commands

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep paperclip
curl -sI --max-time 10 http://127.0.0.1:3100 | head -5
ss -tlnp | grep 5435 || echo "5435 NOT listening"
/opt/apiaries/backup-pg.sh 2>&1 | tail -20
```

Expected:

```text
paperclip               Up ...
paperclip-postgres      Up ... healthy
HTTP/1.1 200 OK
5435 NOT listening
DONE errors=0
```

## Backup status

The multi-container backup script succeeded after Paperclip recovery:

```text
START pg_dump paperclip-postgres
OK paperclip-postgres
START pg_dump hive-db
OK hive-db
START pg_dump langfuse-pg
OK langfuse-pg
START pg_dumpall apiaries_db
OK apiaries_db
START pg_dumpall authentik-db
OK authentik-db
DONE errors=0
```

Backup folder example:

```text
/opt/apiaries/backups/postgres/20260428-125443
```

## Snapshot

Fixed-state snapshot:

```text
/opt/apiaries/snapshots/phoenix-paperclip-fixed-20260428-1255.tar.gz
```

Observed size: `204M`.

## Do not repeat

- Do not mount `/root/.paperclip` into `/root/.paperclip` for this container.
- Do not use `paperclip_paperclip-data:/paperclip` unless it contains the corrected config and secrets.
- Do not publish Postgres on host port `5435`.
- Do not commit Paperclip database or auth secret values to this repo.
- Do not run bash heredocs directly in fish on the Mac. Run heredocs inside SSH/bash or use `ssh host 'cat > file << "EOF" ... EOF'` carefully.
- Do not override the image entrypoint to `/app/packages/server/dist/index.js`; the image CMD expects `server/dist/index.js` with the tsx loader.

## Remaining hardening

- Off-host copy snapshot to Mac or object storage.
- Rotate `BETTER_AUTH_SECRET` during maintenance window; this may invalidate sessions.
- Commit `/opt/paperclip/docker-compose.yml` into the local repo if not already committed.
- Add a small health check script for Paperclip to Phoenix monitoring.
