#!/bin/bash
# Build and exercise Reclaimerr under its shipped enforced AppArmor policy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly APP_DIR
readonly PROFILE_SOURCE="${APP_DIR}/apparmor.txt"
readonly PROFILE_NAME="reclaimerr-local-test-${UID}-$$"
TEST_ROOT="$(mktemp -d -t reclaimerr-apparmor.XXXXXX)"
readonly TEST_ROOT
readonly PROFILE_FILE="${TEST_ROOT}/apparmor.txt"
readonly DEFAULT_IMAGE="local/ha-addon-reclaimerr:apparmor-test"
PROFILE_LOADED=false
ROOT_COMMAND=()

log() {
  printf '[apparmor-test] %s\n' "$*"
}

fail() {
  printf '[apparmor-test] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ "${PROFILE_LOADED}" == "true" ]]; then
    "${ROOT_COMMAND[@]}" apparmor_parser --remove --skip-cache \
      "${PROFILE_FILE}" >/dev/null 2>&1 || true
  fi
  rm -rf -- "${TEST_ROOT}"
}

require_command() {
  local command_name="$1"

  command -v "${command_name}" >/dev/null 2>&1 \
    || fail "Required command not found: ${command_name}"
}

configure_privilege_command() {
  if ((EUID == 0)); then
    ROOT_COMMAND=()
    return
  fi
  require_command sudo
  ROOT_COMMAND=(sudo)
  "${ROOT_COMMAND[@]}" true \
    || fail "Root access is required to load the AppArmor profile"
}

check_apparmor_support() {
  local security_options

  [[ -r /sys/module/apparmor/parameters/enabled ]] \
    || fail "The kernel does not expose AppArmor support"
  [[ "$(</sys/module/apparmor/parameters/enabled)" == "Y" ]] \
    || fail "AppArmor is disabled; refusing an unconfined test"
  security_options="$(docker info --format \
    '{{range .SecurityOptions}}{{println .}}{{end}}')"
  grep -qx 'name=apparmor' <<<"${security_options}" \
    || fail "Docker is not configured with AppArmor support"
}

build_image_if_needed() {
  local image="$1"
  local version

  if docker image inspect "${image}" >/dev/null 2>&1; then
    return
  fi
  version="$(awk '$1 == "version:" {print $2; exit}' \
    "${APP_DIR}/config.yaml")"
  [[ -n "${version}" ]] || fail "Unable to read Reclaimerr app version"
  log "building ${image} for Reclaimerr ${version}"
  docker build --build-arg BUILD_ARCH=amd64 \
    --build-arg "BUILD_VERSION=${version}" --tag "${image}" "${APP_DIR}"
}

load_profile() {
  sed "s/^profile reclaimerr /profile ${PROFILE_NAME} /" \
    "${PROFILE_SOURCE}" >"${PROFILE_FILE}"
  grep -q "^profile ${PROFILE_NAME} " "${PROFILE_FILE}" \
    || fail "Unable to create isolated AppArmor profile"
  log "loading enforced AppArmor profile ${PROFILE_NAME}"
  "${ROOT_COMMAND[@]}" apparmor_parser --replace --skip-cache \
    "${PROFILE_FILE}"
  PROFILE_LOADED=true
}

read_denials() {
  local started_at="$1"

  if command -v journalctl >/dev/null 2>&1; then
    "${ROOT_COMMAND[@]}" journalctl --dmesg --since "@${started_at}" \
      --no-pager 2>/dev/null | grep -F 'apparmor="DENIED"' \
      | grep -F "profile=\"${PROFILE_NAME}\"" || true
  else
    log "journalctl unavailable; inspect kernel logs for AppArmor denials"
  fi
}

run_confined_suite() {
  local image="$1"
  local started_at
  local denials
  local status=0

  started_at="$(date +%s)"
  log "running smoke suite under AppArmor enforcement"
  APPARMOR_PROFILE="${PROFILE_NAME}" \
    "${SCRIPT_DIR}/smoke.sh" "${image}" || status=$?
  denials="$(read_denials "${started_at}")"
  if [[ -n "${denials}" ]]; then
    printf '%s\n' "${denials}" >&2
    fail "The kernel reported AppArmor denials"
  fi
  ((status == 0)) || fail "Confined smoke suite failed with status ${status}"
}

main() {
  local image="${1:-${DEFAULT_IMAGE}}"

  trap cleanup EXIT
  require_command docker
  require_command apparmor_parser
  check_apparmor_support
  configure_privilege_command
  build_image_if_needed "${image}"
  load_profile
  run_confined_suite "${image}"
  log "all confined runtime checks passed"
}

main "$@"
