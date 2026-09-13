#!/usr/bin/env bash
# Shared bats setup: source the toolkit shim and the adapter against a
# throwaway DATA_DIR, with curl (the REST API client) replaced by a shim and
# the Steam helpers stubbed, so no test touches the network or Steam.
# shellcheck shell=bash
# shellcheck disable=SC2034

setup_adapter() {
    TEST_TMP=$(mktemp -d)
    export GAMEOPS_HOME=/opt/gameops
    export GAMEOPS_STATE="$TEST_TMP/state"
    export DATA_DIR="$TEST_TMP/data"
    export BACKUP_DIR="$TEST_TMP/backups"
    export GAME_ADAPTER=/opt/game/adapter.sh
    export LOG_LEVEL=warn
    export ADMIN_PASSWORD=test-admin
    unset GAME_DIR
    mkdir -p "$GAMEOPS_STATE" "$DATA_DIR" "$BACKUP_DIR" "$TEST_TMP/bin"

    export CURL_LOG="$TEST_TMP/curl.log"
    : > "$CURL_LOG"
    cat > "$TEST_TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
[[ -n "${CURL_STUB_FILE:-}" ]] && cat "$CURL_STUB_FILE"
exit "${CURL_STUB_EXIT:-0}"
SH
    chmod +x "$TEST_TMP/bin/curl"
    export PATH="$TEST_TMP/bin:$PATH"

    # shellcheck source=/dev/null
    source "${GAMEOPS_HOME}/shim/adapter.sh"
    adapter_load
    stub_steam
}

teardown_adapter() { rm -rf "$TEST_TMP"; }

fixture() { cat "/tests/fixtures/$1"; }

# Replace the Steam helpers: record install calls; answer update checks with
# STEAM_STUB_REMOTE (an update) or nothing (current).
stub_steam() {
    export STEAM_LOG="$TEST_TMP/steam.log"
    : > "$STEAM_LOG"
    # shellcheck disable=SC2317,SC2329  # invoked by the adapter under test
    steam_install() {
        printf 'install %s\n' "$*" >> "$STEAM_LOG"
        return "${STEAM_STUB_EXIT:-0}"
    }
    # shellcheck disable=SC2317,SC2329
    steam_update_available() {
        printf 'update-check %s\n' "$*" >> "$STEAM_LOG"
        [[ -n "${STEAM_STUB_REMOTE:-}" ]] || return 1
        printf '%s' "$STEAM_STUB_REMOTE"
    }
}

# Lay down the files that make pal_installed true.
fake_install() {
    mkdir -p "$DATA_DIR/Pal/Binaries/Linux" "$DATA_DIR/steamapps"
    printf '#!/bin/sh\n' > "$DATA_DIR/PalServer.sh"
    printf '#!/bin/sh\n' > "$DATA_DIR/Pal/Binaries/Linux/PalServer-Linux-Shipping"
    cp /tests/fixtures/appmanifest_2394010.acf "$DATA_DIR/steamapps/"
}
