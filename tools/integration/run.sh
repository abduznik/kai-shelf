#!/usr/bin/env bash
# Starts real Suwayomi, Komga and Kavita servers in containers, seeds them
# with test comics, and runs the live integration tests against them.
#
#   tools/integration/run.sh            # uses docker, or podman if docker is missing
#   KEEP=1 tools/integration/run.sh     # leave the containers running afterwards
set -euo pipefail

cd "$(dirname "$0")/../.."
CT="${CONTAINER:-$(command -v docker >/dev/null && echo docker || echo podman)}"
WORK="$(mktemp -d)"
PFX="kai-it"
PORT_SUWA=14567
PORT_KOMGA=15600
PORT_KAVITA=15000

KOMGA_EMAIL="kai@test.dev"
KOMGA_PASSWORD="kai-test-pw1"
KAVITA_USER="kai"
KAVITA_PASSWORD="Kai-test-pw1!"

cleanup() {
  if [ -z "${KEEP:-}" ]; then
    "$CT" rm -f "$PFX-suwayomi" "$PFX-komga" "$PFX-kavita" >/dev/null 2>&1 || true
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

echo "==> Generating test comics in $WORK"
python3 tools/integration/make_comics.py "$WORK"

echo "==> Starting servers with $CT"
"$CT" rm -f "$PFX-suwayomi" "$PFX-komga" "$PFX-kavita" >/dev/null 2>&1 || true
"$CT" run -d --name "$PFX-suwayomi" -p "$PORT_SUWA:4567" \
  -v "$WORK/suwayomi:/home/suwayomi/.local/share/Tachidesk/local:Z" \
  ghcr.io/suwayomi/tachidesk:stable >/dev/null
"$CT" run -d --name "$PFX-komga" -p "$PORT_KOMGA:25600" \
  -v "$WORK/komga:/data:Z" docker.io/gotson/komga:latest >/dev/null
"$CT" run -d --name "$PFX-kavita" -p "$PORT_KAVITA:5000" \
  -v "$WORK/kavita:/manga:Z" docker.io/jvmilazz0/kavita:latest >/dev/null

wait_for() { # name url
  for _ in $(seq 1 90); do
    if curl -s -o /dev/null --max-time 3 "$2"; then return 0; fi
    sleep 2
  done
  echo "timed out waiting for $1 ($2)" >&2
  "$CT" logs --tail 40 "$PFX-$1" >&2 || true
  exit 1
}
wait_for suwayomi "http://localhost:$PORT_SUWA/api/graphql"
wait_for komga "http://localhost:$PORT_KOMGA/api/v1/claim"
wait_for kavita "http://localhost:$PORT_KAVITA/api/health"

echo "==> Seeding Suwayomi's Local source"
# Gives the category tests a title to file without needing an extension.
"$CT" cp "$WORK/komga/Series/Alpha Saga" \
  "$PFX-suwayomi:/home/suwayomi/.local/share/Tachidesk/local/" >/dev/null

echo "==> Seeding Komga"
curl -sf -X POST "http://localhost:$PORT_KOMGA/api/v1/claim" \
  -H "X-Komga-Email: $KOMGA_EMAIL" -H "X-Komga-Password: $KOMGA_PASSWORD" >/dev/null
for lib in "Main:/data/Series" "Big:/data/Big"; do
  curl -sf -u "$KOMGA_EMAIL:$KOMGA_PASSWORD" -H 'content-type: application/json' \
    -X POST "http://localhost:$PORT_KOMGA/api/v1/libraries" \
    -d "{\"name\":\"${lib%%:*}\",\"root\":\"${lib#*:}\"}" >/dev/null
done

echo "==> Seeding Kavita"
KJSON='content-type: application/json'
curl -sf -X POST "http://localhost:$PORT_KAVITA/api/Account/register" -H "$KJSON" \
  -d "{\"username\":\"$KAVITA_USER\",\"email\":\"kai@test.dev\",\"password\":\"$KAVITA_PASSWORD\"}" >/dev/null
LOGIN="$(curl -sf -X POST "http://localhost:$PORT_KAVITA/api/Account/login" -H "$KJSON" \
  -d "{\"username\":\"$KAVITA_USER\",\"password\":\"$KAVITA_PASSWORD\"}")"
KAVITA_TOKEN="$(printf '%s' "$LOGIN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')"
KAVITA_API_KEY="$(printf '%s' "$LOGIN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["apiKey"])')"
# metadataProvider is a required enum whose valid values differ by version;
# try them until the server accepts one.
created=""
for provider in 3 4 5 2 1 0; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://localhost:$PORT_KAVITA/api/Library/create" \
    -H "$KJSON" -H "Authorization: Bearer $KAVITA_TOKEN" \
    -d "{\"name\":\"Main\",\"type\":0,\"folders\":[\"/manga\"],\"folderWatching\":false,\"includeInDashboard\":true,\"includeInRecommended\":true,\"includeInSearch\":true,\"manageCollections\":true,\"manageReadingLists\":true,\"allowScrobbling\":false,\"allowMetadataMatching\":false,\"enableMetadata\":false,\"fileGroupTypes\":[1],\"excludePatterns\":[],\"metadataProvider\":$provider}")"
  if [ "$code" = "200" ]; then created=1; break; fi
done
[ -n "$created" ] || { echo "could not create Kavita library" >&2; exit 1; }

echo "==> Waiting for library scans"
for _ in $(seq 1 60); do
  k="$(curl -s -u "$KOMGA_EMAIL:$KOMGA_PASSWORD" "http://localhost:$PORT_KOMGA/api/v1/series?size=1" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("totalElements",0))' 2>/dev/null || echo 0)"
  v="$(curl -s -X POST "http://localhost:$PORT_KAVITA/api/Series/v2?PageNumber=1&PageSize=50" \
    -H "$KJSON" -H "Authorization: Bearer $KAVITA_TOKEN" -d '{}' \
    | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
  [ "$k" -ge 232 ] && [ "$v" -ge 2 ] && break
  sleep 3
done
echo "    komga series: $k, kavita series: $v"

echo "==> Running live tests"
KAI_SUWAYOMI_URL="http://localhost:$PORT_SUWA" \
KAI_KOMGA_URL="http://localhost:$PORT_KOMGA" \
KAI_KOMGA_EMAIL="$KOMGA_EMAIL" KAI_KOMGA_PASSWORD="$KOMGA_PASSWORD" \
KAI_KAVITA_URL="http://localhost:$PORT_KAVITA" KAI_KAVITA_API_KEY="$KAVITA_API_KEY" \
  flutter test test/integration
