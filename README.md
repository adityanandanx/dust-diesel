# Dust Diesel

`Dust Diesel` is a Godot 4.6 vehicle-combat project with optional online multiplayer via Nakama.

## Prerequisites

Install these tools first:

- Godot Engine `4.6` (or a compatible `4.x` build)
- Docker + Docker Compose (for Nakama/CockroachDB local backend)
- Optional: `git`

## Local Setup

1. Clone and enter the project:

```bash
git clone https://github.com/adityanandanx/dust-diesel
cd dust_diesel
```

2. Start backend services:

```bash
docker compose up -d
```

This starts:

- CockroachDB on `26257` (admin UI on `8080`)
- Nakama on `7350` (HTTP API), `7351` (gRPC), `7349` (console)
- Prometheus on `9090`

3. Open the project in Godot:

- Launch Godot.
- Import/open this folder (`dust_diesel`) using `project.godot`.
- Run the project (main scene is `scenes/ui/MainMenu.tscn`).

## Multiplayer Backend Notes

The game autoloads `NakamaManager` and defaults to `127.0.0.1:7350`.

You can point to a different Nakama host with:

```bash
NAKAMA_HOST=<host-or-ip> godot4 --path .
```

Example:

```bash
NAKAMA_HOST=192.168.1.100 godot4 --path .
```

## Stop Backend Services

```bash
docker compose down
```

To also remove the DB volume:

```bash
docker compose down -v
```

## Troubleshooting

- If authentication fails at startup, verify Nakama is running:

```bash
docker compose ps
```

- If port conflicts occur, stop conflicting services or adjust `docker-compose.yml` ports.
- If the project opens but rendering/physics behaves unexpectedly, confirm you are using a Godot build compatible with features in `project.godot` (`4.6`, Jolt physics).
