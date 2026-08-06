#!/bin/bash
# Configure and supervise Endurain, PostgreSQL, and Valkey.

set -euo pipefail

readonly OPTIONS_FILE="/data/options.json"
readonly ENDURAIN_DATA_DIR="/data/endurain/data"
readonly ENDURAIN_LOGS_DIR="/data/endurain/logs"
readonly POSTGRES_DATA_DIR="/data/postgresql"
readonly SECRETS_DIR="/data/secrets"
readonly RUNTIME_DIR="/run/endurain"
readonly RUNTIME_SECRETS_DIR="/run/secrets"
readonly POSTGRES_RUNTIME_DIR="/run/postgresql"
readonly VALKEY_DATA_DIR="/data/valkey"
readonly POSTGRES_MAJOR="18"
readonly SERVICE_RETRIES=120
readonly ENDURAIN_RETRIES=300

POSTGRES_PID=""
VALKEY_PID=""
ENDURAIN_PID=""
SHUTTING_DOWN=false

log() {
  printf '[endurain] %s\n' "$*"
}

fail() {
  printf '[endurain] ERROR: %s\n' "$*" >&2
  exit 1
}

option_string() {
  local key="$1"
  local default_value="$2"

  jq -er \
    --arg key "${key}" \
    --arg default_value "${default_value}" \
    'if has($key) and .[$key] != null then .[$key] else $default_value end
    | if type == "string" then . else error("option must be a string") end' \
    "${OPTIONS_FILE}"
}

option_bool() {
  local key="$1"
  local default_value="$2"

  jq -er \
    --arg key "${key}" \
    --argjson default_value "${default_value}" \
    'if has($key) and .[$key] != null then .[$key] else $default_value end
    | if type == "boolean" then tostring else error("option must be a boolean") end' \
    "${OPTIONS_FILE}"
}

option_int() {
  local key="$1"
  local default_value="$2"

  jq -er \
    --arg key "${key}" \
    --argjson default_value "${default_value}" \
    'if has($key) and .[$key] != null then .[$key] else $default_value end
    | if type == "number" and floor == . then tostring else error("option must be an integer") end' \
    "${OPTIONS_FILE}"
}

validate_origin() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlsplit

value = sys.argv[1]
if any(char.isspace() for char in value):
    raise SystemExit(1)
parsed = urlsplit(value)
if (
    parsed.scheme not in {"http", "https"}
    or not parsed.netloc
    or parsed.hostname is None
    or parsed.username is not None
    or parsed.password is not None
    or parsed.path
    or parsed.query
    or parsed.fragment
):
    raise SystemExit(1)
try:
    parsed.port
except ValueError:
    raise SystemExit(1)
print(parsed.scheme)
PY
}

validate_host_list() {
  python3 - "$1" "$2" <<'PY'
import ipaddress
import re
import sys

mode, value = sys.argv[1:]
hostname = re.compile(
    r"(?=^.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*"
    r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$"
)
for raw in value.split(","):
    entry = raw.strip()
    if not entry:
        continue
    if entry == "*":
        raise SystemExit(1)
    try:
        network = ipaddress.ip_network(entry, strict=False)
        if mode == "ssrf" and network.prefixlen < (8 if network.version == 4 else 32):
            raise SystemExit(1)
        continue
    except ValueError:
        if "/" in entry or re.fullmatch(r"[0-9.]+", entry) or not hostname.fullmatch(entry):
            raise SystemExit(1)
PY
}

validate_scheme_list() {
  local value="$1"
  local entry
  local -a entries

  IFS=',' read -r -a entries <<<"${value}"
  for entry in "${entries[@]}"; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -z "${entry}" ]] && continue
    [[ "${entry}" =~ ^[A-Za-z][A-Za-z0-9+.-]*$ ]] \
      || fail "allowed_redirect_schemes contains an invalid URI scheme"
    [[ "${entry,,}" != "http" && "${entry,,}" != "https" ]] \
      || fail "allowed_redirect_schemes may not include http or https"
  done
}

validate_csp_sources() {
  local value="$1"
  local entry
  local -a entries

  IFS=',' read -r -a entries <<<"${value}"
  for entry in "${entries[@]}"; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -z "${entry}" ]] && continue
    [[ "${entry}" != "*" && "${entry}" != *';'* && "${entry}" != *' '* ]] \
      || fail "csp_additional_connect_src contains an unsafe source"
    [[ "${entry}" =~ ^(https?|wss?)://(\*\.)?[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]] \
      || fail "csp_additional_connect_src entries must be explicit HTTP or WebSocket origins"
  done
}

generate_secret() {
  local path="$1"
  shift

  if [[ ! -s "${path}" ]]; then
    local temporary="${path}.tmp.$$"
    (umask 077; "$@" >"${temporary}")
    mv "${temporary}" "${path}"
  fi
  chmod 0600 "${path}"
}

stage_secret() {
  local source="$1"
  local destination="$2"

  install -o root -g 1000 -m 0440 "${source}" "${destination}"
}

prepare_directories() {
  install -d -o root -g root -m 0700 "${SECRETS_DIR}"
  install -d -o root -g root -m 0755 "${RUNTIME_DIR}"
  install -d -o root -g 1000 -m 0750 "${RUNTIME_SECRETS_DIR}"
  install -d -o postgres -g postgres -m 0700 "${POSTGRES_DATA_DIR}"
  install -d -o postgres -g postgres -m 0770 "${POSTGRES_RUNTIME_DIR}"
  install -d -o valkey -g valkey -m 0750 "${VALKEY_DATA_DIR}"
  install -d -o 1000 -g 1000 -m 0750 "${ENDURAIN_DATA_DIR}" "${ENDURAIN_LOGS_DIR}"
}

prepare_secrets() {
  generate_secret "${SECRETS_DIR}/db_password" openssl rand -hex 32
  generate_secret "${SECRETS_DIR}/secret_key" openssl rand -hex 32
  generate_secret \
    "${SECRETS_DIR}/fernet_key" \
    python3 -c 'import base64, secrets; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())'

  stage_secret "${SECRETS_DIR}/db_password" "${RUNTIME_SECRETS_DIR}/db_password"
  stage_secret "${SECRETS_DIR}/secret_key" "${RUNTIME_SECRETS_DIR}/secret_key"
  stage_secret "${SECRETS_DIR}/fernet_key" "${RUNTIME_SECRETS_DIR}/fernet_key"

  if [[ -n "${SMTP_PASSWORD_VALUE}" ]]; then
    local temporary="${RUNTIME_SECRETS_DIR}/smtp_password.tmp.$$"
    (umask 077; printf '%s\n' "${SMTP_PASSWORD_VALUE}" >"${temporary}")
    chown root:1000 "${temporary}"
    chmod 0440 "${temporary}"
    mv "${temporary}" "${RUNTIME_SECRETS_DIR}/smtp_password"
    export SMTP_PASSWORD_FILE="${RUNTIME_SECRETS_DIR}/smtp_password"
  else
    rm -f "${RUNTIME_SECRETS_DIR}/smtp_password"
  fi
  unset SMTP_PASSWORD_VALUE
}

write_effective_options() {
  {
    printf 'ENDURAIN_HOST=%s\n' "${ENDURAIN_HOST}"
    printf 'ENVIRONMENT=%s\n' "${ENVIRONMENT}"
    printf 'TZ=%s\n' "${TZ}"
    printf 'LOG_LEVEL=%s\n' "${LOG_LEVEL}"
    printf 'BEHIND_PROXY=%s\n' "${BEHIND_PROXY}"
    printf 'TRUSTED_PROXIES=%s\n' "${TRUSTED_PROXIES}"
    printf 'SMTP_HOST=%s\n' "${SMTP_HOST:-}"
    printf 'SMTP_PORT=%s\n' "${SMTP_PORT}"
    printf 'SMTP_USERNAME=%s\n' "${SMTP_USERNAME:-}"
    printf 'SMTP_FROM=%s\n' "${SMTP_FROM:-}"
    printf 'SMTP_SECURE=%s\n' "${SMTP_SECURE}"
    printf 'SMTP_SECURE_TYPE=%s\n' "${SMTP_SECURE_TYPE}"
    printf 'ALLOWED_REDIRECT_SCHEMES=%s\n' "${ALLOWED_REDIRECT_SCHEMES:-}"
    printf 'SSRF_ALLOWED_HOSTS=%s\n' "${SSRF_ALLOWED_HOSTS:-}"
    printf 'CSP_ADDITIONAL_CONNECT_SRC=%s\n' "${CSP_ADDITIONAL_CONNECT_SRC:-}"
    printf 'ALLOW_API_KEY_QUERY_PARAM=%s\n' "${ALLOW_API_KEY_QUERY_PARAM}"
    [[ -z "${SMTP_PASSWORD_FILE:-}" ]] \
      || printf 'SMTP_PASSWORD_FILE=%s\n' "${SMTP_PASSWORD_FILE}"
  } >"${RUNTIME_DIR}/effective-options"
  chmod 0444 "${RUNTIME_DIR}/effective-options"
}

load_options() {
  local scheme

  [[ -f "${OPTIONS_FILE}" ]] || fail "Missing Home Assistant options file: ${OPTIONS_FILE}"
  jq -e 'type == "object"' "${OPTIONS_FILE}" >/dev/null \
    || fail "Home Assistant options must be a JSON object"

  ENDURAIN_HOST_VALUE="$(option_string endurain_host 'http://homeassistant.local:8081')" \
    || fail "endurain_host must be a string"
  TIMEZONE_VALUE="$(option_string timezone UTC)" \
    || fail "timezone must be a string"
  LOG_LEVEL_VALUE="$(option_string log_level info)" \
    || fail "log_level must be a string"
  BEHIND_PROXY_VALUE="$(option_bool behind_proxy false)" \
    || fail "behind_proxy must be a Boolean"
  TRUSTED_PROXIES_VALUE="$(option_string trusted_proxies '')" \
    || fail "trusted_proxies must be a comma-separated string"
  SMTP_HOST_VALUE="$(option_string smtp_host '')" || fail "smtp_host must be a string"
  SMTP_PORT_VALUE="$(option_int smtp_port 587)" || fail "smtp_port must be an integer"
  SMTP_USERNAME_VALUE="$(option_string smtp_username '')" || fail "smtp_username must be a string"
  SMTP_PASSWORD_VALUE="$(option_string smtp_password '')" || fail "smtp_password must be a string"
  SMTP_FROM_VALUE="$(option_string smtp_from '')" || fail "smtp_from must be a string"
  SMTP_SECURE_VALUE="$(option_bool smtp_secure true)" || fail "smtp_secure must be a Boolean"
  SMTP_SECURE_TYPE_VALUE="$(option_string smtp_secure_type starttls)" \
    || fail "smtp_secure_type must be a string"
  ALLOWED_REDIRECT_SCHEMES_VALUE="$(option_string allowed_redirect_schemes '')" \
    || fail "allowed_redirect_schemes must be a string"
  SSRF_ALLOWED_HOSTS_VALUE="$(option_string ssrf_allowed_hosts '')" \
    || fail "ssrf_allowed_hosts must be a string"
  CSP_ADDITIONAL_CONNECT_SRC_VALUE="$(option_string csp_additional_connect_src '')" \
    || fail "csp_additional_connect_src must be a string"
  ALLOW_API_KEY_QUERY_PARAM_VALUE="$(option_bool allow_api_key_query_param false)" \
    || fail "allow_api_key_query_param must be a Boolean"

  scheme="$(validate_origin "${ENDURAIN_HOST_VALUE}")" \
    || fail "endurain_host must be an http(s) origin without a path, query, fragment, credentials, or trailing slash"
  [[ "${TIMEZONE_VALUE}" != *'..'* && -f "/usr/share/zoneinfo/${TIMEZONE_VALUE}" ]] \
    || fail "timezone must name an installed IANA time zone"
  [[ "${LOG_LEVEL_VALUE}" =~ ^(critical|error|warning|info|debug|trace)$ ]] \
    || fail "log_level must be critical, error, warning, info, debug, or trace"
  ((SMTP_PORT_VALUE >= 1 && SMTP_PORT_VALUE <= 65535)) \
    || fail "smtp_port must be between 1 and 65535"
  [[ "${SMTP_SECURE_TYPE_VALUE}" =~ ^(starttls|ssl)$ ]] \
    || fail "smtp_secure_type must be starttls or ssl"

  validate_host_list proxy "${TRUSTED_PROXIES_VALUE}" \
    || fail "trusted_proxies entries must be explicit IPs, CIDRs, or hostnames; wildcard is not allowed"
  validate_host_list ssrf "${SSRF_ALLOWED_HOSTS_VALUE}" \
    || fail "ssrf_allowed_hosts contains an invalid or overly broad entry"
  validate_scheme_list "${ALLOWED_REDIRECT_SCHEMES_VALUE}"
  validate_csp_sources "${CSP_ADDITIONAL_CONNECT_SRC_VALUE}"

  if [[ "${scheme}" == "http" ]]; then
    [[ "${BEHIND_PROXY_VALUE}" == "false" && -z "${TRUSTED_PROXIES_VALUE}" ]] \
      || fail "HTTP mode is for direct trusted-LAN access; disable behind_proxy and clear trusted_proxies"
    ENVIRONMENT_VALUE="development"
  else
    [[ "${BEHIND_PROXY_VALUE}" == "true" && "${TRUSTED_PROXIES_VALUE}" =~ [A-Za-z0-9] ]] \
      || fail "HTTPS mode requires behind_proxy=true and explicit trusted_proxies"
    ENVIRONMENT_VALUE="production"
  fi

  export ENDURAIN_HOST="${ENDURAIN_HOST_VALUE}"
  export TZ="${TIMEZONE_VALUE}"
  export LOG_LEVEL="${LOG_LEVEL_VALUE}"
  export BEHIND_PROXY="${BEHIND_PROXY_VALUE}"
  export TRUSTED_PROXIES="${TRUSTED_PROXIES_VALUE}"
  export ENVIRONMENT="${ENVIRONMENT_VALUE}"
  export SMTP_PORT="${SMTP_PORT_VALUE}"
  export SMTP_SECURE="${SMTP_SECURE_VALUE}"
  export SMTP_SECURE_TYPE="${SMTP_SECURE_TYPE_VALUE}"
  export ALLOW_API_KEY_QUERY_PARAM="${ALLOW_API_KEY_QUERY_PARAM_VALUE}"

  [[ -z "${SMTP_HOST_VALUE}" ]] || export SMTP_HOST="${SMTP_HOST_VALUE}"
  [[ -z "${SMTP_USERNAME_VALUE}" ]] || export SMTP_USERNAME="${SMTP_USERNAME_VALUE}"
  [[ -z "${SMTP_FROM_VALUE}" ]] || export SMTP_FROM="${SMTP_FROM_VALUE}"
  [[ -z "${ALLOWED_REDIRECT_SCHEMES_VALUE}" ]] \
    || export ALLOWED_REDIRECT_SCHEMES="${ALLOWED_REDIRECT_SCHEMES_VALUE}"
  [[ -z "${SSRF_ALLOWED_HOSTS_VALUE}" ]] || export SSRF_ALLOWED_HOSTS="${SSRF_ALLOWED_HOSTS_VALUE}"
  [[ -z "${CSP_ADDITIONAL_CONNECT_SRC_VALUE}" ]] \
    || export CSP_ADDITIONAL_CONNECT_SRC="${CSP_ADDITIONAL_CONNECT_SRC_VALUE}"
}

initialize_postgres() {
  if [[ -f "${POSTGRES_DATA_DIR}/PG_VERSION" ]]; then
    [[ "$(<"${POSTGRES_DATA_DIR}/PG_VERSION")" == "${POSTGRES_MAJOR}" ]] \
      || fail "PostgreSQL data uses major version $(<"${POSTGRES_DATA_DIR}/PG_VERSION"); restore a compatible backup or perform an explicit migration to PostgreSQL ${POSTGRES_MAJOR}"
    return
  fi

  [[ -z "$(find "${POSTGRES_DATA_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]] \
    || fail "PostgreSQL data directory is non-empty but has no PG_VERSION file"

  log "Initializing PostgreSQL ${POSTGRES_MAJOR}"
  su-exec postgres initdb \
    --pgdata="${POSTGRES_DATA_DIR}" \
    --encoding=UTF8 \
    --locale=C \
    --auth-local=peer \
    --auth-host=scram-sha-256 >/dev/null

  cat >"${POSTGRES_DATA_DIR}/pg_hba.conf" <<'EOF'
local all postgres peer
local all all reject
host all endurain 127.0.0.1/32 scram-sha-256
host all all 127.0.0.1/32 reject
host all all ::1/128 reject
EOF
  chown postgres:postgres "${POSTGRES_DATA_DIR}/pg_hba.conf"
  chmod 0600 "${POSTGRES_DATA_DIR}/pg_hba.conf"
}

start_postgres() {
  su-exec postgres postgres \
    -D "${POSTGRES_DATA_DIR}" \
    -c "listen_addresses=127.0.0.1" \
    -c "port=5432" \
    -c "unix_socket_directories=${POSTGRES_RUNTIME_DIR}" &
  POSTGRES_PID=$!
  printf '%s\n' "${POSTGRES_PID}" >"${RUNTIME_DIR}/postgres.pid"
}

wait_for_postgres() {
  local attempt
  for ((attempt = 1; attempt <= SERVICE_RETRIES; attempt += 1)); do
    kill -0 "${POSTGRES_PID}" 2>/dev/null || return 1
    if su-exec postgres pg_isready \
      --host="${POSTGRES_RUNTIME_DIR}" \
      --port=5432 \
      --username=postgres >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

configure_postgres() {
  local db_password
  db_password="$(<"${SECRETS_DIR}/db_password")"
  {
    printf "SELECT 'CREATE ROLE endurain LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'endurain') \\gexec\n"
    printf "ALTER ROLE endurain PASSWORD '%s';\n" "${db_password}"
    printf "SELECT 'CREATE DATABASE endurain OWNER endurain' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'endurain') \\gexec\n"
  } | su-exec postgres psql \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --dbname=postgres >/dev/null
  unset db_password
}

start_valkey() {
  su-exec valkey valkey-server /usr/local/etc/valkey/valkey.conf &
  VALKEY_PID=$!
  printf '%s\n' "${VALKEY_PID}" >"${RUNTIME_DIR}/valkey.pid"
}

wait_for_valkey() {
  local attempt
  for ((attempt = 1; attempt <= SERVICE_RETRIES; attempt += 1)); do
    kill -0 "${VALKEY_PID}" 2>/dev/null || return 1
    if [[ "$(valkey-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null)" == "PONG" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

start_endurain() {
  su-exec appuser /docker-entrypoint.d/start.sh &
  ENDURAIN_PID=$!
  printf '%s\n' "${ENDURAIN_PID}" >"${RUNTIME_DIR}/endurain.pid"
}

wait_for_endurain() {
  local attempt
  for ((attempt = 1; attempt <= ENDURAIN_RETRIES; attempt += 1)); do
    kill -0 "${POSTGRES_PID}" 2>/dev/null || return 1
    kill -0 "${VALKEY_PID}" 2>/dev/null || return 1
    kill -0 "${ENDURAIN_PID}" 2>/dev/null || return 1
    if curl --fail --silent --show-error \
      http://127.0.0.1:8080/api/v1/about >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_exit() {
  local pid="$1"
  local timeout="$2"
  local attempt

  for ((attempt = 0; attempt < timeout; attempt += 1)); do
    kill -0 "${pid}" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "${pid}" 2>/dev/null; then
    kill -KILL "${pid}" 2>/dev/null || true
  fi
  wait "${pid}" 2>/dev/null || true
}

shutdown_services() {
  local signal="${1:-TERM}"

  [[ "${SHUTTING_DOWN}" == "false" ]] || return 0
  SHUTTING_DOWN=true
  trap - TERM INT HUP
  log "Stopping services"

  if [[ -n "${ENDURAIN_PID}" ]] && kill -0 "${ENDURAIN_PID}" 2>/dev/null; then
    kill -s "${signal}" "${ENDURAIN_PID}" 2>/dev/null || true
    wait_for_exit "${ENDURAIN_PID}" 20
  fi

  if [[ -n "${POSTGRES_PID}" ]] && kill -0 "${POSTGRES_PID}" 2>/dev/null; then
    kill -s "${signal}" "${POSTGRES_PID}" 2>/dev/null || true
    if kill -0 "${POSTGRES_PID}" 2>/dev/null; then
      su-exec postgres pg_ctl \
        --pgdata="${POSTGRES_DATA_DIR}" \
        --mode=fast \
        --wait \
        --timeout=60 stop >/dev/null 2>&1 || true
    fi
    wait_for_exit "${POSTGRES_PID}" 65
    log "PostgreSQL stopped cleanly"
  fi

  if [[ -n "${VALKEY_PID}" ]] && kill -0 "${VALKEY_PID}" 2>/dev/null; then
    kill -s "${signal}" "${VALKEY_PID}" 2>/dev/null || true
    if kill -0 "${VALKEY_PID}" 2>/dev/null; then
      valkey-cli -h 127.0.0.1 -p 6379 shutdown save >/dev/null 2>&1 || true
    fi
    wait_for_exit "${VALKEY_PID}" 20
    log "Valkey stopped cleanly"
  fi
}

on_signal() {
  local signal="$1"
  shutdown_services "${signal}"
  exit 0
}

on_exit() {
  local status=$?
  trap - EXIT
  if [[ "${SHUTTING_DOWN}" == "false" ]]; then
    shutdown_services TERM
  fi
  exit "${status}"
}

monitor_services() {
  local exited_pid=""
  local status

  set +e
  wait -n -p exited_pid "${POSTGRES_PID}" "${VALKEY_PID}" "${ENDURAIN_PID}"
  status=$?
  set -e

  [[ "${status}" -ne 0 ]] || status=1
  case "${exited_pid}" in
    "${POSTGRES_PID}") log "PostgreSQL exited unexpectedly" ;;
    "${VALKEY_PID}") log "Valkey exited unexpectedly" ;;
    "${ENDURAIN_PID}") log "Endurain exited unexpectedly" ;;
    *) log "A child service exited unexpectedly" ;;
  esac
  shutdown_services TERM
  return "${status}"
}

main() {
  load_options
  prepare_directories
  prepare_secrets
  write_effective_options
  initialize_postgres

  export DB_HOST="127.0.0.1"
  export DB_PORT="5432"
  export DB_USER="endurain"
  export DB_DATABASE="endurain"
  export DB_SSLMODE="disable"
  export DB_PASSWORD_FILE="${RUNTIME_SECRETS_DIR}/db_password"
  export SECRET_KEY_FILE="${RUNTIME_SECRETS_DIR}/secret_key"
  export FERNET_KEY_FILE="${RUNTIME_SECRETS_DIR}/fernet_key"
  export DATA_DIR="${ENDURAIN_DATA_DIR}"
  export LOGS_DIR="${ENDURAIN_LOGS_DIR}"
  export RATE_LIMIT_STORAGE_URI="redis://127.0.0.1:6379/0"
  export AUTH_SECURITY_STORAGE_URI="redis://127.0.0.1:6379/0"

  trap 'on_signal TERM' TERM
  trap 'on_signal INT' INT
  trap 'on_signal HUP' HUP
  trap on_exit EXIT

  start_postgres
  wait_for_postgres || fail "PostgreSQL did not become ready"
  configure_postgres

  start_valkey
  wait_for_valkey || fail "Valkey did not become ready"

  start_endurain
  wait_for_endurain || fail "Endurain did not become ready"
  log "Endurain is ready on port 8080"

  monitor_services
}

main "$@"
