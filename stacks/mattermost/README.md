# Mattermost

Defined in `../apiaries-trunk/docker-compose.yml` under the `mattermost` service.

- Image: `mattermost/mattermost-team-edition:10.5`
- Port: `8065`
- Site URL: https://chat.apiaries.ai
- Data: `/opt/apiaries-trunk/mattermost/`
- DB: `hive-db:5432/mattermost` (uses `${DB_PASSWORD}`)
