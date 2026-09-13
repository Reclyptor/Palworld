#!/usr/bin/env bats
load test_helper

setup()    { setup_adapter; }
teardown() { teardown_adapter; }

@test "install detection needs the script, the manifest and the binary" {
    ! pal_installed
    fake_install
    pal_installed
    rm "$DATA_DIR/steamapps/appmanifest_2394010.acf"
    ! pal_installed
}

@test "game_install runs SteamCMD only when not installed" {
    run game_install
    [ "$status" -eq 1 ]
    grep -c "install $DATA_DIR 2394010" "$STEAM_LOG" >/dev/null
    fake_install
    : > "$STEAM_LOG"
    game_install
    [ ! -s "$STEAM_LOG" ]
}

@test "version is the Steam build id" {
    [ "$(game_version)" = unknown ]
    fake_install
    [ "$(game_version)" = "build 13378465" ]
}

@test "update detection delegates the depot manifest check to the toolkit" {
    fake_install
    export STEAM_STUB_REMOTE=111222333444
    run game_update_available
    [ "$status" -eq 0 ]
    [ "$output" = 111222333444 ]
    grep -c "update-check $DATA_DIR 2394010 2394012" "$STEAM_LOG" >/dev/null
    unset STEAM_STUB_REMOTE
    run game_update_available
    [ "$status" -eq 1 ]
}

@test "update apply reinstalls through SteamCMD" {
    fake_install
    game_update_apply 111
    grep -c "install --keep Pal/Saved $DATA_DIR 2394010" "$STEAM_LOG" >/dev/null
}
