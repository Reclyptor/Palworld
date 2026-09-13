#!/usr/bin/env bats
load test_helper

setup()    { setup_adapter; }
teardown() { teardown_adapter; }

@test "save posts to /save" {
    game_save
    grep -c -- '-X POST' "$CURL_LOG" >/dev/null
    grep -c 'http://127.0.0.1:8212/v1/api/save' "$CURL_LOG" >/dev/null
}

@test "broadcast posts a JSON message to /announce" {
    game_broadcast 'Restarting in 5 "minutes"'
    grep -c -- '--data {"message":"Restarting in 5 \\"minutes\\""} http://127.0.0.1:8212/v1/api/announce' "$CURL_LOG" >/dev/null
}

@test "shutdown saves first then asks the server to stop" {
    game_shutdown
    [ "$(grep -c 'v1/api/save' "$CURL_LOG")" -eq 1 ]
    grep -c -- '--data {"waittime":1,"message":"Server is shutting down."} http://127.0.0.1:8212/v1/api/shutdown' "$CURL_LOG" >/dev/null
    [[ "$(sed -n '1p' "$CURL_LOG")" == *save* ]]
}

@test "ready means /info answers" {
    export CURL_STUB_FILE=/tests/fixtures/info.json
    game_ready
    export CURL_STUB_EXIT=7
    ! game_ready
}

@test "REST failures propagate as non-zero" {
    export CURL_STUB_EXIT=22
    run game_save
    [ "$status" -ne 0 ]
    run game_players
    [ "$status" -ne 0 ]
}
