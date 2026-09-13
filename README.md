# Palworld

A self-contained Palworld dedicated server image with scheduled backups, in-place auto-updates that
warn players first, Discord notifications, player join/leave events and a graceful, saving shutdown.
Every world setting is an environment variable. Built on the
[GameOps](https://github.com/Reclyptor/GameOps) toolkit.

```sh
mkdir -p data backups && sudo chown -R 1000:1000 data backups
docker run -d --name palworld -p 8211:8211/udp -p 27015:27015/udp \
  -e SERVER_NAME="My Palworld Server" -e MAX_PLAYERS=16 \
  -e GAME_PASSWORD=secret -e ADMIN_PASSWORD=secret2 -e DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/… \
  -v "$PWD/data:/data" -v "$PWD/backups:/backups" \
  ghcr.io/reclyptor/palworld:latest
```

Or use [`compose.yaml`](compose.yaml). The first start installs the dedicated server (several GB)
through SteamCMD into `/data`; a `/data` that already holds a server install and `Pal/Saved` is
picked up as is.

## What it does for you

| | |
|---|---|
| **Backups** | Nightly by default: a REST `save`, then `Pal/Saved` into `/backups/palworld-<timestamp>.tar.gz`, pruned after `BACKUP_RETAIN_DAYS`. `docker exec palworld gameops backup` any time. |
| **Updates** | Hourly check of the Steam depot manifest. When a build lands: players are told in-game at 15/10/5/2/1 min, a backup is taken, the world is saved, SteamCMD updates in place, and the server relaunches **inside the same container**. `UPDATE_ON_BOOT` covers the first start. |
| **Notifications** | Discord: online, offline, crashed, updating/updated, backup, join, leave. Plain text, every message overridable. |
| **Lifecycle** | Stop = REST `save` + REST `shutdown`, never a bare signal (Palworld does not save on `SIGTERM`). Crashes exit the container with the game's code. |

## Configuration

### Palworld

The REST API is how the toolkit saves, stops, counts and announces, so it is always on and
**`ADMIN_PASSWORD` is required**.

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_NAME` | `Palworld` | The in-game server name, and the name every Discord message uses. |
| `SERVER_DESCRIPTION` | — | |
| `MAX_PLAYERS` | `32` | Max players. |
| `GAME_PASSWORD` | — | Join password. |
| `ADMIN_PASSWORD` | **required** | REST API / RCON / in-game admin. |
| `PUBLIC` | `false` | List on the community server browser (`-publiclobby`; needs `ADVERTISED_IP`/`ADVERTISED_PORT`). |
| `MULTITHREADING` | `false` | `-useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS` plus worker threads = CPU count. |
| `ENABLE_PERF_THREADING_ARGS` / `WORKER_THREADS_SERVER` | `false` / — | The same, separately. |
| `ENABLE_GAMEDATA_API` | `false` | |
| `DISABLE_GENERATE_SETTINGS` | `false` | `true` leaves `PalWorldSettings.ini` alone. |
| `DISABLE_GENERATE_ENGINE` | `true` | `false` renders `Engine.ini` (tick rates, bandwidth). |
| `PLAYER_POLL_SECONDS` | `5` | Player-list poll interval for join/leave events. |
| `PORT` / `QUERY_PORT` | `8211` / `27015` | UDP. |
| `ADVERTISED_IP` / `ADVERTISED_PORT` | — / `8211` | The address the community browser shows (`PublicIP`/`PublicPort`). |
| `RCON_ENABLED` / `RCON_PORT` | `false` / `25575` | Optional; the REST API is used for everything. |
| `REST_API_PORT` | `8212` | Loopback only; never publish it. |

### Palworld world settings

Every `OptionSettings` entry of `PalWorldSettings.ini` is an environment variable with the game's
default: `DIFFICULTY`, `EXP_RATE`, `PAL_CAPTURE_RATE`, `DEATH_PENALTY`, `IS_PVP`, `HARDCORE`,
`AUTO_SAVE_SPAN`, `BASE_CAMP_MAX_NUM`, `CROSSPLAY_PLATFORMS`, … — the full list with defaults is
[`adapter/lib/settings.sh`](adapter/lib/settings.sh) and it maps one-to-one onto
[`adapter/templates/PalWorldSettings.ini.template`](adapter/templates/PalWorldSettings.ini.template).
Booleans are `True`/`False` as the game expects. Engine tuning (`NET_SERVER_MAX_TICK_RATE`,
`MAX_CLIENT_RATE`, …) is rendered only with `DISABLE_GENERATE_ENGINE=false`.

**The environment is the source of truth**: `PalWorldSettings.ini` is re-rendered on every start.

### Backups, updates, notifications

These are the [GameOps](https://github.com/Reclyptor/GameOps#configuration) variables and are
identical across every Reclyptor game image: `BACKUP_CRON`, `BACKUP_RETAIN_DAYS`,
`BACKUP_ON_UPDATE`, `UPDATE_CRON`, `UPDATE_ON_BOOT`, `UPDATE_WARN_MINUTES`,
`UPDATE_SKIP_IF_PLAYERS`, `STOP_TIMEOUT`, `METRICS_PORT`, `DISCORD_WEBHOOK_URL`,
`DISCORD_<EVENT>_MESSAGE`, `TZ`, … Backups are verified as they are written; `gameops backup list`,
`gameops backup verify latest` and `gameops restore latest` work from `docker exec`.

## Volumes and ports

| | |
|---|---|
| `/data` | The server install and `Pal/Saved` — uid/gid **1000** |
| `/backups` | Archives. Mount a NAS share here for off-box copies. |
| `8211/udp` | Game |
| `27015/udp` | Steam query |
| `9110/tcp` | `/metrics` (Prometheus) and `/healthz` — `METRICS_PORT`, `0` disables |

## Development

```sh
tests/run.sh      # bats, inside the built image
tests/smoke.sh    # real server: SteamCMD install → REST → backup → live update check → saving stop
```

## License

MIT.
