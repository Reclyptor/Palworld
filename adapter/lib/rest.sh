#!/usr/bin/env bash
# The server's REST API (127.0.0.1:${REST_API_PORT}/v1/api/*, basic auth
# admin:${ADMIN_PASSWORD}) and the player-list diffing built on it. The API
# needs authenticated POSTs, so this is the one place the image uses curl.
# shellcheck shell=bash

pal_rest_url() { printf 'http://127.0.0.1:%s/v1/api/%s' "$REST_API_PORT" "$1"; }

pal_rest_get() {
    curl -sfS --connect-timeout 5 --max-time 20 -u "admin:${ADMIN_PASSWORD}" \
        -H 'Accept: application/json' "$(pal_rest_url "$1")"
}

# pal_rest_post <api> [json]
pal_rest_post() {
    curl -sfS --connect-timeout 5 --max-time 30 -u "admin:${ADMIN_PASSWORD}" \
        -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
        --data "${2:-}" "$(pal_rest_url "$1")"
}

# A player still loading or in character creation has playerId "None" or all
# zeros; they are reported once they are actually in the world.
pal_player_loaded() {
    local id=$1
    [[ -n "$id" && "$id" != None && ! "$id" =~ ^0+$ ]]
}

# Names of players that have finished loading, sorted.
pal_players_names() {
    local json=$1 i=0 name id
    while name=$(printf '%s' "$json" | json_get - ".players[$i].name" 2>/dev/null); do
        id=$(printf '%s' "$json" | json_get - ".players[$i].playerId" 2>/dev/null) || id=""
        pal_player_loaded "$id" && printf '%s\n' "$name"
        (( i++ ))
    done | sort
}

# Everyone the server reports, loading or not — the number that matters for
# "is anyone here" decisions.
pal_players_count() {
    local json=$1 i=0
    while printf '%s' "$json" | json_get - ".players[$i].name" >/dev/null 2>&1; do
        (( i++ ))
    done
    printf '%s' "$i"
}

# pal_diff_events <old-sorted-file> <new-sorted-file> → JOIN/LEAVE lines
pal_diff_events() {
    local old=$1 new=$2 name
    while IFS= read -r name; do [[ -n "$name" ]] && printf 'JOIN %s\n' "$name"; done < <(comm -13 "$old" "$new")
    while IFS= read -r name; do [[ -n "$name" ]] && printf 'LEAVE %s\n' "$name"; done < <(comm -23 "$old" "$new")
    return 0
}

# Poll the player list for as long as the server lives.
pal_events_loop() {
    local prev="" cur="" json
    prev=$(mktemp) cur=$(mktemp)
    trap 'rm -f "$prev" "$cur"' RETURN
    while server_pid >/dev/null; do
        if json=$(pal_rest_get players 2>/dev/null); then
            pal_players_names "$json" > "$cur"
            pal_diff_events "$prev" "$cur"
            mv "$cur" "$prev"; cur=$(mktemp)
        fi
        sleep "$PLAYER_POLL_SECONDS"
    done
}
