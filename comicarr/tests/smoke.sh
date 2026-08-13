#!/bin/bash
# Docker smoke tests for the Comicarr Home Assistant app image.

set -euo pipefail

readonly IMAGE="${1:?usage: smoke.sh IMAGE}"
TEST_ROOT="$(mktemp -d -t comicarr-smoke.XXXXXX)"
readonly TEST_ROOT
readonly DATA_DIR="${TEST_ROOT}/data"
readonly MEDIA_DIR="${TEST_ROOT}/media"
readonly SHARE_DIR="${TEST_ROOT}/share"
readonly CONTAINER_NAME="comicarr-smoke-$$"
readonly RESTART_NAME="comicarr-smoke-restart-$$"
readonly PRESERVE_NAME="comicarr-smoke-preserve-$$"
CONTAINERS=()

log() {
  printf '[smoke] %s\n' "$*"
}

cleanup() {
  local name

  for name in "${CONTAINERS[@]}"; do
    docker rm -f "${name}" >/dev/null 2>&1 || true
  done
  docker run --rm --entrypoint sh \
    --volume "${TEST_ROOT}:/test:rw" "${IMAGE}" \
    -c 'rm -rf -- /test/data /test/media /test/share' \
    >/dev/null 2>&1 || true
  rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

write_options() {
  local source="$1"

  mkdir -p "${DATA_DIR}" "${MEDIA_DIR}" "${SHARE_DIR}"
  cp "${source}" "${DATA_DIR}/options.json"
  chmod 0777 "${DATA_DIR}" "${MEDIA_DIR}" "${SHARE_DIR}"
}

start_container() {
  local name="$1"

  CONTAINERS+=("${name}")
  docker run --detach --name "${name}" \
    --publish 127.0.0.1::8090 \
    --volume "${DATA_DIR}:/data:rw" \
    --volume "${MEDIA_DIR}:/media:rw" \
    --volume "${SHARE_DIR}:/share:rw" \
    "${IMAGE}" >/dev/null
}

wait_for_health() {
  local name="$1"
  local attempt

  for ((attempt = 1; attempt <= 180; attempt += 1)); do
    if ! docker inspect --format '{{.State.Running}}' "${name}" \
      2>/dev/null | grep -qx true; then
      docker logs "${name}" >&2 || true
      return 1
    fi
    if docker exec "${name}" python3 -c \
      'import urllib.request; assert urllib.request.urlopen("http://127.0.0.1:8090/api/health", timeout=2).status == 200' \
      >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  docker logs "${name}" >&2 || true
  return 1
}

assert_initial_state() {
  local name="$1"

  docker exec "${name}" python3 -c \
    'import urllib.request; body = urllib.request.urlopen("http://127.0.0.1:8090/", timeout=2).read(); assert b"<div id=\"root\"></div>" in body'
  docker exec "${name}" test -f /data/comicarr/config.ini
  docker exec "${name}" test -f /data/comicarr/comicarr.db
  docker exec "${name}" grep -Fq 'destination_dir = /media/comics' \
    /data/comicarr/config.ini
  docker exec "${name}" grep -Fq 'manga_destination_dir = /media/manga' \
    /data/comicarr/config.ini
  docker exec "${name}" test -d /share/comicarr/downloads
  docker exec "${name}" test -d /share/comicarr/watch
  docker exec "${name}" sh -c \
    'printf persistence-ok > /data/comicarr/ha-smoke-sentinel'
}

assert_config_value() {
  local name="$1"
  local section="$2"
  local key="$3"
  local expected="$4"

  docker exec "${name}" python3 -c '
import configparser
import sys

parser = configparser.ConfigParser(interpolation=None)
parser.read("/data/comicarr/config.ini")
actual = parser.get(sys.argv[1], sys.argv[2])
if actual != sys.argv[3]:
    raise SystemExit(f"{sys.argv[1]}.{sys.argv[2]}: expected {sys.argv[3]!r}, got {actual!r}")
' "${section}" "${key}" "${expected}"
}

assert_encrypted_secret() {
  local name="$1"
  local section="$2"
  local key="$3"

  docker exec "${name}" python3 -c '
import configparser
import sys

parser = configparser.ConfigParser(interpolation=None)
parser.read("/data/comicarr/config.ini")
value = parser.get(sys.argv[1], sys.argv[2])
if not value.startswith("gAAAAA"):
    raise SystemExit(f"{sys.argv[1]}.{sys.argv[2]} was not encrypted")
' "${section}" "${key}"
}

assert_full_configuration() {
  local name="$1"

  assert_config_value "${name}" General destination_dir /media/library/comics
  assert_config_value "${name}" General manga_destination_dir /media/library/manga
  # shellcheck disable=SC2016
  assert_config_value "${name}" General folder_format '$Publisher/$Series ($Year)'
  # shellcheck disable=SC2016
  assert_config_value "${name}" General file_format '$Series $Issue ($Year)'
  assert_config_value "${name}" General create_folders True
  assert_config_value "${name}" General rename_files True
  assert_config_value "${name}" General backup_on_start True
  assert_config_value "${name}" General backup_retention 9
  assert_config_value "${name}" PostProcess file_opts copy
  assert_config_value "${name}" Scheduler rss_checkinterval 30
  assert_config_value "${name}" Scheduler search_interval 720
  assert_config_value "${name}" Scheduler download_scan_interval 3
  assert_config_value "${name}" Client torrent_downloader 5
  assert_config_value "${name}" Torrents enable_torrents True
  assert_config_value "${name}" Torrents enable_torrent_search True
  assert_config_value "${name}" Torrents minseeds 5
  assert_config_value "${name}" Watchdir local_watchdir /share/watch/comicarr
  assert_config_value "${name}" qBittorrent qbittorrent_host http://qbittorrent:8080
  assert_config_value "${name}" qBittorrent qbittorrent_username comicarr
  assert_config_value "${name}" qBittorrent qbittorrent_label comic-books
  assert_config_value "${name}" qBittorrent qbittorrent_folder /share/downloads/comicarr
  assert_config_value "${name}" qBittorrent qbittorrent_loadaction paused
  assert_config_value "${name}" Transmission transmission_host http://transmission:9091
  assert_config_value "${name}" Transmission transmission_username comicarr
  assert_config_value "${name}" Transmission transmission_directory /share/downloads/comicarr
  assert_config_value "${name}" OPDS opds_enable True
  assert_config_value "${name}" OPDS opds_authentication True
  assert_config_value "${name}" OPDS opds_endpoint catalog
  assert_config_value "${name}" OPDS opds_username reader
  assert_config_value "${name}" OPDS opds_pagesize 60
  assert_config_value "${name}" OPDS opds_metainfo True
  assert_config_value "${name}" HAUnmanaged keep_me untouched
  assert_encrypted_secret "${name}" qBittorrent qbittorrent_password
  assert_encrypted_secret "${name}" Transmission transmission_password
  assert_encrypted_secret "${name}" OPDS opds_password
  docker exec "${name}" test -d /media/library/comics
  docker exec "${name}" test -d /media/library/manga
  docker exec "${name}" test -d /share/downloads/comicarr
  docker exec "${name}" test -d /share/watch/comicarr
}

assert_invalid_options_rejected() {
  assert_invalid_option \
    timezone \
    '{"timezone":"not/a-zone","log_level":"normal"}' \
    'timezone must be a valid IANA timezone'
  assert_invalid_option \
    outside-path \
    '{"timezone":"Etc/UTC","log_level":"normal","directories":{"comics":"/etc/comics"}}' \
    'directories.comics must be below /media or /share'
  assert_invalid_option \
    traversal \
    '{"timezone":"Etc/UTC","log_level":"normal","directories":{"comics":"/media/library/../comics"}}' \
    'directories.comics must not contain parent traversal'
}

assert_invalid_option() {
  local label="$1"
  local options_json="$2"
  local expected="$3"
  local invalid_dir="${TEST_ROOT}/invalid-${label}"
  local name="comicarr-smoke-invalid-${label}-$$"
  local output

  mkdir -p "${invalid_dir}"
  printf '%s\n' "${options_json}" >"${invalid_dir}/options.json"
  CONTAINERS+=("${name}")
  if output="$(docker run --name "${name}" \
    --volume "${invalid_dir}:/data:rw" \
    --volume "${MEDIA_DIR}:/media:rw" \
    --volume "${SHARE_DIR}:/share:rw" \
    "${IMAGE}" 2>&1)"; then
    printf 'invalid options unexpectedly succeeded: %s\n' "${label}" >&2
    return 1
  fi
  grep -Fq "${expected}" <<<"${output}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

log "upgrading legacy options with default managed settings"
write_options "${SCRIPT_DIR}/options-legacy.json"
start_container "${CONTAINER_NAME}"
wait_for_health "${CONTAINER_NAME}"
assert_initial_state "${CONTAINER_NAME}"
docker stop --time 45 "${CONTAINER_NAME}" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "${CONTAINER_NAME}")" == "0" ]]
docker run --rm --entrypoint sh \
  --volume "${DATA_DIR}:/data:rw" "${IMAGE}" \
  -c "printf '%s\\n' '[HAUnmanaged]' 'keep_me = untouched' >>/data/comicarr/config.ini"

log "applying customized Home Assistant settings"
write_options "${SCRIPT_DIR}/options-full.json"
start_container "${RESTART_NAME}"
wait_for_health "${RESTART_NAME}"
assert_full_configuration "${RESTART_NAME}"
docker exec "${RESTART_NAME}" grep -Fqx persistence-ok \
  /data/comicarr/ha-smoke-sentinel
docker stop --time 45 "${RESTART_NAME}" >/dev/null

log "preserving encrypted secrets when password options are omitted"
write_options "${SCRIPT_DIR}/options-default.json"
start_container "${PRESERVE_NAME}"
wait_for_health "${PRESERVE_NAME}"
assert_encrypted_secret "${PRESERVE_NAME}" qBittorrent qbittorrent_password
assert_encrypted_secret "${PRESERVE_NAME}" Transmission transmission_password
assert_encrypted_secret "${PRESERVE_NAME}" OPDS opds_password
assert_config_value "${PRESERVE_NAME}" HAUnmanaged keep_me untouched
docker stop --time 45 "${PRESERVE_NAME}" >/dev/null

log "checking invalid option handling"
assert_invalid_options_rejected
log "all Comicarr smoke checks passed"
