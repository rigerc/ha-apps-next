#!/usr/bin/env bash

set -Eeuo pipefail

readonly OPTIONS_FILE="/data/options.json"
readonly SUPERVISOR_URL="http://supervisor"
readonly SERVICE_URL="${SUPERVISOR_URL}/services/mysql"
readonly SECRET_FILE="/data/romm_auth_secret_key"
readonly DEFAULT_STORAGE_PATH="/share/romm"
readonly DEFAULT_DATABASE_NAME="romm"
readonly DEFAULT_LOG_LEVEL="INFO"
readonly DEFAULT_SCHEDULED_RESCAN_CRON="0 3 * * *"

log() {
  printf '[romm] %s\n' "$*"
}

fail() {
  printf '[romm] ERROR: %s\n' "$*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "Missing required file: ${path}"
}

require_file "${OPTIONS_FILE}"

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v mariadb >/dev/null 2>&1 || fail "mariadb client is required"

[[ -n "${SUPERVISOR_TOKEN:-}" ]] || fail "SUPERVISOR_TOKEN is not set"

option_string() {
  local key="$1"
  local default_value="${2:-}"

  jq -er --arg key "${key}" --arg default_value "${default_value}" '
    if has($key) and .[$key] != null then
      .[$key]
    else
      $default_value
    end
  ' "${OPTIONS_FILE}"
}

option_bool() {
  local key="$1"
  local default_value="$2"

  jq -r --arg key "${key}" --argjson default_value "${default_value}" '
    if has($key) and .[$key] != null then
      .[$key]
    else
      $default_value
    end
  ' "${OPTIONS_FILE}"
}

optional_string() {
  local key="$1"

  jq -er --arg key "${key}" '
    if has($key) and .[$key] != null and .[$key] != "" then
      .[$key]
    else
      empty
    end
  ' "${OPTIONS_FILE}" 2>/dev/null || true
}

SUPERVISOR_HEADERS=(
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}"
  -H "Content-Type: application/json"
)

STORAGE_PATH="$(option_string "storage_path" "${DEFAULT_STORAGE_PATH}")"
DATABASE_NAME="$(option_string "database_name" "${DEFAULT_DATABASE_NAME}")"
LOG_LEVEL="$(option_string "log_level" "${DEFAULT_LOG_LEVEL}")"
KIOSK_MODE="$(option_bool "kiosk_mode" false)"
ENABLE_RESCAN_ON_FILESYSTEM_CHANGE="$(option_bool "enable_rescan_on_filesystem_change" false)"
ENABLE_SCHEDULED_RESCAN="$(option_bool "enable_scheduled_rescan" false)"
SCHEDULED_RESCAN_CRON="$(option_string "scheduled_rescan_cron" "${DEFAULT_SCHEDULED_RESCAN_CRON}")"
DISABLE_EMULATOR_JS="$(option_bool "disable_emulator_js" false)"
DISABLE_RUFFLE_RS="$(option_bool "disable_ruffle_rs" false)"

case "${STORAGE_PATH}" in
  /share/*) ;;
  *)
    fail "storage_path must stay within /share"
    ;;
esac

if [[ "${DATABASE_NAME}" =~ [^A-Za-z0-9_] ]]; then
  fail "database_name may only contain letters, numbers, and underscores"
fi

MYSQL_PAYLOAD=""
for _ in $(seq 1 30); do
  if MYSQL_PAYLOAD="$(curl -fsSL "${SUPERVISOR_HEADERS[@]}" "${SERVICE_URL}" 2>/dev/null)"; then
    break
  fi
  log "Waiting for Home Assistant mysql service..."
  sleep 2
done

[[ -n "${MYSQL_PAYLOAD}" ]] || fail "Home Assistant mysql service is unavailable"

DB_HOST="$(jq -er '.host' <<<"${MYSQL_PAYLOAD}")"
DB_PORT="$(jq -er '.port' <<<"${MYSQL_PAYLOAD}")"
DB_USER="$(jq -er '.username' <<<"${MYSQL_PAYLOAD}")"
DB_PASSWD="$(jq -er '.password' <<<"${MYSQL_PAYLOAD}")"

mkdir -p \
  "${STORAGE_PATH}" \
  "${STORAGE_PATH}/assets" \
  "${STORAGE_PATH}/config" \
  "${STORAGE_PATH}/library" \
  "${STORAGE_PATH}/resources"

if [[ ! -f "${STORAGE_PATH}/config/config.yml" ]]; then
  printf '{}\n' > "${STORAGE_PATH}/config/config.yml"
fi

if [[ ! -f "${SECRET_FILE}" ]]; then
  python3 - <<'PY' >"${SECRET_FILE}"
import secrets

print(secrets.token_hex(32))
PY
fi

ROMM_AUTH_SECRET_KEY="$(tr -d '\n' <"${SECRET_FILE}")"
[[ -n "${ROMM_AUTH_SECRET_KEY}" ]] || fail "Failed to initialize ROMM auth secret"

if id romm >/dev/null 2>&1; then
  chown -R romm:romm "${STORAGE_PATH}" /data
fi

MYSQL_PASSWORD_FILE="$(mktemp)"
chmod 0600 "${MYSQL_PASSWORD_FILE}"
cat >"${MYSQL_PASSWORD_FILE}" <<EOF
[client]
host=${DB_HOST}
port=${DB_PORT}
user=${DB_USER}
password=${DB_PASSWD}
EOF

cleanup() {
  rm -f "${MYSQL_PASSWORD_FILE}"
}
trap cleanup EXIT

log "Ensuring MariaDB database '${DATABASE_NAME}' exists"
mariadb --defaults-extra-file="${MYSQL_PASSWORD_FILE}" \
  --execute="CREATE DATABASE IF NOT EXISTS \`${DATABASE_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

export DB_HOST
export DB_PORT
export DB_NAME="${DATABASE_NAME}"
export DB_USER
export DB_PASSWD
export ROMM_DB_DRIVER="mariadb"
export ROMM_AUTH_SECRET_KEY
export ROMM_BASE_PATH="${STORAGE_PATH}"
export ROMM_PORT="8080"
export ROMM_BASE_URL="http://0.0.0.0:8080"
export LOGLEVEL="${LOG_LEVEL}"
export KIOSK_MODE
export ENABLE_RESCAN_ON_FILESYSTEM_CHANGE
export ENABLE_SCHEDULED_RESCAN
export SCHEDULED_RESCAN_CRON
export DISABLE_EMULATOR_JS
export DISABLE_RUFFLE_RS

for key in \
  igdb_client_id \
  igdb_client_secret \
  screenscraper_user \
  screenscraper_password \
  retroachievements_api_key \
  steamgriddb_api_key \
  mobygames_api_key; do
  value="$(optional_string "${key}")"
  [[ -n "${value}" ]] || continue

  upper_key="$(tr '[:lower:]' '[:upper:]' <<<"${key}")"
  export "${upper_key}"="${value}"
done

log "Starting RomM"
exec /docker-entrypoint.sh /init
