#!/bin/bash
#
# Configure RomM from Home Assistant app options and start upstream RomM.

set -euo pipefail

readonly OPTIONS_FILE="/data/options.json"
readonly SECRET_FILE="/data/romm_auth_secret_key"
readonly REDIS_DATA_PATH="/data/redis"
readonly SUPERVISOR_URL="${SUPERVISOR_URL:-http://supervisor}"
readonly MYSQL_SERVICE_URL="${SUPERVISOR_URL}/services/mysql"
readonly DEFAULT_STORAGE_PATH="/share/romm"
readonly DEFAULT_DATABASE_NAME="romm"
readonly DEFAULT_LOG_LEVEL="INFO"
readonly DEFAULT_RESCAN_CRON="0 3 * * *"
readonly SERVICE_RETRIES=60
readonly DATABASE_RETRIES=60

MYSQL_CLIENT_FILE=""

log() {
  printf '[romm] %s\n' "$*"
}

fail() {
  printf '[romm] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${MYSQL_CLIENT_FILE}" ]]; then
    rm -f "${MYSQL_CLIENT_FILE}"
  fi
}

option_string() {
  local key="$1"
  local default_value="$2"

  jq -er \
    --arg key "${key}" \
    --arg default_value "${default_value}" \
    'if has($key) and .[$key] != null then
      .[$key]
    else
      $default_value
    end' \
    "${OPTIONS_FILE}"
}

option_bool() {
  local key="$1"
  local default_value="$2"

  jq -r \
    --arg key "${key}" \
    --argjson default_value "${default_value}" \
    'if has($key) and .[$key] != null then
      .[$key]
    else
      $default_value
    end' \
    "${OPTIONS_FILE}"
}

optional_string() {
  local key="$1"

  jq -er \
    --arg key "${key}" \
    'select(has($key) and .[$key] != null and .[$key] != "")
    | .[$key]' \
    "${OPTIONS_FILE}" 2>/dev/null || true
}

service_field() {
  local response="$1"
  local field="$2"

  jq -er \
    --arg field "${field}" \
    '(.data // .)[$field] | select(. != null and . != "")' \
    <<<"${response}"
}

wait_for_mysql_service() {
  local response=""
  local attempt

  for ((attempt = 1; attempt <= SERVICE_RETRIES; attempt += 1)); do
    if response="$(
      curl \
        --fail \
        --silent \
        --show-error \
        --header "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        --header "Content-Type: application/json" \
        "${MYSQL_SERVICE_URL}" 2>/dev/null
    )" && service_field "${response}" "host" >/dev/null; then
      printf '%s' "${response}"
      return 0
    fi

    log \
      "Waiting for the Home Assistant MariaDB service" \
      "(${attempt}/${SERVICE_RETRIES})..." >&2
    sleep 2
  done

  return 1
}

write_mysql_client_file() {
  local host="$1"
  local port="$2"
  local user="$3"
  local password="$4"

  MYSQL_CLIENT_FILE="$(mktemp)"
  chmod 0600 "${MYSQL_CLIENT_FILE}"
  {
    printf '[client]\n'
    printf 'host=%s\n' "${host}"
    printf 'port=%s\n' "${port}"
    printf 'user=%s\n' "${user}"
    printf 'password=%s\n' "${password}"
  } >"${MYSQL_CLIENT_FILE}"
}

wait_for_database() {
  local attempt

  for ((attempt = 1; attempt <= DATABASE_RETRIES; attempt += 1)); do
    if mariadb \
      --defaults-extra-file="${MYSQL_CLIENT_FILE}" \
      --execute="SELECT 1" >/dev/null 2>&1; then
      return 0
    fi

    log "Waiting for MariaDB (${attempt}/${DATABASE_RETRIES})..."
    sleep 2
  done

  return 1
}

create_auth_secret() {
  if [[ ! -s "${SECRET_FILE}" ]]; then
    umask 077
    python3 -c \
      'import secrets; print(secrets.token_hex(32))' >"${SECRET_FILE}"
  fi

  chmod 0600 "${SECRET_FILE}"
}

export_optional_secret() {
  local option_name="$1"
  local environment_name="$2"
  local value

  value="$(optional_string "${option_name}")"
  if [[ -n "${value}" ]]; then
    export "${environment_name}=${value}"
  fi
}

main() {
  local storage_path
  local database_name
  local log_level
  local mysql_response
  local db_host
  local db_port
  local db_user
  local db_password
  local base_url

  [[ -f "${OPTIONS_FILE}" ]] \
    || fail "Missing Home Assistant options file: ${OPTIONS_FILE}"
  [[ -n "${SUPERVISOR_TOKEN:-}" ]] \
    || fail "SUPERVISOR_TOKEN is not set"

  storage_path="$(
    option_string "storage_path" "${DEFAULT_STORAGE_PATH}"
  )"
  storage_path="$(
    python3 -c \
      'import os, sys; print(os.path.realpath(sys.argv[1]))' \
      "${storage_path}"
  )"
  database_name="$(
    option_string "database_name" "${DEFAULT_DATABASE_NAME}"
  )"
  log_level="$(option_string "log_level" "${DEFAULT_LOG_LEVEL}")"

  case "${storage_path}" in
    /share/*) ;;
    *) fail "storage_path must be a directory below /share" ;;
  esac

  if [[ -z "${database_name}" ]] \
    || [[ "${database_name}" =~ [^A-Za-z0-9_] ]]; then
    fail "database_name may contain only letters, numbers, and underscores"
  fi

  mysql_response="$(wait_for_mysql_service)" \
    || fail "The Home Assistant MariaDB service is unavailable"
  db_host="$(service_field "${mysql_response}" "host")"
  db_port="$(service_field "${mysql_response}" "port")"
  db_user="$(service_field "${mysql_response}" "username")"
  db_password="$(service_field "${mysql_response}" "password")"

  write_mysql_client_file \
    "${db_host}" \
    "${db_port}" \
    "${db_user}" \
    "${db_password}"
  wait_for_database || fail "MariaDB did not become ready"

  log "Ensuring MariaDB database '${database_name}' exists"
  mariadb \
    --defaults-extra-file="${MYSQL_CLIENT_FILE}" \
    --execute="CREATE DATABASE IF NOT EXISTS \`${database_name}\`
      CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

  mkdir -p \
    "${storage_path}/assets" \
    "${storage_path}/config" \
    "${storage_path}/library" \
    "${storage_path}/resources" \
    "${storage_path}/sync" \
    "${REDIS_DATA_PATH}"

  if [[ ! -f "${storage_path}/config/config.yml" ]]; then
    printf '{}\n' >"${storage_path}/config/config.yml"
  fi

  create_auth_secret

  KIOSK_MODE="$(option_bool "kiosk_mode" false)"
  ENABLE_RESCAN_ON_FILESYSTEM_CHANGE="$(
    option_bool "enable_rescan_on_filesystem_change" false
  )"
  ENABLE_SCHEDULED_RESCAN="$(
    option_bool "enable_scheduled_rescan" false
  )"
  SCHEDULED_RESCAN_CRON="$(
    option_string "scheduled_rescan_cron" "${DEFAULT_RESCAN_CRON}"
  )"
  DISABLE_EMULATOR_JS="$(option_bool "disable_emulator_js" false)"
  DISABLE_RUFFLE_RS="$(option_bool "disable_ruffle_rs" false)"
  HASHEOUS_API_ENABLED="$(option_bool "hasheous_api_enabled" true)"

  export DB_HOST="${db_host}"
  export DB_PORT="${db_port}"
  export DB_NAME="${database_name}"
  export DB_USER="${db_user}"
  export DB_PASSWD="${db_password}"
  export ROMM_DB_DRIVER="mariadb"
  export ROMM_AUTH_SECRET_KEY_FILE="${SECRET_FILE}"
  export ROMM_BASE_PATH="${storage_path}"
  export ROMM_PORT="8080"
  export LOGLEVEL="${log_level}"
  export KIOSK_MODE
  export ENABLE_RESCAN_ON_FILESYSTEM_CHANGE
  export ENABLE_SCHEDULED_RESCAN
  export SCHEDULED_RESCAN_CRON
  export DISABLE_EMULATOR_JS
  export DISABLE_RUFFLE_RS
  export HASHEOUS_API_ENABLED

  base_url="$(optional_string "base_url")"
  if [[ -n "${base_url}" ]]; then
    export ROMM_BASE_URL="${base_url}"
  fi

  export_optional_secret "igdb_client_id" "IGDB_CLIENT_ID"
  export_optional_secret "igdb_client_secret" "IGDB_CLIENT_SECRET"
  export_optional_secret "screenscraper_user" "SCREENSCRAPER_USER"
  export_optional_secret "screenscraper_password" "SCREENSCRAPER_PASSWORD"
  export_optional_secret \
    "retroachievements_api_key" \
    "RETROACHIEVEMENTS_API_KEY"
  export_optional_secret "steamgriddb_api_key" "STEAMGRIDDB_API_KEY"
  export_optional_secret "mobygames_api_key" "MOBYGAMES_API_KEY"

  cleanup
  trap - EXIT

  log "Starting RomM 5.0.0"
  exec /docker-entrypoint.sh /init
}

trap cleanup EXIT
main "$@"
