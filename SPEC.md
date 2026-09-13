# SPEC: Palworld — a self-contained dedicated server image

**Status:** IMPLEMENTED — v1.
**Drafted:** 2026-09-12
**Deliverable:** `ghcr.io/reclyptor/palworld`, built on [GameOps](https://github.com/Reclyptor/GameOps).

---

## 1. Purpose

Run a Palworld dedicated server as a single container that looks after itself: scheduled backups
with retention, automatic updates that warn players in-game and relaunch without the container
exiting, Discord notifications for lifecycle and player events, a saving shutdown, and a
configuration surface where every world setting is an environment variable. Everything operational
comes from the GameOps toolkit; this repo contributes only what is Palworld-specific.

### Non-goals
- **No autopause, no arm64, no beta branches.** The image runs the current public build on x86-64.
- **No RCON-driven control.** RCON can be enabled for operators (`RCON_ENABLED`), but the toolkit
  uses the REST API for everything.
- **No settings UI.** The environment is the source of truth for `PalWorldSettings.ini`.

---

## 2. Hard constraints

| # | Constraint |
|---|---|
| P1 | **Never start as root.** uid/gid `1000:1000` (`steam`) from the first instruction; SteamCMD runs as that user with `HOME=/home/steam`. |
| P2 | **One variable per world setting, with the game's default**, named by the shared GameOps vocabulary where one exists (`SERVER_NAME`, `MAX_PLAYERS`, `GAME_PASSWORD`, `PUBLIC`, `PORT`); no aliases. |
| P3 | **Stop means save.** A bare `SIGTERM` does not save a Palworld world; every stop goes REST `save` → REST `shutdown`. |
| P4 | **`ADMIN_PASSWORD` is mandatory.** The REST API refuses without it, and the REST API is the only control channel. The image fails fast rather than running unmanageable. |
| P5 | **The binary is launched directly.** `PalServer.sh` does not `exec`; running it would put the pid and signals on a shell wrapper. |
| P6 | **SteamCMD is installed by this image**, into `/home/steam/steamcmd`, and self-updated once at build so the first start goes straight to the game download. |

---

## 3. The image

`debian:trixie-slim` with the i386 architecture enabled for SteamCMD (`lib32gcc-s1`,
`lib32stdc++6`), `procps` and `curl` for the toolkit, `gettext-base` for envsubst, and the runtime
libraries the Unreal dedicated server links (`libicu76`, `libsdl3-0`, `xdg-user-dirs`). The game is
not in the image: SteamCMD installs app `2394010` into `/data` on first start and updates it in place.

| Path | Contents |
|---|---|
| `/data` | The server install (`GAME_DIR` = `DATA_DIR`); `Pal/Saved` is the world |
| `/backups` | Archives of `Pal/Saved` |
| `/home/steam/steamcmd` | SteamCMD (`STEAMCMD_DIR`) |
| `/opt/gameops` | The toolkit |
| `/opt/game` | This adapter |

## 4. The adapter

| Contract function | Palworld implementation |
|---|---|
| `game_install` | Require `ADMIN_PASSWORD` and the REST API; SteamCMD install when `PalServer.sh` + manifest + binary are absent; render `PalWorldSettings.ini` (and `Engine.ini` on request). |
| `game_version` | The Steam `buildid` from `appmanifest_2394010.acf`. |
| `game_update_available` | `steam_update_available` — depot `2394012` manifest vs `api.steamcmd.net`. |
| `game_update_apply` | `steam_install` (validate). |
| `game_start_cmd` | `PalServer-Linux-Shipping Pal -port -queryport [-publiclobby] [perf threads] […]`. |
| `game_ready` / `game_healthy` | REST `/info` answers; process + ready + REST port. |
| `game_save` / `game_broadcast` / `game_players` | REST `save` / `announce` / `players` count. |
| `game_shutdown` | REST `save`, then REST `shutdown` with a 1 s wait. |
| `game_events` | Poll REST `players` every `PLAYER_POLL_SECONDS`, diff loaded players, emit `JOIN`/`LEAVE`. |
| `game_backup_paths` | `Pal/Saved`. |

## 5. Verification

- `tests/*.bats` inside the built image: settings and engine rendering (quoting, defaults,
  overrides, `MAX_PLAYERS`/`GAME_PASSWORD`/advertised address), start-command flags, REST calls (auth, endpoints, JSON bodies),
  player-list parsing and diffing, install detection, build id, Steam manifest comparison.
- `tests/smoke.sh`: real SteamCMD install, REST readiness, `players` = 0, an announce, backup
  archive holds `Pal/Saved`, live update check, `docker stop` exits 0 with a save first.
