#!/bin/bash
# Docker smoke tests for the self-contained Endurain app image.

set -euo pipefail

readonly IMAGE="${1:?usage: smoke.sh IMAGE}"
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
readonly DEFAULT_NAME="endurain-smoke-default-$$"
readonly FULL_NAME="endurain-smoke-full-$$"
CONTAINERS=()
DOCKER_SECURITY_ARGS=()

if [[ -n "${APPARMOR_PROFILE:-}" ]]; then
  DOCKER_SECURITY_ARGS+=(--security-opt "apparmor=${APPARMOR_PROFILE}")
fi
readonly -a DOCKER_SECURITY_ARGS

log() {
  printf '[smoke] %s\n' "$*"
}

cleanup() {
  local name
  for name in "${CONTAINERS[@]}"; do
    docker rm -f "${name}" >/dev/null 2>&1 || true
  done
  docker run --rm \
    --entrypoint sh \
    --volume "${TEST_ROOT}:/test" \
    "${IMAGE}" -c 'rm -rf /test/*' >/dev/null 2>&1 || true
  rmdir "${TEST_ROOT}" 2>/dev/null || true
}
trap cleanup EXIT

new_data_dir() {
  local name="$1"
  local fixture="$2"
  local path="${TEST_ROOT}/${name}"

  mkdir -p "${path}"
  cp "${fixture}" "${path}/options.json"
  chmod 0755 "${path}"
  printf '%s' "${path}"
}

start_new_container() {
  local name="$1"
  local data_dir="$2"

  CONTAINERS+=("${name}")
  docker run \
    "${DOCKER_SECURITY_ARGS[@]}" \
    --detach \
    --name "${name}" \
    --volume "${data_dir}:/data" \
    "${IMAGE}" >/dev/null
}

wait_for_health() {
  local name="$1"
  local attempt

  for ((attempt = 1; attempt <= 300; attempt += 1)); do
    if ! docker inspect --format '{{.State.Running}}' "${name}" 2>/dev/null | grep -qx true; then
      docker logs "${name}" >&2 || true
      return 1
    fi
    if docker exec "${name}" \
      curl --fail --silent http://127.0.0.1:8080/api/v1/about >/dev/null 2>&1; then
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
    if docker inspect --format '{{.State.Running}}' "${name}" | grep -qx false; then
      return 0
    fi
    sleep 1
  done
  docker logs "${name}" >&2 || true
  return 1
}

assert_clean_stop() {
  local name="$1"
  local logs

  docker stop --time 90 "${name}" >/dev/null
  [[ "$(docker inspect --format '{{.State.ExitCode}}' "${name}")" == "0" ]]
  logs="$(docker logs "${name}" 2>&1)"
  grep -q '\[endurain\] PostgreSQL stopped cleanly' <<<"${logs}"
  grep -q '\[endurain\] Valkey stopped cleanly' <<<"${logs}"
}

assert_rejected() {
  local label="$1"
  local options="$2"
  local expected="$3"
  local name="endurain-smoke-invalid-${label}-$$"
  local data_dir="${TEST_ROOT}/invalid-${label}"

  mkdir -p "${data_dir}"
  printf '%s\n' "${options}" >"${data_dir}/options.json"
  CONTAINERS+=("${name}")
  if docker run \
    "${DOCKER_SECURITY_ARGS[@]}" \
    --name "${name}" \
    --volume "${data_dir}:/data" \
    "${IMAGE}" >"${data_dir}/output.log" 2>&1; then
    printf 'invalid options unexpectedly succeeded: %s\n' "${label}" >&2
    return 1
  fi
  grep -q "${expected}" "${data_dir}/output.log"
}

assert_child_failure() {
  local name="$1"
  local service="$2"
  local logs

  docker start "${name}" >/dev/null
  wait_for_health "${name}"
  docker exec "${name}" sh -c \
    "kill -KILL \"\$(cat /run/endurain/${service}.pid)\""
  wait_for_stop "${name}"
  [[ "$(docker inspect --format '{{.State.ExitCode}}' "${name}")" != "0" ]]
  logs="$(docker logs "${name}" 2>&1)"
  grep -qi 'exited unexpectedly' <<<"${logs}"
}

assert_not_logged() {
  local needle="$1"
  local logs="$2"

  if grep -Fq "${needle}" <<<"${logs}"; then
    printf 'secret or raw option leaked into logs\n' >&2
    return 1
  fi
}

log "starting a fresh app with default options"
default_data="$(new_data_dir default endurain/tests/options-default.json)"
start_new_container "${DEFAULT_NAME}" "${default_data}"
wait_for_health "${DEFAULT_NAME}"

if [[ -n "${APPARMOR_PROFILE:-}" ]]; then
  [[ "$(docker exec "${DEFAULT_NAME}" cat /proc/1/attr/current)" == \
    "${APPARMOR_PROFILE} (enforce)" ]]
fi

docker exec "${DEFAULT_NAME}" su-exec postgres \
  pg_isready --host=/run/postgresql --username=postgres >/dev/null
[[ "$(docker exec "${DEFAULT_NAME}" valkey-cli ping)" == "PONG" ]]
docker exec "${DEFAULT_NAME}" test -f /data/postgresql/PG_VERSION
docker exec "${DEFAULT_NAME}" test -d /data/valkey/appendonlydir
docker exec "${DEFAULT_NAME}" test -d /data/endurain/data/activity_files/bulk_import
docker exec "${DEFAULT_NAME}" test -d /data/endurain/data/activity_media
docker exec "${DEFAULT_NAME}" test -d /data/endurain/data/activity_thumbnails

for secret in db_password secret_key fernet_key; do
  [[ "$(docker exec "${DEFAULT_NAME}" stat -c '%a %u %g' "/data/secrets/${secret}")" == "600 0 0" ]]
  [[ "$(docker exec "${DEFAULT_NAME}" stat -c '%a %u %g' "/run/secrets/${secret}")" == "440 0 1000" ]]
done

secret_hash_before="$(docker exec "${DEFAULT_NAME}" sh -c 'sha256sum /data/secrets/* | sort')"
db_secret="$(docker exec "${DEFAULT_NAME}" cat /data/secrets/db_password)"
jwt_secret="$(docker exec "${DEFAULT_NAME}" cat /data/secrets/secret_key)"
fernet_secret="$(docker exec "${DEFAULT_NAME}" cat /data/secrets/fernet_key)"

docker exec "${DEFAULT_NAME}" valkey-cli set smoke-key persisted >/dev/null
docker exec "${DEFAULT_NAME}" su-exec postgres psql --dbname=endurain \
  --command='CREATE TABLE IF NOT EXISTS ha_smoke (value text); TRUNCATE ha_smoke; INSERT INTO ha_smoke VALUES ('\''persisted'\'');' >/dev/null

log "checking clean stop and persistent restart"
assert_clean_stop "${DEFAULT_NAME}"
docker start "${DEFAULT_NAME}" >/dev/null
wait_for_health "${DEFAULT_NAME}"
[[ "$(docker exec "${DEFAULT_NAME}" sh -c 'sha256sum /data/secrets/* | sort')" == "${secret_hash_before}" ]]
[[ "$(docker exec "${DEFAULT_NAME}" valkey-cli get smoke-key)" == "persisted" ]]
[[ "$(docker exec "${DEFAULT_NAME}" su-exec postgres psql --dbname=endurain --tuples-only --no-align --command='SELECT value FROM ha_smoke;')" == "persisted" ]]

log "checking full option mapping"
full_data="$(new_data_dir full endurain/tests/options-full.json)"
start_new_container "${FULL_NAME}" "${full_data}"
wait_for_health "${FULL_NAME}"
full_environment="$(docker exec "${FULL_NAME}" cat /run/endurain/effective-options)"
grep -qx 'ENDURAIN_HOST=https://endurain.example.com' <<<"${full_environment}"
grep -qx 'ENVIRONMENT=production' <<<"${full_environment}"
grep -qx 'TZ=Europe/Amsterdam' <<<"${full_environment}"
grep -qx 'LOG_LEVEL=debug' <<<"${full_environment}"
grep -qx 'BEHIND_PROXY=true' <<<"${full_environment}"
grep -qx 'TRUSTED_PROXIES=192.168.1.10,proxy.internal' <<<"${full_environment}"
grep -qx 'SMTP_HOST=smtp.example.com' <<<"${full_environment}"
grep -qx 'SMTP_PORT=465' <<<"${full_environment}"
grep -qx 'SMTP_USERNAME=endurain@example.com' <<<"${full_environment}"
grep -qx 'SMTP_FROM=endurain@example.com' <<<"${full_environment}"
grep -qx 'SMTP_SECURE=true' <<<"${full_environment}"
grep -qx 'SMTP_SECURE_TYPE=ssl' <<<"${full_environment}"
grep -qx 'ALLOWED_REDIRECT_SCHEMES=endurain,gadgetbridge' <<<"${full_environment}"
grep -qx 'SSRF_ALLOWED_HOSTS=auth.internal.example.com,10.10.0.0/24' <<<"${full_environment}"
grep -qx 'CSP_ADDITIONAL_CONNECT_SRC=https://auth.example.com,wss://events.example.com' <<<"${full_environment}"
grep -qx 'SMTP_PASSWORD_FILE=/run/secrets/smtp_password' <<<"${full_environment}"
grep -qx 'ALLOW_API_KEY_QUERY_PARAM=true' <<<"${full_environment}"
assert_clean_stop "${FULL_NAME}"

log "checking invalid option rejection"
assert_rejected origin \
  '{"endurain_host":"http://homeassistant.local:8081/path"}' \
  'endurain_host must be an http(s) origin'
assert_rejected proxy \
  '{"endurain_host":"https://endurain.example.com","behind_proxy":true,"trusted_proxies":"*"}' \
  'wildcard is not allowed'
assert_rejected log-level \
  '{"log_level":"verbose"}' \
  'log_level must be critical'
assert_rejected unsafe-combination \
  '{"endurain_host":"https://endurain.example.com","behind_proxy":false,"trusted_proxies":""}' \
  'HTTPS mode requires behind_proxy=true'

log "checking child failure supervision"
assert_clean_stop "${DEFAULT_NAME}"
assert_child_failure "${DEFAULT_NAME}" postgres
assert_child_failure "${DEFAULT_NAME}" valkey
assert_child_failure "${DEFAULT_NAME}" endurain

log "checking logs for secret leakage"
all_logs="$(docker logs "${DEFAULT_NAME}" 2>&1; docker logs "${FULL_NAME}" 2>&1)"
assert_not_logged "${db_secret}" "${all_logs}"
assert_not_logged "${jwt_secret}" "${all_logs}"
assert_not_logged "${fernet_secret}" "${all_logs}"
assert_not_logged 'smoke-smtp-password-do-not-log' "${all_logs}"
assert_not_logged '"smtp_password"' "${all_logs}"

log "all smoke checks passed"
