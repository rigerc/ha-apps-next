#!/bin/bash
# Configure Comicarr from Home Assistant app options and start the service.

set -euo pipefail

readonly OPTIONS_FILE="/data/options.json"
readonly DATA_DIR="/data/comicarr"
readonly API_PORT="8090"

log() {
  printf '[comicarr] %s\n' "$*"
}

fail() {
  printf '[comicarr] ERROR: %s\n' "$*" >&2
  exit 1
}

option_value() {
  local key="$1"
  local default_value="$2"

  python3 - "${OPTIONS_FILE}" "${key}" "${default_value}" <<'PY'
import json
import sys

path, key, default_value = sys.argv[1:]
with open(path, encoding="utf-8") as options_file:
    options = json.load(options_file)

if not isinstance(options, dict):
    raise SystemExit("options must be an object")

value = options.get(key, default_value)
if type(value) is not str:
    raise SystemExit(f"option {key} must be a string")
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

load_options() {
  local timezone
  local log_level

  [[ -f "${OPTIONS_FILE}" ]] \
    || fail "Missing Home Assistant options file: ${OPTIONS_FILE}"

  timezone="$(option_value timezone Etc/UTC)" \
    || fail "timezone must be a string"
  validate_timezone "${timezone}" \
    || fail "timezone must be a valid IANA timezone"

  log_level="$(option_value log_level normal)" \
    || fail "log_level must be a string"
  case "${log_level}" in
    warning)
      export COMICARR_LOG_LEVEL=0
      ;;
    normal)
      export COMICARR_LOG_LEVEL=1
      ;;
    debug)
      export COMICARR_LOG_LEVEL=2
      ;;
    *)
      fail "log_level must be warning, normal, or debug"
      ;;
  esac

  export TZ="${timezone}"
}

main() {
  load_options
  umask 027
  python3 /config_sync.py

  log "Starting Comicarr on 0.0.0.0:${API_PORT}"
  exec python3 /opt/comicarr/Comicarr.py \
    --nolaunch \
    --datadir "${DATA_DIR}" \
    --port "${API_PORT}"
}

main "$@"
