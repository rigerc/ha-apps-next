#!/bin/bash
# Exercise fresh, persistent, configured, and upgraded RomM app containers.

set -euo pipefail

readonly IMAGE="${1:?usage: smoke.sh IMAGE}"
readonly OLD_IMAGE="ghcr.io/rigerc/ha-addon-romm:5.0.0-5@sha256:\
440d8e5855bcb3290b4c7ece85017f7c49f2284e823d4c37f6e0febdf17646e7"
readonly MARIADB_IMAGE="mariadb:11.4.10@sha256:\
3b4dfcc32247eb07adbebec0793afae2a8eafa6860ec523ee56af4d3dec42f7f"
readonly SUPERVISOR_TOKEN="romm-smoke-supervisor-token"
readonly MYSQL_ROOT_PASSWORD="romm-smoke-root-password"
readonly MYSQL_SERVICE_PASSWORD="romm-smoke-service-password"
readonly NETWORK_NAME="romm-smoke-network-$$"
readonly DATABASE_NAME="romm-smoke-database-$$"
readonly SUPERVISOR_NAME="romm-smoke-supervisor-$$"
readonly DEFAULT_NAME="romm-smoke-default-$$"
readonly FULL_NAME="romm-smoke-full-$$"
readonly OLD_UPGRADE_NAME="romm-smoke-old-upgrade-$$"
readonly UPGRADE_NAME="romm-smoke-upgrade-$$"
TEST_ROOT="$(mktemp -d -t romm-smoke.XXXXXX)"
readonly TEST_ROOT
readonly DEFAULT_DATA_DIR="${TEST_ROOT}/default-data"
readonly DEFAULT_SHARE_DIR="${TEST_ROOT}/default-share"
readonly FULL_DATA_DIR="${TEST_ROOT}/full-data"
readonly FULL_SHARE_DIR="${TEST_ROOT}/full-share"
readonly UPGRADE_DATA_DIR="${TEST_ROOT}/upgrade-data"
readonly UPGRADE_SHARE_DIR="${TEST_ROOT}/upgrade-share"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

CONTAINERS=()
DOCKER_SECURITY_ARGS=()

if [[ -n "${APPARMOR_PROFILE:-}" ]]; then
  DOCKER_SECURITY_ARGS+=(--security-opt "apparmor=${APPARMOR_PROFILE}")
fi
readonly -a DOCKER_SECURITY_ARGS

log() {
  printf '[romm-smoke] %s\n' "$*"
}

fail() {
  printf '[romm-smoke] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local name

  for name in "${CONTAINERS[@]}"; do
    docker rm --force --volumes "${name}" >/dev/null 2>&1 || true
  done
  docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
  docker run --rm --entrypoint sh \
    --volume "${TEST_ROOT}:/test:rw" "${IMAGE}" \
    -c 'find /test -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +' \
    >/dev/null 2>&1 || true
  rmdir "${TEST_ROOT}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

prepare_data_dir() {
  local data_dir="$1"
  local share_dir="$2"
  local options_file="$3"
  local database_name="$4"

  mkdir -p -- "${data_dir}" "${share_dir}"
  jq --arg database_name "${database_name}" \
    '.database_name = $database_name' "${options_file}" \
    >"${data_dir}/options.json"
  chmod 0777 "${data_dir}" "${share_dir}"
}

wait_for_mariadb() {
  local attempt

  for ((attempt = 1; attempt <= 120; attempt += 1)); do
    if docker exec "${DATABASE_NAME}" mariadb \
      --user=root \
      --password="${MYSQL_ROOT_PASSWORD}" \
      --execute='SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  docker logs "${DATABASE_NAME}" >&2 || true
  return 1
}

start_dependencies() {
  local grant_sql

  docker network create "${NETWORK_NAME}" >/dev/null

  CONTAINERS+=("${DATABASE_NAME}")
  docker run --detach --name "${DATABASE_NAME}" \
    --network "${NETWORK_NAME}" \
    --network-alias mariadb \
    --env "MARIADB_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}" \
    "${MARIADB_IMAGE}" \
    --log-bin=mysql-bin \
    --server-id=1 >/dev/null
  wait_for_mariadb

  grant_sql="CREATE USER IF NOT EXISTS 'service'@'%' \
IDENTIFIED BY '${MYSQL_SERVICE_PASSWORD}'; \
GRANT ALL PRIVILEGES ON *.* TO 'service'@'%' WITH GRANT OPTION; \
FLUSH PRIVILEGES;"
  docker exec "${DATABASE_NAME}" mariadb \
    --password="${MYSQL_ROOT_PASSWORD}" \
    --execute="${grant_sql}"

  CONTAINERS+=("${SUPERVISOR_NAME}")
  docker run --detach --name "${SUPERVISOR_NAME}" \
    --network "${NETWORK_NAME}" \
    --network-alias supervisor \
    --env "SUPERVISOR_TOKEN=${SUPERVISOR_TOKEN}" \
    --env MYSQL_HOST=mariadb \
    --env MYSQL_PORT=3306 \
    --env MYSQL_USER=service \
    --env "MYSQL_PASSWORD=${MYSQL_SERVICE_PASSWORD}" \
    --volume "${SCRIPT_DIR}/supervisor_mock.py:/supervisor_mock.py:ro" \
    --entrypoint python3 \
    "${IMAGE}" /supervisor_mock.py >/dev/null
}

start_app() {
  local name="$1"
  local image="$2"
  local data_dir="$3"
  local share_dir="$4"

  CONTAINERS+=("${name}")
  docker run --detach --name "${name}" \
    --network "${NETWORK_NAME}" \
    --env "SUPERVISOR_TOKEN=${SUPERVISOR_TOKEN}" \
    --env SUPERVISOR_URL=http://supervisor:8080 \
    --publish 127.0.0.1::8080 \
    --volume "${data_dir}:/data:rw" \
    --volume "${share_dir}:/share:rw" \
    "${DOCKER_SECURITY_ARGS[@]}" \
    "${image}" >/dev/null
}

wait_for_health() {
  local name="$1"
  local expected_version="$2"
  local attempt

  for ((attempt = 1; attempt <= 360; attempt += 1)); do
    if ! docker inspect --format '{{.State.Running}}' "${name}" \
      2>/dev/null | grep -qx true; then
      docker logs "${name}" >&2 || true
      return 1
    fi
    if docker exec "${name}" curl --fail --silent --show-error \
      http://127.0.0.1:8080/api/heartbeat 2>/dev/null \
      | jq -e --arg version "${expected_version}" \
        '.SYSTEM.VERSION == $version' >/dev/null 2>&1; then
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

  for ((attempt = 1; attempt <= 90; attempt += 1)); do
    if docker inspect --format '{{.State.Running}}' "${name}" \
      2>/dev/null | grep -qx false; then
      return 0
    fi
    sleep 1
  done
  docker logs "${name}" >&2 || true
  return 1
}

stop_cleanly() {
  local name="$1"

  docker stop --time 90 "${name}" >/dev/null
  wait_for_stop "${name}"
  [[ "$(docker inspect --format '{{.State.ExitCode}}' "${name}")" == "0" ]] \
    || { docker logs "${name}" >&2 || true; return 1; }
}

container_environment() {
  local name="$1"

  docker exec "${name}" sh -c \
    'tr "\000" "\n" </proc/1/environ'
}

assert_environment() {
  local environment="$1"
  local expected="$2"

  grep -Fqx "${expected}" <<<"${environment}"
}

assert_web_contract() {
  local name="$1"
  local body
  local host_port

  body="$(docker exec "${name}" curl --fail --silent --show-error \
    http://127.0.0.1:8080/)"
  [[ -n "${body}" ]]
  host_port="$(docker port "${name}" 8080/tcp | awk -F: 'NR == 1 {print $NF}')"
  [[ "${host_port}" =~ ^[0-9]+$ ]]
  curl --fail --silent --show-error \
    "http://127.0.0.1:${host_port}/api/heartbeat" >/dev/null
}

assert_profile() {
  local name="$1"

  if [[ -n "${APPARMOR_PROFILE:-}" ]]; then
    docker exec "${name}" grep -Fq "${APPARMOR_PROFILE}" \
      /proc/1/attr/current
  fi
}

database_scalar() {
  local database_name="$1"
  local query="$2"

  docker exec "${DATABASE_NAME}" mariadb \
    --batch --skip-column-names \
    --user=service \
    --password="${MYSQL_SERVICE_PASSWORD}" \
    "${database_name}" \
    --execute="${query}"
}

seed_old_database() {
  local name="$1"
  local auth_secret

  auth_secret="$(docker exec "${name}" cat /data/romm_auth_secret_key)"
  docker exec \
    --env DB_HOST=mariadb \
    --env DB_PORT=3306 \
    --env DB_NAME=romm_upgrade \
    --env DB_USER=service \
    --env "DB_PASSWD=${MYSQL_SERVICE_PASSWORD}" \
    --env ROMM_DB_DRIVER=mariadb \
    --env ROMM_BASE_PATH=/share/romm \
    --env "ROMM_AUTH_SECRET_KEY=${auth_secret}" \
    "${name}" python3 -c '
from handler.database.base_handler import sync_session
from models.platform import Platform
from models.rom import Rom

with sync_session() as session:
    platform = Platform(slug="snes", fs_slug="snes", name="Super Nintendo")
    session.add(platform)
    session.flush()
    for index in range(1, 4):
        session.add(
            Rom(
                fs_name=f"Smoke Game {index}.sfc",
                fs_path="snes",
                fs_size_bytes=index * 1024,
                name=f"Smoke Game {index}",
                slug=f"smoke-game-{index}",
                summary="Upgrade smoke fixture",
                manual_metadata={
                    "genres": ["Action"],
                    "companies": ["Smoke Studio"],
                    "game_modes": ["Single player"],
                },
                regions=["us"],
                languages=["en"],
                tags=["upgrade-smoke"],
                platform_id=platform.id,
            )
        )
    session.commit()
'
}

exercise_migrated_triggers() {
  local name="$1"
  local auth_secret

  auth_secret="$(docker exec "${name}" cat /data/romm_auth_secret_key)"
  docker exec \
    --env DB_HOST=mariadb \
    --env DB_PORT=3306 \
    --env DB_NAME=romm_upgrade \
    --env DB_USER=service \
    --env "DB_PASSWD=${MYSQL_SERVICE_PASSWORD}" \
    --env ROMM_DB_DRIVER=mariadb \
    --env ROMM_BASE_PATH=/share/romm \
    --env "ROMM_AUTH_SECRET_KEY=${auth_secret}" \
    "${name}" python3 -c '
from handler.database.base_handler import sync_session
from models.platform import Platform
from models.rom import Rom

with sync_session() as session:
    platform = session.query(Platform).filter_by(slug="snes").one()
    rom = Rom(
        fs_name="Trigger Game.sfc",
        fs_path="snes",
        fs_size_bytes=4096,
        name="Trigger Game",
        slug="trigger-game",
        summary="Trigger smoke fixture",
        manual_metadata={"genres": ["Puzzle"]},
        regions=["us"],
        languages=["en"],
        tags=["trigger-smoke"],
        platform_id=platform.id,
    )
    session.add(rom)
    session.commit()

with sync_session() as session:
    rom = session.query(Rom).filter_by(slug="trigger-game").one()
    rom.manual_metadata = {"genres": ["Racing"]}
    session.commit()
'
}

assert_migrated_database() {
  local database_name="$1"
  local membership_query
  local revision
  local trigger_count
  local triggers_query

  membership_query="SELECT COUNT(*) FROM virtual_collection_roms \
WHERE type = 'genre' AND name = 'Action';"
  triggers_query="SELECT COUNT(*) FROM TRIGGERS \
WHERE TRIGGER_SCHEMA = '${database_name}' \
AND TRIGGER_NAME IN (\
'roms_facets_after_insert',\
'roms_facets_after_update',\
'virtual_collection_roms_ai',\
'virtual_collection_roms_au'\
);"

  revision="$(database_scalar "${database_name}" \
    'SELECT version_num FROM alembic_version;')"
  [[ "${revision}" == "0103_roms_facets_provider_ids" ]]
  [[ "$(database_scalar "${database_name}" \
    'SELECT COUNT(*) FROM roms;')" == "3" ]]
  [[ "$(database_scalar "${database_name}" \
    'SELECT COUNT(*) FROM roms_facets;')" == "3" ]]
  [[ "$(database_scalar "${database_name}" \
    "${membership_query}")" == "3" ]]
  trigger_count="$(database_scalar information_schema \
    "${triggers_query}")"
  [[ "${trigger_count}" == "4" ]]
}

assert_no_secret_leaks() {
  local name="$1"
  local logs
  local secret

  logs="$(docker logs "${name}" 2>&1)"
  for secret in \
    smoke-igdb-secret-must-not-leak \
    smoke-screenscraper-secret-must-not-leak \
    smoke-ra-secret-must-not-leak \
    smoke-sgdb-secret-must-not-leak \
    smoke-moby-secret-must-not-leak; do
    if grep -Fq "${secret}" <<<"${logs}"; then
      fail "secret appeared in ${name} logs"
    fi
  done
  if grep -Fq '"igdb_client_secret"' <<<"${logs}"; then
    fail "raw options JSON appeared in ${name} logs"
  fi
}

run_default_test() {
  local secret_hash
  local environment

  log "testing a fresh install and persistent restart"
  prepare_data_dir "${DEFAULT_DATA_DIR}" "${DEFAULT_SHARE_DIR}" \
    "${SCRIPT_DIR}/options-default.json" romm_smoke
  start_app "${DEFAULT_NAME}" "${IMAGE}" \
    "${DEFAULT_DATA_DIR}" "${DEFAULT_SHARE_DIR}"
  wait_for_health "${DEFAULT_NAME}" 5.1.0
  assert_profile "${DEFAULT_NAME}"
  assert_web_contract "${DEFAULT_NAME}"
  docker exec "${DEFAULT_NAME}" test -L /romm/library
  [[ "$(docker exec "${DEFAULT_NAME}" readlink /romm/library)" \
    == "/share/romm/library" ]]
  docker exec "${DEFAULT_NAME}" test -f /share/romm/config/config.yml
  docker exec "${DEFAULT_NAME}" test -d /data/redis
  secret_hash="$(docker exec "${DEFAULT_NAME}" \
    sha256sum /data/romm_auth_secret_key)"
  environment="$(container_environment "${DEFAULT_NAME}")"
  assert_environment "${environment}" \
    ENABLE_SCHEDULED_CLEANUP_ORPHANED_RESOURCES=false
  assert_environment "${environment}" ROMM_SESSION_SECURE_COOKIE=false
  docker exec "${DEFAULT_NAME}" python3 -c '
from redis import Redis

Redis(host="127.0.0.1").set("ha-smoke", "persisted")
'
  docker exec "${DEFAULT_NAME}" sh -c \
    'printf "%s\n" persisted >/share/romm/upgrade-sentinel'
  stop_cleanly "${DEFAULT_NAME}"

  docker start "${DEFAULT_NAME}" >/dev/null
  wait_for_health "${DEFAULT_NAME}" 5.1.0
  [[ "$(docker exec "${DEFAULT_NAME}" \
    sha256sum /data/romm_auth_secret_key)" == "${secret_hash}" ]]
  [[ "$(docker exec "${DEFAULT_NAME}" python3 -c '
from redis import Redis

print(Redis(host="127.0.0.1").get("ha-smoke").decode())
')" \
    == "persisted" ]]
  docker exec "${DEFAULT_NAME}" grep -Fqx persisted \
    /share/romm/upgrade-sentinel
  stop_cleanly "${DEFAULT_NAME}"
}

run_full_options_test() {
  local environment

  log "testing all Home Assistant option mappings"
  prepare_data_dir "${FULL_DATA_DIR}" "${FULL_SHARE_DIR}" \
    "${SCRIPT_DIR}/options-full.json" romm_full
  start_app "${FULL_NAME}" "${IMAGE}" \
    "${FULL_DATA_DIR}" "${FULL_SHARE_DIR}"
  wait_for_health "${FULL_NAME}" 5.1.0
  environment="$(container_environment "${FULL_NAME}")"
  assert_environment "${environment}" ROMM_BASE_URL=https://romm.example.com
  assert_environment "${environment}" \
    ENABLE_SCHEDULED_CLEANUP_ORPHANED_RESOURCES=true
  assert_environment "${environment}" ROMM_SESSION_SECURE_COOKIE=true
  assert_environment "${environment}" ENABLE_SCHEDULED_RESCAN=true
  assert_environment "${environment}" SCHEDULED_RESCAN_CRON='15 4 * * 2'
  assert_environment "${environment}" KIOSK_MODE=true
  assert_environment "${environment}" DISABLE_EMULATOR_JS=true
  assert_environment "${environment}" DISABLE_RUFFLE_RS=true
  assert_environment "${environment}" HASHEOUS_API_ENABLED=false
  assert_no_secret_leaks "${FULL_NAME}"
  stop_cleanly "${FULL_NAME}"
}

run_upgrade_test() {
  local old_secret_hash

  log "testing the 5.0.0-5 to 5.1.0-1 database upgrade"
  prepare_data_dir "${UPGRADE_DATA_DIR}" "${UPGRADE_SHARE_DIR}" \
    "${SCRIPT_DIR}/options-default.json" romm_upgrade
  start_app "${OLD_UPGRADE_NAME}" "${OLD_IMAGE}" \
    "${UPGRADE_DATA_DIR}" "${UPGRADE_SHARE_DIR}"
  wait_for_health "${OLD_UPGRADE_NAME}" 5.0.0
  seed_old_database "${OLD_UPGRADE_NAME}"
  [[ "$(database_scalar romm_upgrade 'SELECT COUNT(*) FROM roms;')" \
    == "3" ]]
  old_secret_hash="$(docker exec "${OLD_UPGRADE_NAME}" \
    sha256sum /data/romm_auth_secret_key)"
  stop_cleanly "${OLD_UPGRADE_NAME}"

  start_app "${UPGRADE_NAME}" "${IMAGE}" \
    "${UPGRADE_DATA_DIR}" "${UPGRADE_SHARE_DIR}"
  wait_for_health "${UPGRADE_NAME}" 5.1.0
  assert_profile "${UPGRADE_NAME}"
  assert_migrated_database romm_upgrade
  exercise_migrated_triggers "${UPGRADE_NAME}"
  [[ "$(database_scalar romm_upgrade 'SELECT COUNT(*) FROM roms;')" \
    == "4" ]]
  [[ "$(database_scalar romm_upgrade 'SELECT COUNT(*) FROM roms_facets;')" \
    == "4" ]]
  [[ "$(database_scalar romm_upgrade \
    "SELECT COUNT(*) FROM virtual_collection_roms WHERE name = 'Puzzle';")" \
    == "0" ]]
  [[ "$(database_scalar romm_upgrade \
    "SELECT COUNT(*) FROM virtual_collection_roms WHERE name = 'Racing';")" \
    == "1" ]]
  [[ "$(docker exec "${UPGRADE_NAME}" \
    sha256sum /data/romm_auth_secret_key)" == "${old_secret_hash}" ]]
  stop_cleanly "${UPGRADE_NAME}"
}

main() {
  command -v docker >/dev/null 2>&1 || fail "docker is required"
  command -v jq >/dev/null 2>&1 || fail "jq is required"
  start_dependencies
  run_default_test
  run_full_options_test
  run_upgrade_test
  log "all RomM smoke and upgrade checks passed"
}

main "$@"
