#!/bin/bash
# Build and exercise Endurain under its real AppArmor policy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly APP_DIR
readonly PROFILE_SOURCE="${APP_DIR}/apparmor.txt"
readonly PROFILE_NAME="endurain-local-test-${UID}-$$"
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
readonly PROFILE_FILE="${TEST_ROOT}/apparmor.txt"
readonly DEFAULT_IMAGE="local/ha-addon-endurain:apparmor-test"
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
    "${ROOT_COMMAND[@]}" apparmor_parser \
      --remove \
      --skip-cache \
      "${PROFILE_FILE}" >/dev/null 2>&1 || true
  fi
  rm -rf "${TEST_ROOT}"
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
  local docker_security_options
  local kernel_state

  [[ -r /sys/module/apparmor/parameters/enabled ]] \
    || fail "The kernel does not expose AppArmor support"
  kernel_state="$(</sys/module/apparmor/parameters/enabled)"
  [[ "${kernel_state}" == "Y" ]] \
    || fail "AppArmor is disabled; this test must not run unconfined"

  docker_security_options="$(
    docker info --format '{{range .SecurityOptions}}{{println .}}{{end}}'
  )"
  grep -qx 'name=apparmor' <<<"${docker_security_options}" \
    || fail "Docker is not configured with AppArmor support"
}

build_image() {
  local image="$1"
  local version

  version="$(
    awk '$1 == "version:" {print $2; exit}' "${APP_DIR}/config.yaml"
  )"
  [[ -n "${version}" ]] || fail "Unable to read the Endurain app version"

  log "building ${image} for Endurain ${version}"
  docker build \
    --build-arg BUILD_ARCH=amd64 \
    --build-arg "BUILD_VERSION=${version}" \
    --tag "${image}" \
    "${APP_DIR}"
}

load_profile() {
  sed \
    "s/^profile endurain /profile ${PROFILE_NAME} /" \
    "${PROFILE_SOURCE}" >"${PROFILE_FILE}"
  grep -q "^profile ${PROFILE_NAME} " "${PROFILE_FILE}" \
    || fail "Unable to create the isolated AppArmor profile"

  log "loading enforced AppArmor profile ${PROFILE_NAME}"
  "${ROOT_COMMAND[@]}" apparmor_parser \
    --replace \
    --skip-cache \
    "${PROFILE_FILE}"
  PROFILE_LOADED=true
}

read_denials() {
  local started_at="$1"

  if command -v journalctl >/dev/null 2>&1; then
    "${ROOT_COMMAND[@]}" journalctl \
      --dmesg \
      --since "@${started_at}" \
      --no-pager 2>/dev/null \
      | grep -F 'apparmor="DENIED"' \
      | grep -F "profile=\"${PROFILE_NAME}\"" \
      || true
    return
  fi

  printf '%s\n' \
    'journalctl is unavailable; inspect the kernel log for AppArmor denials' \
    >&2
}

filter_actionable_denials() {
  local denial

  while IFS= read -r denial; do
    if [[ "${denial}" == *'operation="open"'* \
      && "${denial}" == *'name="/dev/tty"'* \
      && "${denial}" == *'comm="run.sh"'* ]]; then
      continue
    fi
    if [[ "${denial}" == *'operation="capable"'* \
      && "${denial}" == *'comm="install"'* \
      && "${denial}" == *'capname="fsetid"'* ]]; then
      continue
    fi
    if [[ "${denial}" == *'operation="file_mmap"'* \
      && "${denial}" == *'name="/"'* \
      && "${denial}" == *'comm="postgres"'* ]]; then
      continue
    fi
    printf '%s\n' "${denial}"
  done
}

run_confined_suite() {
  local actionable_denials
  local denials
  local image="$1"
  local started_at
  local test_status=0

  started_at="$(date +%s)"
  log "running the complete smoke suite under AppArmor enforcement"
  APPARMOR_PROFILE="${PROFILE_NAME}" \
    "${SCRIPT_DIR}/smoke.sh" "${image}" \
    || test_status=$?

  denials="$(read_denials "${started_at}")"
  if [[ -n "${denials}" ]]; then
    actionable_denials="$(filter_actionable_denials <<<"${denials}")"
    if [[ -n "${actionable_denials}" ]]; then
      printf '%s\n' "${actionable_denials}" >&2
      fail "The kernel reported unexpected AppArmor denials"
    fi
    log "kernel audit contained only documented non-blocking probes"
  fi
  ((test_status == 0)) \
    || fail "The confined smoke suite failed with status ${test_status}"
}

main() {
  local image="${1:-${DEFAULT_IMAGE}}"

  trap cleanup EXIT
  require_command docker
  check_apparmor_support
  require_command apparmor_parser
  configure_privilege_command
  build_image "${image}"
  load_profile
  run_confined_suite "${image}"
  log "all confined runtime checks passed"
}

main "$@"
