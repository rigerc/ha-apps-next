#!/bin/bash
# Configure Comicarr from Home Assistant app options and start the service.

set -euo pipefail

readonly OPTIONS_FILE="/data/options.json"
readonly DATA_DIR="/data/comicarr"
readonly COMICS_DIR="/media/comics"
readonly MANGA_DIR="/media/manga"
readonly DOWNLOADS_DIR="/share/comicarr/downloads"
readonly CONFIG_FILE="${DATA_DIR}/config.ini"
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

prepare_directories() {
  umask 027
  mkdir -p \
    "${DATA_DIR}" \
    "${DATA_DIR}/backups" \
    "${COMICS_DIR}" \
    "${MANGA_DIR}" \
    "${DOWNLOADS_DIR}"
}

seed_config() {
  [[ ! -e "${CONFIG_FILE}" ]] || return 0

  log "Creating initial configuration with Home Assistant storage paths"
  install -m 0600 /dev/null "${CONFIG_FILE}"
  # Comicarr 0.31.0 assumes several default-valued sections exist during
  # configure(), so its minimal INI mode cannot bootstrap a new install.
  printf '%s\n' \
    '[General]' \
    'config_version = 18' \
    'minimal_ini = False' \
    'launch_browser = False' \
    'destination_dir = /media/comics' \
    'manga_destination_dir = /media/manga' \
    'backup_location = /data/comicarr/backups' \
    '' \
    '[Interface]' \
    'http_host = 0.0.0.0' \
    'http_port = 8090' \
    '' \
    '[SABnzbd]' \
    'sab_directory = /share/comicarr/downloads' \
    '' \
    '[DDL]' \
    'ddl_location = /share/comicarr/downloads' \
    >"${CONFIG_FILE}"
}

main() {
  load_options
  prepare_directories
  seed_config

  log "Starting Comicarr on 0.0.0.0:${API_PORT}"
  exec python3 /opt/comicarr/Comicarr.py \
    --nolaunch \
    --datadir "${DATA_DIR}" \
    --port "${API_PORT}"
}

main "$@"
