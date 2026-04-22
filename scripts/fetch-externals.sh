#!/bin/bash
#
# Fetch reference documentation or code from external repositories for local
# use. Clone or pull external repositories declared in .externals.json,
# keeping project dependencies on reference material up to date.
#
# If the config file does not exist, launches an interactive gum wizard
# to create one. Automatically adds the target directory to .gitignore.
#
# Usage:
#   fetch-externals.sh           # clone/pull all externals
#   fetch-externals.sh --add     # interactively add repos to config
#   fetch-externals.sh --remove  # interactively remove repos from config
#   fetch-externals.sh --list    # list configured repos
#   fetch-externals.sh --edit    # re-run the interactive config wizard
#   fetch-externals.sh --open    # open .externals.json in $EDITOR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

if [[ "${SCRIPT_DIR}" == "/" ]]; then
  echo "error: refusing to run from filesystem root" >&2
  exit 1
fi

PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PARENT_DIR

if [[ -f "${SCRIPT_DIR}/.externals.json" ]]; then
  readonly PROJECT_DIR="${SCRIPT_DIR}"
elif [[ -f "${PARENT_DIR}/.externals.json" ]]; then
  readonly PROJECT_DIR="${PARENT_DIR}"
else
  readonly PROJECT_DIR="${PARENT_DIR}"
fi

readonly CONFIG_FILE="${PROJECT_DIR}/.externals.json"

if [[ "${PROJECT_DIR}" == "/" || "${PROJECT_DIR}" == "/home" || "${PROJECT_DIR}" == "/tmp" ]]; then
  echo "error: resolved project dir is '${PROJECT_DIR}' — refusing to operate" >&2
  exit 1
fi

readonly BOLD='\033[1m'
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly CYAN='\033[36m'
readonly RED='\033[31m'
readonly RESET='\033[0m'

err() {
  echo -e "${RED}error${RESET}: $*" >&2
}

info() {
  echo -e "${CYAN}::${RESET} $*"
}

success() {
  echo -e "${GREEN}ok${RESET}: $*"
}

warn() {
  echo -e "${YELLOW}warn${RESET}: $*"
}

require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    err "'$1' is required but not found in PATH"
    exit 1
  fi
}

is_interactive() {
  [[ -t 0 ]] && command -v gum &>/dev/null
}

resolve_url() {
  local input="$1"
  if [[ "${input}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "https://github.com/${input}.git"
  else
    echo "${input}"
  fi
}

detect_default_branch() {
  local url="$1"
  local ref

  ref="$(git ls-remote --symref "${url}" HEAD 2>/dev/null \
    | grep -oP 'refs/heads/\K\S+' | head -1)" || true

  if [[ -n "${ref}" ]]; then
    echo "${ref}"
  fi
}

ensure_gitignore() {
  local target_dir="$1"
  local gitignore="${PROJECT_DIR}/.gitignore"
  local entry="${target_dir}/"

  if [[ ! -f "${gitignore}" ]]; then
    echo "# managed by fetch-externals.sh" > "${gitignore}"
    echo "${entry}" >> "${gitignore}"
    info "created .gitignore with ${entry}"
    return
  fi

  if grep -qFx "${entry}" "${gitignore}" 2>/dev/null; then
    return
  fi

  if grep -qF "${entry}" "${gitignore}" 2>/dev/null; then
    return
  fi

  {
    echo ""
    echo "# managed by fetch-externals.sh"
    echo "${entry}"
  } >> "${gitignore}"
  info "added ${entry} to .gitignore"
}

collect_repos_interactive() {
  local repos_json="${1:-[]}"

  while true; do
    echo "" >&2
    echo -e "${BOLD}--- Add repository ---${RESET}" >&2

    local name url branch
    name="$(gum input \
      --prompt="Name: " \
      --header="Directory name for this repo" \
      --placeholder="my-repo")"

    if [[ -z "${name}" ]]; then
      err "repository name is required"
      continue
    fi

    local raw_url
    raw_url="$(gum input \
      --prompt="URL: " \
      --header="Git remote URL (supports owner/repo for GitHub)" \
      --placeholder="owner/repo or https://github.com/user/repo.git")"

    if [[ -z "${raw_url}" ]]; then
      err "repository URL is required"
      continue
    fi

    url="$(resolve_url "${raw_url}")"

    local detected_branch
    detected_branch="$(detect_default_branch "${url}")" || true

    local branch_header="Branch to track"
    local branch_placeholder="main"
    local branch_value=""

    if [[ -n "${detected_branch}" ]]; then
      branch_header="Branch to track (detected: ${detected_branch})"
      branch_placeholder="${detected_branch}"
      branch_value="${detected_branch}"
    fi

    branch="$(gum input \
      --prompt="Branch: " \
      --header="${branch_header}" \
      --placeholder="${branch_placeholder}" \
      --value="${branch_value}")"

    if [[ -z "${branch}" ]]; then
      if [[ -n "${detected_branch}" ]]; then
        branch="${detected_branch}"
      else
        branch="main"
      fi
    fi

    local use_sparse
    use_sparse="$(gum confirm \
      --affirmative="Yes" \
      --negative="No" \
      "Fetch only specific paths (sparse checkout)?" && echo "yes" || echo "no")"

    local sparse_json="[]"
    if [[ "${use_sparse}" == "yes" ]]; then
      local sparse_paths
      sparse_paths="$(gum input \
        --prompt="Paths: " \
        --header="Comma-separated paths (files or folders)" \
        --placeholder="src/lib,docs/README.md")"

      if [[ -n "${sparse_paths}" ]]; then
        sparse_json="$(echo "${sparse_paths}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R . | jq -s .)"
      fi
    fi

    local repo_entry
    repo_entry="$(jq -n \
      --arg name "${name}" \
      --arg url "${url}" \
      --arg branch "${branch}" \
      --argjson sparse "${sparse_json}" \
      '{name: $name, url: $url, branch: $branch, sparse: $sparse}')"

    repos_json="$(echo "${repos_json}" | jq --argjson entry "${repo_entry}" '. + [$entry]')"

    echo "" >&2
    if ! gum confirm "Add another repository?"; then
      break
    fi
  done

  echo "${repos_json}"
}

create_config_interactive() {
  local target_dir
  target_dir="$(gum input \
    --placeholder="externals" \
    --prompt="Target directory: " \
    --header="Where should repos be cloned? (relative to project root)" \
    --value="externals")"

  if [[ -z "${target_dir}" ]]; then
    target_dir="externals"
  fi

  if [[ "${target_dir}" == "/" || "${target_dir}" == ".." || "${target_dir}" == "../" ]]; then
    err "target directory '${target_dir}' is unsafe"
    exit 1
  fi

  local repos_json
  repos_json="$(collect_repos_interactive)"
  repos_json="${repos_json:-[]}"

  local config
  config="$(jq -n \
    --arg target_dir "${target_dir}" \
    --argjson repos "${repos_json}" \
    '{target_dir: $target_dir, repos: $repos}')"

  echo "${config}" | jq '.' > "${CONFIG_FILE}"
  success "created ${CONFIG_FILE}"
}

clone_repo() {
  local url="$1"
  local dest="$2"
  local branch="$3"
  shift 3
  local -a sparse_paths=("$@")

  if [[ ${#sparse_paths[@]} -gt 0 ]]; then
    git clone --filter=blob:none --no-checkout --branch "${branch}" \
      "${url}" "${dest}" 2>&1
    git -C "${dest}" sparse-checkout init --no-cone 2>&1
    git -C "${dest}" sparse-checkout set "${sparse_paths[@]}" 2>&1
    git -C "${dest}" checkout 2>&1
  else
    git clone --branch "${branch}" "${url}" "${dest}" 2>&1
  fi
}

pull_repo() {
  local dest="$1"
  shift 1
  local -a sparse_paths=("$@")

  if [[ ${#sparse_paths[@]} -gt 0 ]]; then
    git -C "${dest}" sparse-checkout set --no-cone "${sparse_paths[@]}" 2>&1
  fi

  git -C "${dest}" pull 2>&1
}

count_incoming() {
  local dest="$1"
  local branch="$2"
  local count

  git -C "${dest}" fetch origin "${branch}" 2>/dev/null || true
  count="$(git -C "${dest}" log HEAD..FETCH_HEAD --oneline 2>/dev/null | wc -l || echo "0")"
  echo "${count}"
}

count_changes() {
  local dest="$1"
  local prev_head="$2"
  local count

  count="$(git -C "${dest}" diff --stat "${prev_head}..HEAD" 2>/dev/null \
    | tail -1 | grep -oP '\d+ file' | head -1 | grep -oP '\d+' || echo "0")"
  echo "${count}"
}

print_summary() {
  local -n _results="$1"
  local cloned=0 pulled=0 current=0 failed=0 total_commits=0 total_files=0

  echo ""
  echo -e "${BOLD}─────────────────────────────────────────────────────────${RESET}"
  echo -e "${BOLD} Summary${RESET}"
  echo -e "${BOLD}─────────────────────────────────────────────────────────${RESET}"

  printf "  %-25s %-10s %-10s %-8s %-8s\n" \
    "REPO" "STATUS" "COMMITS" "FILES" "SPARSE"
  echo "  ─────────────────────────────────────────────────────────"

  for entry in "${_results[@]}"; do
    local name status commits files sparse
    name="$(echo "${entry}" | cut -d'|' -f1)"
    status="$(echo "${entry}" | cut -d'|' -f2)"
    commits="$(echo "${entry}" | cut -d'|' -f3)"
    files="$(echo "${entry}" | cut -d'|' -f4)"
    sparse="$(echo "${entry}" | cut -d'|' -f5)"

    case "${status}" in
      cloned)  (( cloned += 1 )) ;;
      pulled)  (( pulled += 1 )) ;;
      current) (( current += 1 )) ;;
      failed)  (( failed += 1 )) ;;
    esac

    if [[ "${commits}" =~ ^[0-9]+$ ]]; then
      total_commits=$(( total_commits + commits ))
    fi
    if [[ "${files}" =~ ^[0-9]+$ ]]; then
      total_files=$(( total_files + files ))
    fi

    local status_color="${CYAN}"
    case "${status}" in
      cloned)  status_color="${GREEN}" ;;
      pulled)  status_color="${YELLOW}" ;;
      current) status_color="${CYAN}" ;;
      failed)  status_color="${RED}" ;;
    esac

    printf "  %-25s ${status_color}%-10s${RESET} %-10s %-8s %-8s\n" \
      "${name}" "${status}" "${commits}" "${files}" "${sparse}"
  done

  echo "  ─────────────────────────────────────────────────────────"
  printf "  ${BOLD}%-25s${RESET} %-10s %-10s %-8s\n" \
    "TOTAL" "${cloned}c/${pulled}p/${current}u/${failed}f" \
    "${total_commits}" "${total_files}"
  echo -e "${BOLD}─────────────────────────────────────────────────────────${RESET}"
}

list_repos() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    err "no ${CONFIG_FILE} found"
    exit 1
  fi

  local target_dir
  target_dir="$(jq -r '.target_dir' "${CONFIG_FILE}")"
  local repo_count
  repo_count="$(jq '.repos | length' "${CONFIG_FILE}")"

  echo -e "${BOLD}Config:${RESET} ${CONFIG_FILE}"
  echo -e "${BOLD}Target:${RESET} ${target_dir}/"
  echo ""

  if [[ "${repo_count}" -eq 0 ]]; then
    echo "  (no repos configured)"
    return
  fi

  printf "  %-3s %-20s %-40s %-12s %s\n" "#" "NAME" "URL" "BRANCH" "SPARSE"
  echo "  ─────────────────────────────────────────────────────────────────"

  for (( i = 0; i < repo_count; i++ )); do
    local name url branch sparse_count
    name="$(jq -r ".repos[${i}].name" "${CONFIG_FILE}")"
    url="$(jq -r ".repos[${i}].url" "${CONFIG_FILE}")"
    branch="$(jq -r ".repos[${i}].branch" "${CONFIG_FILE}")"
    sparse_count="$(jq ".repos[${i}].sparse | length" "${CONFIG_FILE}")"

    local sparse_label="no"
    if [[ "${sparse_count}" -gt 0 ]]; then
      sparse_label="yes"
    fi

    printf "  %-3s %-20s %-40s %-12s %s\n" \
      "${i}" "${name}" "${url}" "${branch}" "${sparse_label}"
  done
}

remove_repos_interactive() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    err "no ${CONFIG_FILE} found — nothing to remove"
    exit 1
  fi

  local repo_count
  repo_count="$(jq '.repos | length' "${CONFIG_FILE}")"

  if [[ "${repo_count}" -eq 0 ]]; then
    warn "no repos configured"
    exit 0
  fi

  local choices
  choices="$(jq -r '.repos[] | .name' "${CONFIG_FILE}" \
    | gum choose --no-limit --header="Select repos to remove (space to toggle, enter to confirm)")"

  if [[ -z "${choices}" ]]; then
    info "nothing selected"
    exit 0
  fi

  local tmp
  tmp="$(jq '.' "${CONFIG_FILE}")"

  while IFS= read -r name; do
    tmp="$(echo "${tmp}" | jq --arg n "${name}" '.repos |= map(select(.name != $n))')"
    warn "removed: ${name}"
  done <<< "${choices}"

  echo "${tmp}" | jq '.' > "${CONFIG_FILE}"
  success "updated ${CONFIG_FILE}"
}

print_usage() {
  echo "Usage: $(basename "$0") [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --add     Interactively add repos to existing config"
  echo "  --remove  Interactively remove repos from config"
  echo "  --list    List configured repos"
  echo "  --edit    Re-run the interactive config wizard"
  echo "  --open    Open .externals.json in \$EDITOR"
  echo "  --help    Show this help message"
}

main() {
  local edit_mode=false
  local add_mode=false
  local remove_mode=false
  local list_mode=false
  local open_mode=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --add)    add_mode=true ;;
      --remove) remove_mode=true ;;
      --list)   list_mode=true ;;
      --edit)   edit_mode=true ;;
      --open)   open_mode=true ;;
      --help)   print_usage; exit 0 ;;
      *)        err "unknown option: $1"; print_usage; exit 1 ;;
    esac
    shift
  done

  require_cmd git
  require_cmd jq

  if [[ "${open_mode}" == true ]]; then
    exec "${EDITOR:-${VISUAL:-vi}}" "${CONFIG_FILE}"
  fi

  if [[ "${list_mode}" == true ]]; then
    list_repos
    exit 0
  fi

  if [[ "${remove_mode}" == true ]]; then
    if ! is_interactive; then
      err "--remove requires an interactive terminal with gum installed"
      exit 1
    fi
    remove_repos_interactive
    exit 0
  fi

  if [[ "${add_mode}" == true ]]; then
    if ! is_interactive; then
      err "--add requires an interactive terminal with gum installed"
      exit 1
    fi

    if [[ ! -f "${CONFIG_FILE}" ]]; then
      err "no ${CONFIG_FILE} found — use --edit to create one"
      exit 1
    fi

    local repos_json
    repos_json="$(jq '.repos' "${CONFIG_FILE}")"
    local existing="${repos_json}"
    repos_json="$(collect_repos_interactive "${repos_json}")"
    repos_json="${repos_json:-${existing}}"

    local tmp
    tmp="$(jq --argjson repos "${repos_json}" '.repos = $repos' "${CONFIG_FILE}")"
    echo "${tmp}" | jq '.' > "${CONFIG_FILE}"
    success "updated ${CONFIG_FILE}"
    exit 0
  fi

  if [[ "${edit_mode}" == true ]]; then
    if ! is_interactive; then
      err "--edit requires an interactive terminal with gum installed"
      exit 1
    fi

    if [[ -f "${CONFIG_FILE}" ]]; then
      warn "existing config will be replaced"
      if ! gum confirm "Continue?"; then
        exit 0
      fi
    fi

    create_config_interactive
    echo ""
  fi

  if [[ ! -f "${CONFIG_FILE}" ]]; then
    if is_interactive; then
      info "no ${CONFIG_FILE} found"
      echo -e "  Launching interactive setup..."
      create_config_interactive
      echo ""
    else
      err "no ${CONFIG_FILE} found and running non-interactively"
      echo "  Create .externals.json manually or run in a TTY:" >&2
      echo "    {" >&2
      echo '      "target_dir": "externals",' >&2
      echo '      "repos": [' >&2
      echo '        {' >&2
      echo '          "name": "example",' >&2
      echo '          "url": "https://github.com/user/repo.git",' >&2
      echo '          "branch": "main",' >&2
      echo '          "sparse": []' >&2
      echo '        }' >&2
      echo '      ]' >&2
      echo '    }' >&2
      exit 1
    fi
  fi

  local target_dir
  target_dir="$(jq -r '.target_dir' "${CONFIG_FILE}")"
  if [[ -z "${target_dir}" || "${target_dir}" == "null" ]]; then
    target_dir="externals"
  fi

  if [[ "${target_dir}" == "/" || "${target_dir}" == ".." || "${target_dir}" == "../" ]]; then
    err "target directory '${target_dir}' is unsafe"
    exit 1
  fi

  local abs_target="${PROJECT_DIR}/${target_dir}"

  local abs_real
  abs_real="$(cd "${PROJECT_DIR}" 2>/dev/null && realpath --canonicalize-missing "${target_dir}")"

  if [[ "${abs_real}" == "/" || "${abs_real}" == "/home" || "${abs_real}" == "/tmp" ]]; then
    err "resolved target '${abs_real}' is unsafe — refusing to operate"
    exit 1
  fi

  mkdir -p "${abs_target}"

  ensure_gitignore "${target_dir}"

  local repo_count
  repo_count="$(jq '.repos | length' "${CONFIG_FILE}")"

  if [[ "${repo_count}" -eq 0 ]]; then
    warn "no repositories configured in ${CONFIG_FILE}"
    exit 0
  fi

  info "processing ${repo_count} repos -> ${target_dir}/"
  echo ""

  declare -a results=()

  for (( i = 0; i < repo_count; i++ )); do
    local name url branch
    name="$(jq -r ".repos[${i}].name" "${CONFIG_FILE}")"
    url="$(jq -r ".repos[${i}].url" "${CONFIG_FILE}")"
    branch="$(jq -r ".repos[${i}].branch" "${CONFIG_FILE}")"

    local -a sparse_paths=()
    local sparse_count
    sparse_count="$(jq ".repos[${i}].sparse | length" "${CONFIG_FILE}")"

    if [[ "${sparse_count}" -gt 0 ]]; then
      for (( j = 0; j < sparse_count; j++ )); do
        sparse_paths+=("$(jq -r ".repos[${i}].sparse[${j}]" "${CONFIG_FILE}")")
      done
    fi

    local dest="${abs_target}/${name}"
    local sparse_label="no"
    if [[ ${#sparse_paths[@]} -gt 0 ]]; then
      sparse_label="yes"
    fi

    if [[ -d "${dest}/.git" ]]; then
      local prev_head
      prev_head="$(git -C "${dest}" rev-parse HEAD 2>/dev/null || echo "")"

      local incoming
      incoming="$(count_incoming "${dest}" "${branch}")"

      if [[ "${incoming}" -eq 0 ]]; then
        success "${name}: already up to date"
        results+=("${name}|current|0|0|${sparse_label}")
        continue
      fi

      info "${name}: pulling ${incoming} new commit(s)..."

      if pull_repo "${dest}" "${sparse_paths[@]}" 2>&1; then
        local files
        files="$(count_changes "${dest}" "${prev_head}")"
        success "${name}: pulled ${incoming} commit(s), ${files} file(s) changed"
        results+=("${name}|pulled|${incoming}|${files}|${sparse_label}")
      else
        err "${name}: pull failed"
        results+=("${name}|failed|${incoming}|0|${sparse_label}")
      fi

    else
      info "${name}: cloning ${url} (${branch})..."

      if clone_repo "${url}" "${dest}" "${branch}" "${sparse_paths[@]}" 2>&1; then
        success "${name}: cloned"
        results+=("${name}|cloned|-|-|${sparse_label}")
      else
        err "${name}: clone failed"
        results+=("${name}|failed|-|-|${sparse_label}")
      fi
    fi
  done

  print_summary results
}

main "$@"
