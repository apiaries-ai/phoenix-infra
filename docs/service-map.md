# Phoenix Service Map — Canonical Source of Truth
# Last verified: mixed; Paperclip updated 2026-04-28

| Container | Image | Port | Stack Dir | Tunnel Hostname | Notes |
|---|---|---|---|---|---|
| paperclip | paperclip-server:latest | 3100 | stacks/paperclip | paperclip.apiaries.ai | CEO agent host |
| paperclip-postgres | postgres:17 | internal-only 5432/tcp | stacks/paperclip | — | no host 5435 publish |
| n8n | n8nio/n8n | 5678 | stacks/n8n | n8n.apiaries.ai | |
| langfuse-v3 | langfuse/langfuse | 3201 | stacks/langfuse | langfuse.apiaries.ai | |
| langfuse-pg | postgres | — | stacks/langfuse | — | |
| langfuse-redis | redis | — | stacks/langfuse | — | |
| langfuse-clickhouse | clickhouse | — | stacks/langfuse | — | |
| langfuse-minio | minio | — | stacks/langfuse | — | |
| litellm-proxy | ghcr.io/berriai/litellm | 4001 | stacks/litellm | litellm.apiaries.ai | |
| hermes-agent | ? | 8181 | stacks/hermes | hermes.apiaries.ai | VERIFY image |
| cloudflared | cloudflare/cloudflared | — | stacks/cloudflared | tunnel 3fbbb23d | token-mode |
| authentik-server | ghcr.io/goauthentik/server | 9000 | stacks/authentik | auth.apiaries.ai |  |
| authentik-worker | ghcr.io/goauthentik/server | — | stacks/authentik | — | |
| authentik-db | postgres | — | stacks/authentik | — | |
| authentik-redis | redis | — | stacks/authentik | — | |
| mattermost | mattermost/mattermost | 8065 | stacks/mattermost | chat.apiaries.ai | |
| hive-db | postgres | — | stacks/hive | — | shared DB |
| nextcloud | nextcloud | 8888 | stacks/nextcloud | cloud.apiaries.ai | |
| ebee-api | ? | 8010 | stacks/ebee | api.apiaries.ai | VERIFY |
| apiaries-frontend | ? | 8090 | stacks/apiaries-web | apiaries.ai, www, app | |
| apiaries-backend | ? | — | stacks/apiaries-web | — | |
| apiaries_db | postgres | — | stacks/apiaries-web | — | |
| apiaries_frontend | ? | — | stacks/apiaries-web | — | DUPLICATE? verify vs apiaries-frontend |
| apiaries_crm | ? | 8003 | stacks/crm | crm.apiaries.ai | |
| apiaries_memory_agent | ? | — | stacks/memory | — | |
| stalwart | stalwart-labs/stalwart | 443 | stacks/stalwart | webmail.apiaries.ai | noTLSVerify |
