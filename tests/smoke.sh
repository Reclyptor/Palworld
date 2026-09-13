#!/usr/bin/env bash
# End-to-end against the real game: SteamCMD install (~7 GB) → REST readiness →
# backup → live update check → saving stop. Webhooks go to a receiver in a
# sidecar container on a private network.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GAME_IMAGE:=palworld:test}"
runner="${GAME_IMAGE}-runner"
name=palworld-smoke-$$
net="${name}-net"
hooks_ctr="${name}-hooks"
hook_port=18089
work=$(mktemp -d)
hooks="$work/webhooks.log"

cleanup() {
    docker rm -f -v "$name" "$hooks_ctr" >/dev/null 2>&1 || true
    docker network rm "$net" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

fail() {
    echo "SMOKE FAIL: $*" >&2
    echo "--- container log ---" >&2; docker logs "$name" 2>&1 | tail -80 >&2 || true
    echo "--- webhooks ---" >&2; sync_hooks; cat "$hooks" >&2
    exit 1
}
step() { echo "==> $*"; }
sync_hooks() { docker logs "$hooks_ctr" 2>/dev/null > "$hooks" || true; }
wait_for() {
    local what=$1 pattern=$2 timeout=${3:-60} i
    for (( i = 0; i < timeout; i++ )); do
        sync_hooks; grep -cE "$pattern" "$hooks" >/dev/null && return 0; sleep 1
    done
    fail "timed out waiting for ${what}: /${pattern}/"
}
# Run a snippet inside the container with the toolkit and adapter loaded.
in_game() { docker exec "$name" bash -c "source /opt/gameops/shim/adapter.sh; adapter_load; $*"; }

step "build images"
[[ -n "$(docker images -q "$GAME_IMAGE")" ]] || docker build -q -t "$GAME_IMAGE" . >/dev/null
docker build -q -t "$runner" --build-arg "GAME_IMAGE=${GAME_IMAGE}" -f tests/runner.Dockerfile tests >/dev/null

step "start webhook receiver"
docker network create "$net" >/dev/null
docker run -d --name "$hooks_ctr" --network "$net" --entrypoint python3 "$runner" -u -c "
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        print(body, flush=True)
        self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(('0.0.0.0', ${hook_port}), H).serve_forever()
" >/dev/null
sleep 1

step "run palworld (installs the server through SteamCMD first)"
docker run -d --name "$name" --network "$net" \
    -e "DISCORD_WEBHOOK_URL=http://${hooks_ctr}:${hook_port}/hook" \
    -e SERVER_NAME="Smoke Test" -e ADMIN_PASSWORD=smoke-admin -e GAME_PASSWORD=smoke \
    -e MAX_PLAYERS=4 -e UPDATE_ON_BOOT=false -e STOP_TIMEOUT=180 -e READY_TIMEOUT=1800 \
    -e BACKUP_RETAIN_DAYS=0 -e LOG_LEVEL=debug \
    "$GAME_IMAGE" >/dev/null
wait_for "START notification" 'Smoke Test server is online' 3600

step "health and REST"
for i in $(seq 1 12); do
    [[ "$(docker inspect -f '{{.State.Health.Status}}' "$name")" == healthy ]] && break
    sleep 5
done
[[ "$(docker inspect -f '{{.State.Health.Status}}' "$name")" == healthy ]] || fail "container health is $(docker inspect -f '{{.State.Health.Status}}' "$name")"
info=$(in_game 'pal_rest_get info')
[[ "$info" == *'"version"'* ]] || fail "REST /info returned '${info}'"
echo "    info: ${info}"
[[ "$(in_game 'game_players')" == 0 ]] || fail "expected 0 players"
echo "    build: $(in_game 'game_version')"
docker exec "$name" grep -c 'ServerName="Smoke Test",' /data/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini >/dev/null || fail "PalWorldSettings.ini not rendered"
docker exec "$name" grep -c 'ServerPlayerMaxNum=4,' /data/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini >/dev/null || fail "MAX_PLAYERS not applied"
in_game 'game_broadcast "smoke test announcement"' || fail "announce failed"

step "backup"
docker exec "$name" gameops backup
wait_for "BACKUP_POST notification" 'Manual backup of the Smoke Test server complete: /backups/palworld-' 120
archive=$(docker exec "$name" sh -c 'ls /backups/palworld-*.tar.gz')
docker exec "$name" tar -tzf "$archive" | grep -c '^Pal/Saved/SaveGames/' >/dev/null || fail "archive lacks Pal/Saved/SaveGames"
docker exec "$name" tar -tzf "$archive" | grep -c '^Pal/Saved/Config/LinuxServer/PalWorldSettings.ini$' >/dev/null || fail "archive lacks the settings"

step "update check against the live Steam API"
out=$(in_game 'game_update_available; echo "rc=$?"')
echo "    check → ${out##*$'\n'}"
[[ "$out" == *"rc=1"* ]] || fail "just installed, so the check must report current: ${out}"

step "graceful stop on SIGTERM saves the world"
before=$(docker exec "$name" sh -c 'find /data/Pal/Saved/SaveGames -type f -printf "%T@\n" | sort -n | tail -1 | cut -d. -f1')
sleep 2
docker stop -t 240 "$name" >/dev/null
code=$(docker inspect -f '{{.State.ExitCode}}' "$name")
[[ "$code" == 0 ]] || fail "expected exit 0 after SIGTERM, got ${code}"
wait_for "STOP notification" 'Smoke Test server has shut down' 10
after=$(docker run --rm --volumes-from "$name" --entrypoint sh "$GAME_IMAGE" -c 'find /data/Pal/Saved/SaveGames -type f -printf "%T@\n" | sort -n | tail -1 | cut -d. -f1')
(( after > before )) || fail "world was not saved on shutdown (mtime ${before} → ${after})"
docker logs "$name" 2>&1 | grep -cE 'Server is shutting down|shutdown' >/dev/null || true

echo "SMOKE OK"
