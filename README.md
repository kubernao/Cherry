# Cherry

Cherry is a personal Notion-style workspace built with Phoenix LiveView, Ecto, and SQLite. The first release focuses on projects, kanban tasks, Markdown notes, search, an authenticated JSON API, and a CLI for agent workflows.

## Local Setup

```sh
mix setup
mix phx.server
```

Open [localhost:4000](http://localhost:4000).

The seed script creates the owner account and prints an initial API token:

```txt
email: owner@example.com
password: change-me-now!
```

Override those before setup when needed:

```sh
OWNER_EMAIL=you@example.com OWNER_PASSWORD='a-long-private-password' mix ecto.setup
```

## CLI

Build the CLI executable:

```sh
mix escript.build
```

Save API credentials:

```sh
./cherry auth login --url http://localhost:4000 --token TOKEN
```

Common commands:

```sh
./cherry projects list
./cherry projects create --title "Website rebuild" --description "Markdown notes"
./cherry tasks list --project PROJECT_ID
./cherry tasks create --project PROJECT_ID --title "Draft scope" --tags "writing,client"
./cherry tasks move TASK_ID --column COLUMN_ID --position 0
./cherry tasks done TASK_ID
./cherry search "scope" --json
./cherry activity
```

Use `--json` on read/write commands when agents need machine-readable output. CLI config is stored at `~/.config/cherry/config.json`; tests and automation can override it with `CHERRY_CONFIG_PATH`.

## API

All API routes live under `/api/v1` and require `Authorization: Bearer TOKEN`.

- `GET/POST /projects`
- `GET /projects/:id`
- `POST /projects/:id/archive`
- `GET/POST /tasks`
- `GET/PATCH /tasks/:id`
- `POST /tasks/:id/move`
- `POST /tasks/:id/done`
- `POST /tasks/:id/archive`
- `GET /search?q=term`
- `GET /activity`

Stable errors use:

```json
{"error":{"code":"validation_failed","fields":{}}}
```

## Deployment

Cherry is designed for a single persistent-volume host such as a VPS or Fly.io volume.

Required production environment:

```sh
PHX_SERVER=true
PHX_HOST=your.domain
SECRET_KEY_BASE=$(mix phx.gen.secret)
DATABASE_PATH=/data/cherry.db
```

SQLite runs with WAL enabled. Mount a persistent disk at the directory containing `DATABASE_PATH`.

Create backups with:

```sh
BACKUP_DIR=/data/backups MIX_ENV=prod mix cherry.backup
```

Schedule that command daily with cron, systemd timers, or the platform scheduler.

Health checks can use:

```sh
curl https://your.domain/health
```

## Verification

```sh
mix test
mix assets.build
mix escript.build
```
