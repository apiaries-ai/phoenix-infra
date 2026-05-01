# Nextcloud stack

This stack is opt-in and is intentionally excluded from the default drift check.

Start it explicitly when Nextcloud is intended to run:

```bash
docker compose --profile nextcloud up -d
```

Without the `nextcloud` profile, Compose does not start this service and the
drift check will not treat the stopped container as a failure.
