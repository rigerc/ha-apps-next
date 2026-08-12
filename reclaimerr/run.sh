#!/bin/bash
#
# Configure Reclaimerr from Home Assistant app options and start its API.

set -euo pipefail

readonly OPTIONS_FILE="/data/options.json"
readonly DATA_DIR="/data/reclaimerr"
readonly STATIC_DIR="${DATA_DIR}/static"
readonly AVATARS_DIR="${STATIC_DIR}/avatars"
readonly FRONTEND_DIST="/app/frontend/dist"
readonly API_HOST="0.0.0.0"
readonly API_PORT="8000"

log() {
  printf '[reclaimerr] %s\n' "$*"
}

fail() {
  printf '[reclaimerr] ERROR: %s\n' "$*" >&2
  exit 1
}

option_value() {
  local key="$1"
  local expected_type="$2"
  local default_value="$3"

  python3 - "${OPTIONS_FILE}" "${key}" "${expected_type}" \
    "${default_value}" <<'PY'
import json
import sys

path, key, expected_type, default_text = sys.argv[1:]
with open(path, encoding="utf-8") as options_file:
    options = json.load(options_file)

if not isinstance(options, dict):
    raise SystemExit("options must be an object")

if expected_type == "string":
    default_value = default_text
elif expected_type == "boolean":
    default_value = default_text == "true"
elif expected_type == "integer":
    default_value = int(default_text)
else:
    raise SystemExit("unsupported option type")

value = options.get(key, default_value)
if value is None:
    value = default_value

valid = {
    "string": type(value) is str,
    "boolean": type(value) is bool,
    "integer": type(value) is int,
}
if not valid[expected_type]:
    raise SystemExit(f"option {key} must be a {expected_type}")

if expected_type == "boolean":
    print(str(value).lower())
else:
    print(value)
PY
}

validate_timezone() {
  local timezone="$1"

  python3 - "${timezone}" <<'PY'
import sys
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

try:
    ZoneInfo(sys.argv[1])
except (ValueError, ZoneInfoNotFoundError):
    raise SystemExit(1)
PY
}

validate_origins() {
  local origins="$1"

  python3 - "${origins}" <<'PY'
import sys
from urllib.parse import urlsplit

entries = [item.strip() for item in sys.argv[1].split(",")]
if not entries or any(not item for item in entries):
    raise SystemExit(1)

for origin in entries:
    parsed = urlsplit(origin)
    if (
        any(char.isspace() for char in origin)
        or parsed.scheme not in {"http", "https"}
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

print(",".join(entries))
PY
}

validate_proxy_hosts() {
  local hosts="$1"

  python3 - "${hosts}" <<'PY'
import ipaddress
import sys

entries = [item.strip() for item in sys.argv[1].split(",")]
if not entries or any(not item for item in entries):
    raise SystemExit(1)

networks = []
for entry in entries:
    if entry == "*":
        raise SystemExit(1)
    try:
        network = ipaddress.ip_network(entry, strict=False)
    except ValueError:
        raise SystemExit(1)
    if network.prefixlen == 0:
        raise SystemExit(1)
    networks.append(str(network))

print(",".join(networks))
PY
}

load_options() {
  local timezone
  local log_level
  local log_retention_days
  local command_workers
  local cors_origins
  local proxy_trusted_hosts
  local cookie_secure
  local admin_password

  [[ -f "${OPTIONS_FILE}" ]] \
    || fail "Missing Home Assistant options file: ${OPTIONS_FILE}"

  timezone="$(option_value timezone string UTC)" \
    || fail "timezone must be a string"
  validate_timezone "${timezone}" \
    || fail "timezone must be a valid IANA timezone"

  log_level="$(option_value log_level string INFO)" \
    || fail "log_level must be a string"
  log_level="${log_level^^}"
  [[ "${log_level}" =~ ^(DEBUG|INFO|WARNING|ERROR|CRITICAL)$ ]] \
    || fail "log_level must be DEBUG, INFO, WARNING, ERROR, or CRITICAL"

  log_retention_days="$(option_value log_retention_days integer 30)" \
    || fail "log_retention_days must be an integer"
  (( log_retention_days >= 1 )) \
    || fail "log_retention_days must be at least 1"

  command_workers="$(option_value command_workers integer 2)" \
    || fail "command_workers must be an integer"
  (( command_workers >= 1 && command_workers <= 8 )) \
    || fail "command_workers must be between 1 and 8"

  cors_origins="$(
    option_value cors_origins string "http://homeassistant.local:8000"
  )" \
    || fail "cors_origins must be a string"
  cors_origins="$(validate_origins "${cors_origins}")" \
    || fail "cors_origins must contain explicit http(s) origins"

  proxy_trusted_hosts="$(
    option_value proxy_trusted_hosts string "127.0.0.1,::1"
  )" || fail "proxy_trusted_hosts must be a string"
  proxy_trusted_hosts="$(validate_proxy_hosts "${proxy_trusted_hosts}")" \
    || fail "proxy_trusted_hosts must contain explicit IPs or CIDRs"

  cookie_secure="$(option_value cookie_secure boolean false)" \
    || fail "cookie_secure must be a Boolean"
  admin_password="$(option_value admin_password string "")" \
    || fail "admin_password must be a string"
  if [[ -n "${admin_password}" ]] \
    && (( ${#admin_password} < 3 || ${#admin_password} > 64 )); then
    fail "admin_password must be between 3 and 64 characters"
  fi

  export DATA_DIR STATIC_DIR AVATARS_DIR FRONTEND_DIST API_HOST API_PORT
  # Keep TZ out of the upstream entrypoint so it does not mutate read-only
  # /etc files. The child command restores TZ before starting Reclaimerr.
  export RECLAIMERR_RUNTIME_TZ="${timezone}"
  unset TZ
  export LOG_LEVEL="${log_level}"
  export LOG_RETENTION_DAYS="${log_retention_days}"
  export RECLAIMERR_COMMAND_WORKERS="${command_workers}"
  export CORS_ORIGINS="${cors_origins}"
  export PROXY_TRUSTED_HOSTS="${proxy_trusted_hosts}"
  export COOKIE_SECURE="${cookie_secure}"
  if [[ -n "${admin_password}" ]]; then
    export ADMIN_PASSWORD="${admin_password}"
  else
    unset ADMIN_PASSWORD
  fi
}

prepare_directories() {
  umask 027
  mkdir -p \
    "${DATA_DIR}/database" \
    "${DATA_DIR}/logs" \
    "${STATIC_DIR}" \
    "${AVATARS_DIR}"
}

main() {
  # Never pass externally supplied/generated signing or encryption keys through
  # the Home Assistant wrapper; Reclaimerr persists its own keys in DATA_DIR.
  unset JWT_SECRET ENCRYPTION_KEY PUID PGID

  load_options
  prepare_directories
  log "Starting Reclaimerr on ${API_HOST}:${API_PORT}"

  # Expansion is intentionally deferred to the child shell so TZ is absent
  # while the upstream entrypoint performs its initialization.
  # shellcheck disable=SC2016
  exec /usr/local/bin/docker-entrypoint.sh bash -c '
    export TZ="${RECLAIMERR_RUNTIME_TZ}"
    unset RECLAIMERR_RUNTIME_TZ
    exec granian \
      --interface asgi \
      --workers 1 \
      --host "${API_HOST}" \
      --port "${API_PORT}" \
      backend.api.main:app
  '
}

main "$@"
