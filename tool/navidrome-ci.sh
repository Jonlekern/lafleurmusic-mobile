#!/usr/bin/env bash
# Starts a throw-away Navidrome for the contract test (CI job `navidrome`), with test/fixtures/ as
# its music folder (read-only), creates its first admin through the API and waits for the scan.
#
#   NAVIDROME_USER=… NAVIDROME_PASSWORD=… tool/navidrome-ci.sh
#
# Then: NAVIDROME_URL=http://localhost:4533 flutter test test/sources/navidrome_contract_test.dart
set -euo pipefail

IMAGE="${NAVIDROME_IMAGE:-deluan/navidrome:0.53.3}"
PORT="${NAVIDROME_PORT:-4533}"
URL="http://localhost:${PORT}"
: "${NAVIDROME_USER:?set NAVIDROME_USER}"
: "${NAVIDROME_PASSWORD:?set NAVIDROME_PASSWORD}"

docker rm -f navidrome-ci >/dev/null 2>&1 || true
docker run -d --name navidrome-ci \
  -p "${PORT}:4533" \
  -v "${PWD}/test/fixtures:/music:ro" \
  -e ND_MUSICFOLDER=/music \
  -e ND_SCANSCHEDULE='@every 1m' \
  -e ND_LOGLEVEL=info \
  "${IMAGE}"

# every request is bounded; polling loops are bounded too (60 × 2 s)
CURL=(curl -fsS --max-time 10)

echo "Waiting for ${URL}/ping"
for _ in $(seq 1 60); do
  if "${CURL[@]}" "${URL}/ping" >/dev/null 2>&1; then break; fi
  sleep 2
done
"${CURL[@]}" "${URL}/ping" >/dev/null

echo "Creating the first admin"
"${CURL[@]}" -X POST "${URL}/auth/createAdmin" \
  -H 'Content-Type: application/json' \
  --data "$(printf '{"username":"%s","password":"%s"}' "${NAVIDROME_USER}" "${NAVIDROME_PASSWORD}")" \
  >/dev/null

# Subsonic call with token auth: md5(password + salt)
subsonic() {
  local method="$1"
  local salt token
  salt="$(openssl rand -hex 6)"
  token="$(printf '%s%s' "${NAVIDROME_PASSWORD}" "${salt}" | openssl md5 | awk '{print $NF}')"
  shift
  "${CURL[@]}" -G "${URL}/rest/${method}.view" \
    --data-urlencode "u=${NAVIDROME_USER}" \
    --data-urlencode "t=${token}" \
    --data-urlencode "s=${salt}" \
    --data-urlencode "v=1.16.1" \
    --data-urlencode "c=lafleur-ci" \
    --data-urlencode "f=json" \
    "$@"
}

echo "Scanning test/fixtures"
subsonic startScan >/dev/null || true # the scan on startup may already be running
# done when the library really has an album, not merely when "scanning" is false
albums=""
for _ in $(seq 1 60); do
  albums="$(subsonic getAlbumList2 --data-urlencode type=alphabeticalByName --data-urlencode size=10 || true)"
  if echo "${albums}" | grep -q '"album":\[{'; then
    echo "Scan done: $(subsonic getScanStatus || true)"
    exit 0
  fi
  sleep 2
done
echo "No album after the scan: ${albums}" >&2
docker logs navidrome-ci >&2 || true
exit 1
