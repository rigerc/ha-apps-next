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
  docker exec "${name}" sh -c \
    'printf persistence-ok > /data/comicarr/ha-smoke-sentinel'
}

assert_invalid_options_rejected() {
  local invalid_dir="${TEST_ROOT}/invalid"
  local name="comicarr-smoke-invalid-$$"
  local output

  mkdir -p "${invalid_dir}"
  printf '%s\n' \
    '{"timezone":"not/a-zone","log_level":"normal"}' \
    >"${invalid_dir}/options.json"
  CONTAINERS+=("${name}")
  if output="$(docker run --name "${name}" \
    --volume "${invalid_dir}:/data:rw" "${IMAGE}" 2>&1)"; then
    printf 'invalid options unexpectedly succeeded\n' >&2
    return 1
  fi
  grep -Fq 'timezone must be a valid IANA timezone' <<<"${output}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

log "starting with default options"
write_options "${SCRIPT_DIR}/options-default.json"
start_container "${CONTAINER_NAME}"
wait_for_health "${CONTAINER_NAME}"
assert_initial_state "${CONTAINER_NAME}"
docker stop --time 45 "${CONTAINER_NAME}" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "${CONTAINER_NAME}")" == "0" ]]

log "restarting with the same persistent data"
write_options "${SCRIPT_DIR}/options-full.json"
start_container "${RESTART_NAME}"
wait_for_health "${RESTART_NAME}"
docker exec "${RESTART_NAME}" grep -Fqx persistence-ok \
  /data/comicarr/ha-smoke-sentinel
docker stop --time 45 "${RESTART_NAME}" >/dev/null

log "checking invalid option handling"
assert_invalid_options_rejected
log "all Comicarr smoke checks passed"
