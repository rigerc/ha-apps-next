#!/bin/bash
# Docker smoke tests for the Reclaimerr Home Assistant app image.

set -euo pipefail

readonly IMAGE="${1:?usage: smoke.sh IMAGE}"
TEST_ROOT="$(mktemp -d -t reclaimerr-smoke.XXXXXX)"
readonly TEST_ROOT
readonly DATA_DIR="${TEST_ROOT}/data"
readonly MEDIA_DIR="${TEST_ROOT}/media"
readonly SHARE_DIR="${TEST_ROOT}/share"
readonly RESTORE_DATA_DIR="${TEST_ROOT}/restore-data"
readonly FULL_DATA_DIR="${TEST_ROOT}/full-data"
readonly UPGRADE_DATA_DIR="${TEST_ROOT}/upgrade-data"
readonly OPTIONS_FILE="${DATA_DIR}/options.json"
readonly OLD_IMAGE="ghcr.io/jessielw/reclaimerr:0.3.4@sha256:81351128d89c1cee4b89cd6ab6f0948131fdc6aac69355c1a1718aed40fbe6ac"
readonly CONTAINER_NAME="reclaimerr-smoke-$$"
readonly RESTORE_CONTAINER_NAME="reclaimerr-smoke-restore-$$"
readonly FULL_CONTAINER_NAME="reclaimerr-smoke-full-$$"
readonly OLD_UPGRADE_CONTAINER_NAME="reclaimerr-smoke-old-upgrade-$$"
readonly UPGRADE_CONTAINER_NAME="reclaimerr-smoke-upgrade-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SECRET_SENTINEL="smoke-admin-password-must-not-leak"
CONTAINERS=()

log() {
  printf '[smoke] %s\n' "$*"
}

cleanup() {
  local name

  for name in "${CONTAINERS[@]}"; do
    docker rm -f "${name}" >/dev/null 2>&1 || true
  done
  # The app normally runs as root in the upstream image and may leave
  # root-owned SQLite/secrets files behind.  Use the same image to remove
  # only this explicitly-created temporary tree before removing its parent.
  docker run --rm --entrypoint sh \
    --volume "${TEST_ROOT}:/test:rw" "${IMAGE}" \
    -c 'rm -rf -- /test/data /test/media /test/share /test/restore-data /test/full-data /test/upgrade-data' \
    >/dev/null 2>&1 || true
  rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

write_options() {
  local options_json="$1"

  mkdir -p -- "${DATA_DIR}" "${MEDIA_DIR}" "${SHARE_DIR}"
  printf '%s\n' "${options_json}" >"${OPTIONS_FILE}"
  chmod 0777 "${DATA_DIR}" "${MEDIA_DIR}" "${SHARE_DIR}"
}

start_container() {
  local name="$1"
  local data_dir="${2:-${DATA_DIR}}"
  local media_dir="${3:-${MEDIA_DIR}}"
  local share_dir="${4:-${SHARE_DIR}}"
  local -a security_args=()

  CONTAINERS+=("${name}")
  if [[ -n "${APPARMOR_PROFILE:-}" ]]; then
    security_args+=(--security-opt "apparmor=${APPARMOR_PROFILE}")
  fi
  docker run --detach --name "${name}" \
    --publish 127.0.0.1::8000 \
    --volume "${data_dir}:/data:rw" \
    --volume "${media_dir}:/media:rw" \
    --volume "${share_dir}:/share:rw" \
    "${security_args[@]}" \
    "${IMAGE}" >/dev/null
}

start_old_upgrade_container() {
  CONTAINERS+=("${OLD_UPGRADE_CONTAINER_NAME}")
  docker run --detach --name "${OLD_UPGRADE_CONTAINER_NAME}" \
    --env DATA_DIR=/data/reclaimerr \
    --env STATIC_DIR=/data/reclaimerr/static \
    --env AVATARS_DIR=/data/reclaimerr/static/avatars \
    --volume "${UPGRADE_DATA_DIR}/reclaimerr:/data/reclaimerr:rw" \
    --volume "${MEDIA_DIR}:/media:rw" \
    "${OLD_IMAGE}" >/dev/null
}

wait_for_running() {
  local name="$1"
  local attempt

  for ((attempt = 1; attempt <= 120; attempt += 1)); do
    if ! docker inspect --format '{{.State.Running}}' "${name}" \
      2>/dev/null | grep -qx true; then
      docker logs "${name}" >&2 || true
      return 1
    fi
    return 0
  done
  docker logs "${name}" >&2 || true
  return 1
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
    if docker exec "${name}" curl --fail --silent --show-error \
      http://127.0.0.1:8000/api/info/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  docker logs "${name}" >&2 || true
  return 1
}

wait_for_stop() {
  local name="$1"
  local attempt

  for ((attempt = 1; attempt <= 60; attempt += 1)); do
    if docker inspect --format '{{.State.Running}}' "${name}" \
      2>/dev/null | grep -qx false; then
      return 0
    fi
    sleep 1
  done
  docker logs "${name}" >&2 || true
  return 1
}

assert_profile() {
  local name="$1"

  if [[ -n "${APPARMOR_PROFILE:-}" ]]; then
    docker exec "${name}" bash -c \
      '[[ "$(< /proc/1/attr/current)" == *"$1"* ]]' \
      -- "${APPARMOR_PROFILE}" \
      || { docker logs "${name}" >&2 || true; return 1; }
  fi
}

api_body() {
  local name="$1"
  local endpoint="$2"

  docker exec "${name}" curl --fail --silent --show-error \
    "http://127.0.0.1:8000${endpoint}"
}

assert_api_contract() {
  local name="$1"
  local health
  local version
  local setup

  health="$(api_body "${name}" /api/info/health)"
  version="$(api_body "${name}" /api/info/version)"
  setup="$(api_body "${name}" /api/setup/status)"
  grep -Fq '"status":"ok"' <<<"${health}"
  grep -Fq '"version":"0.3.5"' <<<"${version}"
  grep -Fq '"needs_setup":true' <<<"${setup}"
}

complete_setup() {
  local name="$1"
  local response

  response="$(docker exec "${name}" curl --fail --silent --show-error \
    --header 'content-type: application/json' \
    --data '{"password":"smoke-password-123","confirm_password":"smoke-password-123"}' \
    --write-out $'\n%{http_code}' \
    http://127.0.0.1:8000/api/setup)"
  grep -qx '201' <<<"${response##*$'\n'}"
  grep -Fq 'Setup complete' <<<"${response%$'\n'*}"
  grep -Fq '"needs_setup":false' <<<"$(api_body "${name}" /api/setup/status)"
}

assert_clean_stop() {
  local name="$1"
  local logs

  docker stop --time 30 "${name}" >/dev/null
  wait_for_stop "${name}"
  [[ "$(docker inspect --format '{{.State.ExitCode}}' "${name}")" == "0" ]]
  logs="$(docker logs "${name}" 2>&1)"
  grep -Fq 'reclaimerr API shutdown complete' <<<"${logs}"
}

assert_rejected() {
  local label="$1"
  local options_json="$2"
  local name="reclaimerr-smoke-invalid-${label}-$$"
  local invalid_dir="${TEST_ROOT}/invalid-${label}"
  local output
  local -a security_args=()

  mkdir -p -- "${invalid_dir}"
  printf '%s\n' "${options_json}" >"${invalid_dir}/options.json"
  CONTAINERS+=("${name}")
  if [[ -n "${APPARMOR_PROFILE:-}" ]]; then
    security_args+=(--security-opt "apparmor=${APPARMOR_PROFILE}")
  fi
  if output="$(docker run --name "${name}" \
    --volume "${invalid_dir}:/data:rw" \
    "${security_args[@]}" \
    "${IMAGE}" 2>&1)"; then
    printf 'invalid options unexpectedly succeeded: %s\n' "${label}" >&2
    return 1
  fi
  if grep -Fq "${SECRET_SENTINEL}" <<<"${output}"; then
    printf 'secret leaked while rejecting options: %s\n' "${label}" >&2
    return 1
  fi
}

assert_media_contract() {
  local name="$1"
  local source_dir="${MEDIA_DIR}/reclaimerr-smoke/source"
  local destination_dir="${MEDIA_DIR}/reclaimerr-smoke/destination"
  local delete_dir="${MEDIA_DIR}/reclaimerr-smoke/delete"

  mkdir -p -- "${source_dir}" "${destination_dir}" "${delete_dir}"
  printf 'disposable video fixture\n' >"${source_dir}/movie.mkv"
  printf 'disposable sidecar fixture\n' >"${source_dir}/movie.en.srt"
  printf 'delete video fixture\n' >"${delete_dir}/delete.mkv"
  printf 'delete sidecar fixture\n' >"${delete_dir}/delete.nfo"
  chmod -R 0777 "${MEDIA_DIR}/reclaimerr-smoke"

  docker exec \
    --env DATA_DIR=/data/reclaimerr \
    --env STATIC_DIR=/data/reclaimerr/static \
    --env AVATARS_DIR=/data/reclaimerr/static/avatars \
    "${name}" python3 -c '
from pathlib import Path
from backend.core.utils.filesystem import move_media, sibling_cleanup

root = Path("/media/reclaimerr-smoke")
moved = move_media(root / "source/movie.mkv", root / "destination")
assert moved == root / "destination/source/movie.mkv"
assert moved.read_text() == "disposable video fixture\n"
assert (moved.parent / "movie.en.srt").is_file()
sibling_cleanup(root / "delete/delete.mkv")
'
  [[ -f "${destination_dir}/source/movie.mkv" ]]
  [[ -f "${destination_dir}/source/movie.en.srt" ]]
  [[ ! -e "${source_dir}" && ! -e "${delete_dir}" ]]
  if ! docker inspect --format '{{json .Mounts}}' "${name}" \
    | grep -Eiq '"Destination":"/share".*"RW":true'; then
    return 1
  fi
  if docker inspect --format '{{json .Mounts}}' "${name}" \
    | grep -Eiq '"Destination":"/supervisor(/|"|$)'; then
    return 1
  fi
  printf 'disposable share fixture\n' >"${SHARE_DIR}/shared.txt"
  docker exec "${name}" python3 -c '
from pathlib import Path

path = Path("/share/shared.txt")
assert path.read_text() == "disposable share fixture\n"
path.write_text("updated share fixture\n")
'
  [[ "$(<"${SHARE_DIR}/shared.txt")" == "updated share fixture" ]]
  [[ "$(docker inspect --format '{{.HostConfig.NetworkMode}}' "${name}")" \
    != 'host' ]]
}

assert_host_port_contract() {
  local name="$1"
  local host_port

  host_port="$(docker port "${name}" 8000/tcp | awk -F: 'NR == 1 {print $NF}')"
  [[ "${host_port}" =~ ^[0-9]+$ ]]
  curl --fail --silent --show-error \
    "http://127.0.0.1:${host_port}/api/info/health" >/dev/null
}

copy_cold_backup() {
  mkdir -p -- "${RESTORE_DATA_DIR}"
  chmod 0777 "${RESTORE_DATA_DIR}"
  docker run --rm --entrypoint sh \
    --volume "${DATA_DIR}:/source:ro" \
    --volume "${RESTORE_DATA_DIR}:/destination:rw" \
    "${IMAGE}" -c 'cp -a /source/. /destination/'
}

file_sha256() {
  local name="$1"
  local path="$2"

  docker exec "${name}" python3 -c '
from hashlib import sha256
from pathlib import Path
import sys

print(sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
' "${path}"
}

database_count() {
  local name="$1"
  local table="$2"

  docker exec "${name}" python3 -c '
import sqlite3
import sys

table = sys.argv[1]
if table not in {"users", "general_settings", "task_schedules"}:
    raise SystemExit("unsupported smoke-test table")
with sqlite3.connect("/data/reclaimerr/database/reclaimerr.db") as database:
    print(database.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
' "${table}"
}

configure_upgrade_setting() {
  local name="$1"

  docker exec "${name}" python3 -c '
import asyncio

from backend.database import async_db
from backend.database.models import GeneralSettings

async def configure() -> None:
    async with async_db() as session:
        session.add(
            GeneralSettings(application_url="http://reclaimerr-upgrade.invalid:8000")
        )
        await session.commit()

asyncio.run(configure())
'
}

database_application_url() {
  local name="$1"

  docker exec "${name}" python3 -c '
import sqlite3

with sqlite3.connect("/data/reclaimerr/database/reclaimerr.db") as database:
    print(database.execute(
        "SELECT application_url FROM general_settings LIMIT 1"
    ).fetchone()[0])
'
}

assert_upgrade_contract() {
  local login_response
  local schedules_before
  local secret_hash_before
  local settings_before
  local users_before

  mkdir -p -- "${UPGRADE_DATA_DIR}/reclaimerr"
  cp "${SCRIPT_DIR}/options-default.json" "${UPGRADE_DATA_DIR}/options.json"
  chmod -R 0777 "${UPGRADE_DATA_DIR}"

  start_old_upgrade_container
  wait_for_health "${OLD_UPGRADE_CONTAINER_NAME}"
  complete_setup "${OLD_UPGRADE_CONTAINER_NAME}"
  configure_upgrade_setting "${OLD_UPGRADE_CONTAINER_NAME}"
  secret_hash_before="$(file_sha256 "${OLD_UPGRADE_CONTAINER_NAME}" \
    /data/reclaimerr/secrets.env)"
  users_before="$(database_count "${OLD_UPGRADE_CONTAINER_NAME}" users)"
  settings_before="$(database_count \
    "${OLD_UPGRADE_CONTAINER_NAME}" general_settings)"
  schedules_before="$(database_count \
    "${OLD_UPGRADE_CONTAINER_NAME}" task_schedules)"
  (( users_before > 0 && settings_before > 0 && schedules_before > 0 ))
  assert_clean_stop "${OLD_UPGRADE_CONTAINER_NAME}"

  start_container "${UPGRADE_CONTAINER_NAME}" "${UPGRADE_DATA_DIR}"
  wait_for_health "${UPGRADE_CONTAINER_NAME}"
  assert_profile "${UPGRADE_CONTAINER_NAME}"
  grep -Fq '"version":"0.3.5"' \
    <<<"$(api_body "${UPGRADE_CONTAINER_NAME}" /api/info/version)"
  grep -Fq '"needs_setup":false' \
    <<<"$(api_body "${UPGRADE_CONTAINER_NAME}" /api/setup/status)"
  [[ "$(file_sha256 "${UPGRADE_CONTAINER_NAME}" \
    /data/reclaimerr/secrets.env)" == "${secret_hash_before}" ]]
  (( $(database_count "${UPGRADE_CONTAINER_NAME}" users) >= users_before ))
  (( $(database_count \
    "${UPGRADE_CONTAINER_NAME}" general_settings) >= settings_before ))
  (( $(database_count \
    "${UPGRADE_CONTAINER_NAME}" task_schedules) >= schedules_before ))
  [[ "$(database_application_url "${UPGRADE_CONTAINER_NAME}")" \
    == "http://reclaimerr-upgrade.invalid:8000" ]]
  login_response="$(docker exec "${UPGRADE_CONTAINER_NAME}" \
    curl --fail --silent --show-error \
    --header 'content-type: application/json' \
    --data '{"username":"admin","password":"smoke-password-123"}' \
    http://127.0.0.1:8000/api/auth/login)"
  grep -Fq '"username":"admin"' <<<"${login_response}"
  docker exec "${UPGRADE_CONTAINER_NAME}" python3 -c '
import sqlite3

with sqlite3.connect("/data/reclaimerr/database/reclaimerr.db") as database:
    assert database.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
'
  assert_clean_stop "${UPGRADE_CONTAINER_NAME}"
}

assert_no_external_integration_failure() {
  local name="$1"
  local logs

  # A fresh database has no configured integrations.  Health must still be
  # available and startup must not attempt destructive calls to another host.
  api_body "${name}" /api/info/health >/dev/null
  logs="$(docker logs "${name}" 2>&1)"
  if grep -Eiq \
    'connection refused|Traceback|ERROR.*(radarr|sonarr|plex|jellyfin)' \
    <<<"${logs}"; then
    return 1
  fi
}

configure_unavailable_integration() {
  local name="$1"

  docker exec \
    --env DATA_DIR=/data/reclaimerr \
    --env STATIC_DIR=/data/reclaimerr/static \
    --env AVATARS_DIR=/data/reclaimerr/static/avatars \
    "${name}" python3 -c '
import asyncio

from backend.core.encryption import fer_encrypt
from backend.database import async_db
from backend.database.models import ServiceConfig
from backend.enums import Service

async def configure() -> None:
    async with async_db() as session:
        session.add(
            ServiceConfig(
                service_type=Service.RADARR,
                base_url="http://127.0.0.1:9",
                api_key=fer_encrypt("offline-smoke-key"),
                name="offline-smoke",
                enabled=True,
                extra_settings={"timeout": 1},
                is_main=False,
            )
        )
        await session.commit()

asyncio.run(configure())
'
}

assert_unavailable_integration_tolerated() {
  local name="$1"
  local logs

  api_body "${name}" /api/info/health >/dev/null
  logs="$(docker logs "${name}" 2>&1)"
  grep -Fq 'Radarr service initialization failed after 4 attempts' \
    <<<"${logs}"
}

assert_full_options_contract() {
  local admin_password
  local login_payload
  local login_response
  local logs

  mkdir -p -- "${FULL_DATA_DIR}"
  cp "${SCRIPT_DIR}/options-full.json" "${FULL_DATA_DIR}/options.json"
  chmod 0777 "${FULL_DATA_DIR}"
  admin_password="$(jq -er '.admin_password' \
    "${SCRIPT_DIR}/options-full.json")"
  login_payload="$(jq -cn --arg password "${admin_password}" \
    '{username:"admin", password:$password}')"

  start_container "${FULL_CONTAINER_NAME}" "${FULL_DATA_DIR}"
  wait_for_health "${FULL_CONTAINER_NAME}"
  assert_profile "${FULL_CONTAINER_NAME}"
  grep -Fq '"needs_setup":false' \
    <<<"$(api_body "${FULL_CONTAINER_NAME}" /api/setup/status)"
  login_response="$(docker exec "${FULL_CONTAINER_NAME}" \
    curl --fail --silent --show-error \
    --header 'content-type: application/json' \
    --data "${login_payload}" \
    http://127.0.0.1:8000/api/auth/login)"
  grep -Fq '"username":"admin"' <<<"${login_response}"
  logs="$(docker logs "${FULL_CONTAINER_NAME}" 2>&1)"
  if grep -Fq "${admin_password}" <<<"${logs}"; then
    return 1
  fi
  assert_clean_stop "${FULL_CONTAINER_NAME}"
}

main() {
  local logs
  local secret_hash_before
  local secret_hash_after

  write_options '{
    "timezone": "Europe/Amsterdam",
    "log_level": "INFO",
    "log_retention_days": 7,
    "command_workers": 1,
    "cors_origins": "http://localhost:8000",
    "proxy_trusted_hosts": "127.0.0.1,::1",
    "cookie_secure": false
  }'

  log "starting a fresh app with HA-shaped options"
  start_container "${CONTAINER_NAME}"
  wait_for_running "${CONTAINER_NAME}"
  wait_for_health "${CONTAINER_NAME}"
  assert_profile "${CONTAINER_NAME}"
  assert_api_contract "${CONTAINER_NAME}"
  assert_host_port_contract "${CONTAINER_NAME}"
  assert_no_external_integration_failure "${CONTAINER_NAME}"
  assert_media_contract "${CONTAINER_NAME}"

  docker exec "${CONTAINER_NAME}" bash -c \
    '[[ -f /data/reclaimerr/database/reclaimerr.db ]]'
  docker exec "${CONTAINER_NAME}" bash -c \
    '[[ -f /data/reclaimerr/secrets.env ]]'
  secret_hash_before="$(file_sha256 "${CONTAINER_NAME}" \
    /data/reclaimerr/secrets.env)"
  complete_setup "${CONTAINER_NAME}"
  configure_unavailable_integration "${CONTAINER_NAME}"
  assert_clean_stop "${CONTAINER_NAME}"

  log "checking cold backup and restore"
  copy_cold_backup
  start_container "${RESTORE_CONTAINER_NAME}" "${RESTORE_DATA_DIR}"
  wait_for_health "${RESTORE_CONTAINER_NAME}"
  assert_profile "${RESTORE_CONTAINER_NAME}"
  grep -Fq '"needs_setup":false' \
    <<<"$(api_body "${RESTORE_CONTAINER_NAME}" /api/setup/status)"
  assert_unavailable_integration_tolerated "${RESTORE_CONTAINER_NAME}"
  [[ "$(file_sha256 "${RESTORE_CONTAINER_NAME}" \
    /data/reclaimerr/secrets.env)" == "${secret_hash_before}" ]]
  assert_clean_stop "${RESTORE_CONTAINER_NAME}"

  log "checking database and generated-secret persistence across restart"
  docker start "${CONTAINER_NAME}" >/dev/null
  wait_for_health "${CONTAINER_NAME}"
  assert_unavailable_integration_tolerated "${CONTAINER_NAME}"
  grep -Fq '"needs_setup":false' \
    <<<"$(api_body "${CONTAINER_NAME}" /api/setup/status)"
  secret_hash_after="$(file_sha256 "${CONTAINER_NAME}" \
    /data/reclaimerr/secrets.env)"
  [[ "${secret_hash_before}" == "${secret_hash_after}" ]]
  docker exec "${CONTAINER_NAME}" bash -c \
    '[[ -s /data/reclaimerr/database/reclaimerr.db ]]'

  log "checking invalid options and secret redaction"
  assert_rejected wildcard-proxy \
    '{"proxy_trusted_hosts":"*","admin_password":"'"${SECRET_SENTINEL}"'"}'
  assert_rejected malformed-cors \
    '{"cors_origins":"not-an-origin","admin_password":"'"${SECRET_SENTINEL}"'"}'
  log "checking full options and transient admin bootstrap"
  assert_full_options_contract
  log "checking pinned 0.3.4 to packaged 0.3.5 upgrade"
  assert_upgrade_contract
  logs="$(docker logs "${CONTAINER_NAME}" 2>&1)"
  if grep -Fq "${SECRET_SENTINEL}" <<<"${logs}"; then
    return 1
  fi

  assert_clean_stop "${CONTAINER_NAME}"
  log "all smoke checks passed"
}

main "$@"
