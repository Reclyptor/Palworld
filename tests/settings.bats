#!/usr/bin/env bats
load test_helper

setup()    { setup_adapter; }
teardown() { teardown_adapter; }

@test "renders PalWorldSettings.ini with quoted strings, defaults and overrides" {
    export SERVER_NAME="Test Pals" SERVER_DESCRIPTION="friends only" GAME_PASSWORD=example-pass \
           EXP_RATE=2.000000 IS_PVP=True RCON_ENABLED=true REST_API_ENABLED=true REST_API_PORT=8212
    pal_render_settings /opt/game/templates/PalWorldSettings.ini.template "$TEST_TMP/PalWorldSettings.ini"
    local ini; ini=$(cat "$TEST_TMP/PalWorldSettings.ini")
    [ "$(head -1 "$TEST_TMP/PalWorldSettings.ini")" = "[/Script/Pal.PalGameWorldSettings]" ]
    [ "$(wc -l < "$TEST_TMP/PalWorldSettings.ini")" -eq 2 ]
    [[ "$ini" == *'ServerName="Test Pals",'* ]]
    [[ "$ini" == *'ServerDescription="friends only",'* ]]
    [[ "$ini" == *'ServerPassword="example-pass",'* ]]
    [[ "$ini" == *'AdminPassword="test-admin",'* ]]
    [[ "$ini" == *'ExpRate=2.000000,'* ]]
    [[ "$ini" == *'bIsPvP=True,'* ]]
    [[ "$ini" == *'RESTAPIEnabled=true,'* ]]
    [[ "$ini" == *'RESTAPIPort=8212,'* ]]
    # untouched settings keep their defaults
    [[ "$ini" == *'Difficulty=None,'* ]]
    [[ "$ini" == *'ServerPlayerMaxNum=32,'* ]]
    [[ "$ini" == *'CrossplayPlatforms=(Steam,Xbox,PS5,Mac),'* ]]
    [[ "$ini" == *'BanListURL="https://b.palworldgame.com/api/banlist.txt",'* ]]
    [[ "$ini" == *'BuildingNameDisplayCacheTTLSeconds=60)' ]]
    # no placeholder survived
    [[ "$ini" != *'$'* ]]
}

@test "MAX_PLAYERS, GAME_PASSWORD and the advertised address reach the ini" {
    export MAX_PLAYERS=16 GAME_PASSWORD=joinme ADVERTISED_IP=203.0.113.5 ADVERTISED_PORT=9211
    pal_render_settings /opt/game/templates/PalWorldSettings.ini.template "$TEST_TMP/s.ini"
    local ini; ini=$(cat "$TEST_TMP/s.ini")
    [[ "$ini" == *'ServerPlayerMaxNum=16,'* ]]
    [[ "$ini" == *'ServerPassword="joinme",'* ]]
    [[ "$ini" == *'PublicIP="203.0.113.5",'* ]]
    [[ "$ini" == *'PublicPort=9211,'* ]]
}

@test "renders Engine.ini" {
    export NET_SERVER_MAX_TICK_RATE=60
    pal_render_engine /opt/game/templates/Engine.ini.template "$TEST_TMP/Engine.ini"
    grep -c '^NetServerMaxTickRate=60$' "$TEST_TMP/Engine.ini" >/dev/null
    grep -c '^LanServerMaxTickRate=120$' "$TEST_TMP/Engine.ini" >/dev/null
    grep -c 'LowerBound=(Type=Inclusive,Value=30.000000)' "$TEST_TMP/Engine.ini" >/dev/null
    [[ "$(cat "$TEST_TMP/Engine.ini")" != *'$'* ]]
}

@test "game_install renders settings and skips Engine.ini by default" {
    fake_install
    export SERVER_NAME="Rendered"
    game_install
    grep -c 'ServerName="Rendered",' "$DATA_DIR/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini" >/dev/null
    [ ! -e "$DATA_DIR/Pal/Saved/Config/LinuxServer/Engine.ini" ]
    export DISABLE_GENERATE_ENGINE=false
    game_install
    [ -f "$DATA_DIR/Pal/Saved/Config/LinuxServer/Engine.ini" ]
}

@test "game_install refuses to run without an admin password" {
    fake_install
    export ADMIN_PASSWORD=""
    run game_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"ADMIN_PASSWORD must be set"* ]]
}

@test "start command launches the binary directly with the right flags" {
    fake_install
    game_start_cmd
    [ "${GAME_CMD[0]}" = "$DATA_DIR/Pal/Binaries/Linux/PalServer-Linux-Shipping" ]
    [ "${GAME_CMD[1]}" = Pal ]
    [[ " ${GAME_CMD[*]} " == *" -port=8211 "* ]]
    [[ " ${GAME_CMD[*]} " == *" -queryport=27015 "* ]]
    [[ " ${GAME_CMD[*]} " != *"-publiclobby"* ]]
    [[ " ${GAME_CMD[*]} " != *"-useperfthreads"* ]]

    export PUBLIC=true MULTITHREADING=true WORKER_THREADS_SERVER=4 PORT=9000
    game_start_cmd
    [[ " ${GAME_CMD[*]} " == *" -publiclobby "* ]]
    [[ " ${GAME_CMD[*]} " == *" -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS "* ]]
    [[ " ${GAME_CMD[*]} " == *" -NumberOfWorkerThreadsServer=4"* ]]
}
