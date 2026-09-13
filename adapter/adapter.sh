#!/usr/bin/env bash
# GameOps adapter for Palworld.
# Contract: https://github.com/Reclyptor/GameOps/blob/master/docs/CONTRACT.md
# shellcheck shell=bash
# shellcheck disable=SC2034  # GAME_* and GAME_CMD are consumed by the toolkit

GAME_NAME=palworld
GAME_DIR=${GAME_DIR:-${DATA_DIR}}
GAME_PORT=${PORT:-8211}
GAME_PORT_PROTO=udp

: "${APPID:=2394010}"
: "${DEPOT:=2394012}"
: "${PLAYER_POLL_SECONDS:=5}"
: "${QUERY_PORT:=27015}"
: "${REST_API_ENABLED:=true}"
: "${REST_API_PORT:=8212}"
: "${RCON_ENABLED:=false}"
: "${RCON_PORT:=25575}"
: "${PUBLIC:=false}"
: "${MULTITHREADING:=false}"
: "${ENABLE_PERF_THREADING_ARGS:=false}"
: "${ENABLE_GAMEDATA_API:=false}"
: "${PALWORLD_ALLOW_NEGATIVE_DELTA_TIME:=false}"
: "${DISABLE_GENERATE_SETTINGS:=false}"
: "${DISABLE_GENERATE_ENGINE:=true}"

ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=adapter/lib/settings.sh
source "${ADAPTER_DIR}/lib/settings.sh"
# shellcheck source=adapter/lib/rest.sh
source "${ADAPTER_DIR}/lib/rest.sh"

SAVED_DIR="${DATA_DIR}/Pal/Saved"
CONFIG_DIR="${SAVED_DIR}/Config/LinuxServer"
SERVER_BINARY="${GAME_DIR}/Pal/Binaries/Linux/PalServer-Linux-Shipping"

pal_installed() {
    [[ -f "${GAME_DIR}/PalServer.sh" && -f "${GAME_DIR}/steamapps/appmanifest_${APPID}.acf" && -f "$SERVER_BINARY" ]]
}

# ── install / version / update ──────────────────────────────────────────────

game_install() {
    # Save, shutdown, announce and the player list all go through the REST
    # API, and the REST API refuses to work without an admin password.
    require_var ADMIN_PASSWORD "the REST API needs it (save, shutdown, player list)"
    is_true "$REST_API_ENABLED" || die "REST_API_ENABLED must be true: the toolkit controls the server through it"

    mkdir -p "$CONFIG_DIR" "${DATA_DIR}/logs"
    if ! pal_installed; then
        log_action "installing Palworld dedicated server (app ${APPID}) via SteamCMD"
        steam_install "$GAME_DIR" "$APPID" || return 1
        pal_installed || { log_error "SteamCMD finished but the server is not where it should be"; return 1; }
    fi
    chmod +x "${GAME_DIR}/PalServer.sh" "$SERVER_BINARY" 2>/dev/null || true

    if is_true "$DISABLE_GENERATE_SETTINGS"; then
        log_warn "DISABLE_GENERATE_SETTINGS=true: PalWorldSettings.ini is not rendered from the environment"
        [[ -s "${CONFIG_DIR}/PalWorldSettings.ini" ]] || cp "${GAME_DIR}/DefaultPalWorldSettings.ini" "${CONFIG_DIR}/PalWorldSettings.ini"
    else
        pal_render_settings "${ADAPTER_DIR}/templates/PalWorldSettings.ini.template" "${CONFIG_DIR}/PalWorldSettings.ini"
    fi
    if ! is_true "$DISABLE_GENERATE_ENGINE"; then
        pal_render_engine "${ADAPTER_DIR}/templates/Engine.ini.template" "${CONFIG_DIR}/Engine.ini"
    fi
}

# The Steam build id recorded by SteamCMD.
game_version() {
    local acf="${GAME_DIR}/steamapps/appmanifest_${APPID}.acf"
    [[ -r "$acf" ]] || { echo unknown; return; }
    awk '$1 == "\"buildid\"" { gsub(/"/, "", $2); print "build " $2; exit }' "$acf"
}

game_update_available() { steam_update_available "$GAME_DIR" "$APPID" "$DEPOT"; }
# The install dir is the data dir; the world under Pal/Saved must survive a
# staged reinstall (the toolkit's fallback when an in-place update fails).
game_update_apply()     { steam_install --keep Pal/Saved "$GAME_DIR" "$APPID"; }

# ── process ─────────────────────────────────────────────────────────────────

# The binary is launched directly rather than through PalServer.sh: the
# wrapper does not exec, so signals and the pid would land on a shell.
game_start_cmd() {
    GAME_CMD=("$SERVER_BINARY" Pal "-port=${GAME_PORT}" "-queryport=${QUERY_PORT}")
    is_true "$PUBLIC" && GAME_CMD+=(-publiclobby)
    if is_true "$ENABLE_PERF_THREADING_ARGS" || is_true "$MULTITHREADING"; then
        GAME_CMD+=(-useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS)
    fi
    if [[ -n "${WORKER_THREADS_SERVER:-}" ]]; then
        GAME_CMD+=("-NumberOfWorkerThreadsServer=${WORKER_THREADS_SERVER}")
    elif is_true "$MULTITHREADING"; then
        GAME_CMD+=("-NumberOfWorkerThreadsServer=$(nproc --all)")
    fi
    is_true "$ENABLE_GAMEDATA_API" && GAME_CMD+=(-enable-gamedata-api)
    is_true "$PALWORLD_ALLOW_NEGATIVE_DELTA_TIME" && GAME_CMD+=("-ini:Engine:[ConsoleVariables]:Pal.AllowNegativeDeltaTime=1")
    return 0
}

# The REST API answers only once the world is loaded.
game_ready() { pal_rest_get info >/dev/null 2>&1; }

game_healthy() {
    server_pid >/dev/null && flag_is_set ready && tcp_port_open 127.0.0.1 "$REST_API_PORT"
}

# Save, then ask the server to stop itself; a bare SIGTERM would not save.
game_shutdown() {
    pal_rest_post save >/dev/null 2>&1 || log_warn "pre-shutdown save failed"
    pal_rest_post shutdown '{"waittime":1,"message":"Server is shutting down."}' >/dev/null
}

# ── control ─────────────────────────────────────────────────────────────────

game_save() { pal_rest_post save >/dev/null; }

game_broadcast() {
    pal_rest_post announce "{\"message\":$(json_escape "$*")}" >/dev/null
}

game_players() {
    local json
    json=$(pal_rest_get players) || return 1
    pal_players_count "$json"
}

# ── events ──────────────────────────────────────────────────────────────────

game_events() { pal_events_loop; }

# ── backups ─────────────────────────────────────────────────────────────────

game_backup_paths() { echo Pal/Saved; }
