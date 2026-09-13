#!/usr/bin/env bats
load test_helper

setup()    { setup_adapter; }
teardown() { teardown_adapter; }

@test "player names exclude players still loading" {
    [ "$(pal_players_names "$(fixture players.json)" | tr '\n' '|')" = "Alice|Bob Builder|" ]
}

@test "player count includes everyone connected" {
    [ "$(pal_players_count "$(fixture players.json)")" = 4 ]
    [ "$(pal_players_count '{"players":[]}')" = 0 ]
}

@test "diffing sorted lists yields JOIN and LEAVE" {
    printf 'Alice\nCarol\n' > "$TEST_TMP/old"
    printf 'Alice\nBob Builder\n' > "$TEST_TMP/new"
    [ "$(pal_diff_events "$TEST_TMP/old" "$TEST_TMP/new" | tr '\n' '|')" = "JOIN Bob Builder|LEAVE Carol|" ]
    : > "$TEST_TMP/empty"
    [ -z "$(pal_diff_events "$TEST_TMP/empty" "$TEST_TMP/empty")" ]
}

@test "game_players goes through the REST API with basic auth" {
    export CURL_STUB_FILE=/tests/fixtures/players.json
    [ "$(game_players)" = 4 ]
    grep -c -- '-u admin:test-admin' "$CURL_LOG" >/dev/null
    grep -c 'http://127.0.0.1:8212/v1/api/players' "$CURL_LOG" >/dev/null
}

@test "backup paths" {
    [ "$(game_backup_paths)" = "Pal/Saved" ]
}
