#!/usr/bin/env bash
# Starts a throw-away Jellyfin for the contract test (CI job `jellyfin`): two tagged FLAC files
# made from our own test tone (test/fixtures/tone-20.wav, see tool/make_tone.dart) as its music
# library (read-only), the startup wizard done through the API (admin = JELLYFIN_USER), a music
# library added, then waits until the scan has found the album and its songs.
#
#   JELLYFIN_USER=… JELLYFIN_PASSWORD=… tool/jellyfin-ci.sh
#
# Then: JELLYFIN_URL=http://localhost:8096 flutter test test/sources/jellyfin_contract_test.dart
#
# Needs docker, curl and jq. Every step says what it does; a failure prints the HTTP status and
# answer of the call that broke, then the server log, so the CI log shows what went wrong.
set -euo pipefail

IMAGE="${JELLYFIN_IMAGE:-jellyfin/jellyfin:10.10.7}"
PORT="${JELLYFIN_PORT:-8096}"
URL="http://localhost:${PORT}"
NAME=jellyfin-ci
MUSIC="${JELLYFIN_MUSIC_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/jellyfin-ci-music}"
: "${JELLYFIN_USER:?set JELLYFIN_USER}"
: "${JELLYFIN_PASSWORD:?set JELLYFIN_PASSWORD}"

# what the contract test expects (test/sources/jellyfin_contract_test.dart)
ALBUM='CI Tones'
ALBUM_ARTIST='LAFLEUR CI'

step() { echo "==> $*"; }

diagnostics() {
  echo "---- docker ps ----" >&2
  docker ps -a --filter "name=${NAME}" >&2 || true
  echo "---- music folder ----" >&2
  ls -laR "${MUSIC}" >&2 || true
  echo "---- Jellyfin log (last 200 lines) ----" >&2
  docker logs --tail 200 "${NAME}" >&2 || true
}
trap 'code=$?; if [ "${code}" -ne 0 ]; then echo "::error::tool/jellyfin-ci.sh failed (exit ${code})" >&2; diagnostics; fi' EXIT

for tool in docker curl jq; do
  command -v "${tool}" >/dev/null || { echo "::error::${tool} is missing" >&2; exit 1; }
done

TOKEN=""
auth() {
  local a='MediaBrowser Client="lafleur-ci", Device="ci", DeviceId="lafleur-ci", Version="1.0.0"'
  if [ -n "${TOKEN}" ]; then a="${a}, Token=\"${TOKEN}\""; fi
  printf '%s' "${a}"
}

# api METHOD PATH [JSON]: the answer on stdout. Anything but a 2xx prints the status and the
# answer (never the request: it may carry the password) and fails.
api() {
  local method="$1" path="$2" data="${3:-}" out code
  out="$(mktemp)"
  local args=(-sS --max-time 20 -o "${out}" -w '%{http_code}' -X "${method}"
    -H "Authorization: $(auth)")
  if [ -n "${data}" ]; then
    args+=(-H 'Content-Type: application/json' --data "${data}")
  fi
  code="$(curl "${args[@]}" "${URL}${path}")" || code="000"
  if [[ "${code}" != 2* ]]; then
    echo "::error::${method} ${path%%\?*} → HTTP ${code}" >&2
    head -c 2000 "${out}" >&2 || true
    echo >&2
    rm -f "${out}"
    return 1
  fi
  cat "${out}"
  rm -f "${out}"
}

step "Making the music library in ${MUSIC} from test/fixtures/tone-20.wav"
[ -f test/fixtures/tone-20.wav ] || { echo "::error::run from the repository root (test/fixtures/tone-20.wav)" >&2; exit 1; }
rm -rf "${MUSIC}"
mkdir -p "${MUSIC}/${ALBUM_ARTIST}/${ALBUM}"
docker pull --quiet "${IMAGE}" >/dev/null
# the image's own ffmpeg: nothing else to install on the runner
n=0
for title in 'Tone One' 'Tone Two'; do
  n=$((n + 1))
  docker run --rm --user "$(id -u):$(id -g)" \
    --entrypoint /usr/lib/jellyfin-ffmpeg/ffmpeg \
    -v "${PWD}/test/fixtures:/in:ro" \
    -v "${MUSIC}:/out" \
    "${IMAGE}" -hide_banner -loglevel error -y -i /in/tone-20.wav \
    -metadata "title=${title}" -metadata "artist=${ALBUM_ARTIST}" \
    -metadata "album_artist=${ALBUM_ARTIST}" -metadata "album=${ALBUM}" \
    -metadata "track=${n}" -metadata "genre=Test" \
    "/out/${ALBUM_ARTIST}/${ALBUM}/0${n} ${title}.flac"
done
ls -la "${MUSIC}/${ALBUM_ARTIST}/${ALBUM}"

step "Starting ${IMAGE} on ${URL}"
docker rm -fv "${NAME}" >/dev/null 2>&1 || true
docker run -d --name "${NAME}" \
  -p "${PORT}:8096" \
  -v "${MUSIC}:/music:ro" \
  "${IMAGE}" >/dev/null

step "Waiting for ${URL}/System/Info/Public"
info=""
for _ in $(seq 1 90); do
  info="$(curl -fsS --max-time 5 "${URL}/System/Info/Public" 2>/dev/null || true)"
  if echo "${info}" | jq -e '.ProductName' >/dev/null 2>&1; then break; fi
  sleep 2
done
echo "${info}" | jq -e '.ProductName' >/dev/null 2>&1 || {
  echo "::error::Jellyfin did not answer within 180 s (last answer: ${info:-none})" >&2
  exit 1
}
echo "${info}" | jq -c '{ProductName, Version, StartupWizardCompleted}'

step "Startup wizard: language"
api GET /Startup/Configuration >/dev/null
api POST /Startup/Configuration \
  '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' >/dev/null

step "Startup wizard: the admin"
# GET first: it creates the default user that POST then renames
api GET /Startup/User >/dev/null
api POST /Startup/User \
  "$(jq -nc --arg n "${JELLYFIN_USER}" --arg p "${JELLYFIN_PASSWORD}" '{Name: $n, Password: $p}')" >/dev/null

step "Startup wizard: remote access, then done"
api POST /Startup/RemoteAccess '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}' >/dev/null
api POST /Startup/Complete >/dev/null

step "Signing in as the admin"
signin=""
for _ in $(seq 1 15); do
  # right after the wizard the server may still be saving the user: a few tries
  if signin="$(api POST /Users/AuthenticateByName \
    "$(jq -nc --arg n "${JELLYFIN_USER}" --arg p "${JELLYFIN_PASSWORD}" '{Username: $n, Pw: $p}')")"; then
    break
  fi
  sleep 2
done
TOKEN="$(echo "${signin}" | jq -r '.AccessToken // empty')"
USER_ID="$(echo "${signin}" | jq -r '.User.Id // empty')"
[ -n "${TOKEN}" ] && [ -n "${USER_ID}" ] || {
  echo "::error::sign-in gave no token or user id" >&2
  exit 1
}

step "Adding the music library (/music)"
api POST "/Library/VirtualFolders?name=Music&collectionType=music&refreshLibrary=true" \
  '{"LibraryOptions":{"EnableRealtimeMonitor":false,"PathInfos":[{"Path":"/music"}]}}' >/dev/null
api GET /Library/VirtualFolders | jq -c '[.[] | {Name, CollectionType, Locations}]'

step "Scanning"
api POST /Library/Refresh >/dev/null || true # the scan asked above may already be running
albums=0
songs=0
for _ in $(seq 1 90); do
  albums="$(api GET "/Users/${USER_ID}/Items?IncludeItemTypes=MusicAlbum&Recursive=true&Limit=10" |
    jq '.TotalRecordCount // 0' || echo 0)"
  songs="$(api GET "/Users/${USER_ID}/Items?IncludeItemTypes=Audio&Recursive=true&Limit=10" |
    jq '.TotalRecordCount // 0' || echo 0)"
  if [ "${albums}" -ge 1 ] && [ "${songs}" -ge 2 ]; then
    api GET "/Users/${USER_ID}/Items?IncludeItemTypes=MusicAlbum&Recursive=true&Limit=10" |
      jq -c '[.Items[] | {Name, AlbumArtist, ChildCount}]'
    step "Scan done: ${albums} album(s), ${songs} song(s)"
    exit 0
  fi
  sleep 2
done
echo "::error::after 180 s the library has ${albums} album(s) and ${songs} song(s) (want 1 and 2)" >&2
api GET /ScheduledTasks | jq -c '[.[] | select(.State != "Idle") | {Name, State, CurrentProgressPercentage}]' >&2 || true
exit 1
