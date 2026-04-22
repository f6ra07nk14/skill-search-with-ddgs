#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DEFAULT_SKILL_ROOT="~/.agents/skills"
DEFAULT_SKILL_NAME="search-with-ddgs"
DEFAULT_SERVER_NAME="ddgs"

SKILL_ROOT=""
SKILL_NAME=""
SERVER_NAME=""
NON_INTERACTIVE=0

log_phase() {
  local phase="$1"
  local message="$2"
  printf '[phase:%s] %s\n' "$phase" "$message"
}

error_phase() {
  local phase="$1"
  local message="$2"
  printf '[phase:%s] ERROR: %s\n' "$phase" "$message" >&2
}

fatal_phase() {
  local phase="$1"
  local message="$2"
  local next_action="$3"
  error_phase "$phase" "$message"
  printf '[phase:%s] NEXT: %s\n' "$phase" "$next_action" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Preflight-only installer entrypoint for the search-with-ddgs skill.
This S01 scope resolves installer config and prerequisite checks only;
it does not create directories, environments, or MCP config.

Options:
  --skill-root <path>      Skill install root (default: $DEFAULT_SKILL_ROOT)
  --skill-name <name>      Skill directory name (default: $DEFAULT_SKILL_NAME)
  --server-name <name>     MCP server name label (default: $DEFAULT_SERVER_NAME)
  --non-interactive        Disable prompts; resolve from flags + defaults only
  --help                   Show this help text
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_interactive() {
  if [[ "${INSTALLER_FORCE_INTERACTIVE:-0}" == "1" ]]; then
    return 0
  fi
  [[ -t 0 ]]
}

require_option_value() {
  local option_name="$1"
  local value="${2-}"
  if [[ -z "$value" ]]; then
    fatal_phase "config" "Missing value for $option_name." "Provide a non-empty value for $option_name or run --help."
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skill-root)
        require_option_value "--skill-root" "${2-}"
        SKILL_ROOT="$(trim "$2")"
        shift 2
        ;;
      --skill-name)
        require_option_value "--skill-name" "${2-}"
        SKILL_NAME="$(trim "$2")"
        shift 2
        ;;
      --server-name)
        require_option_value "--server-name" "${2-}"
        SERVER_NAME="$(trim "$2")"
        shift 2
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        fatal_phase "config" "Unknown option: $1" "Run '$SCRIPT_NAME --help' for supported options."
        ;;
    esac
  done
}

prompt_with_default() {
  local prompt_label="$1"
  local current_value="$2"
  local answer

  printf '%s [%s]: ' "$prompt_label" "$current_value" >&2
  IFS= read -r answer || true
  answer="$(trim "$answer")"

  if [[ -z "$answer" ]]; then
    printf '%s' "$current_value"
  else
    printf '%s' "$answer"
  fi
}

resolve_config() {
  local can_prompt=0

  SKILL_ROOT="$(trim "$SKILL_ROOT")"
  SKILL_NAME="$(trim "$SKILL_NAME")"
  SERVER_NAME="$(trim "$SERVER_NAME")"

  [[ -z "$SKILL_ROOT" ]] && SKILL_ROOT="$DEFAULT_SKILL_ROOT"
  [[ -z "$SKILL_NAME" ]] && SKILL_NAME="$DEFAULT_SKILL_NAME"
  [[ -z "$SERVER_NAME" ]] && SERVER_NAME="$DEFAULT_SERVER_NAME"

  if [[ "$NON_INTERACTIVE" -eq 0 ]] && is_interactive; then
    can_prompt=1
  fi

  if [[ "$can_prompt" -eq 1 ]]; then
    log_phase "config" "Interactive mode: collecting installer settings."
    SKILL_ROOT="$(prompt_with_default "Skill root" "$SKILL_ROOT")"
    SKILL_NAME="$(prompt_with_default "Skill name" "$SKILL_NAME")"
    SERVER_NAME="$(prompt_with_default "Server name" "$SERVER_NAME")"
  else
    log_phase "config" "Non-interactive resolution: using flags and defaults only."
  fi

  SKILL_ROOT="$(trim "$SKILL_ROOT")"
  SKILL_NAME="$(trim "$SKILL_NAME")"
  SERVER_NAME="$(trim "$SERVER_NAME")"

  [[ -z "$SKILL_ROOT" ]] && SKILL_ROOT="$DEFAULT_SKILL_ROOT"
  [[ -z "$SKILL_NAME" ]] && SKILL_NAME="$DEFAULT_SKILL_NAME"
  [[ -z "$SERVER_NAME" ]] && SERVER_NAME="$DEFAULT_SERVER_NAME"

  log_phase "config" "Resolved skill_root='$SKILL_ROOT' skill_name='$SKILL_NAME' server_name='$SERVER_NAME'."
}

check_platform() {
  local os_name
  os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os_name" in
    darwin|linux)
      log_phase "platform" "Supported platform detected: $os_name."
      ;;
    *)
      fatal_phase "platform" "Unsupported platform: $os_name." "Use macOS or Linux for this installer."
      ;;
  esac
}

uv_available() {
  command -v uv >/dev/null 2>&1
}

guided_uv_install_cmd() {
  if [[ -n "${INSTALLER_UV_INSTALL_CMD:-}" ]]; then
    printf '%s' "$INSTALLER_UV_INSTALL_CMD"
  else
    printf '%s' 'curl -LsSf https://astral.sh/uv/install.sh | sh'
  fi
}

attempt_guided_uv_install() {
  local answer
  local cmd

  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    fatal_phase "uv" "uv is not installed." "Install uv manually (https://docs.astral.sh/uv/getting-started/installation/) then re-run with --non-interactive."
  fi

  if ! is_interactive; then
    fatal_phase "uv" "uv is not installed and prompts are unavailable (non-TTY)." "Run in a TTY session or install uv manually before rerunning."
  fi

  printf 'uv is missing. Run guided uv installer now? [Y/n]: ' >&2
  IFS= read -r answer || true
  answer="$(trim "$answer")"

  if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
    cmd="$(guided_uv_install_cmd)"
    log_phase "uv" "Attempting guided uv install."
    if ! eval "$cmd"; then
      fatal_phase "uv" "Guided uv install command failed." "Install uv manually, then rerun this installer."
    fi
    log_phase "uv" "Guided uv install attempt finished; re-checking uv."
  else
    fatal_phase "uv" "uv installation declined." "Install uv manually, then rerun this installer."
  fi
}

ensure_uv() {
  if uv_available; then
    log_phase "uv" "Detected uv in PATH."
    return
  fi

  error_phase "uv" "uv not found in PATH."
  attempt_guided_uv_install

  if uv_available; then
    log_phase "uv" "uv detected after guided install attempt."
  else
    fatal_phase "uv" "uv still unavailable after guided install attempt." "Install uv manually and ensure it is on PATH before rerunning."
  fi
}

main() {
  parse_args "$@"
  resolve_config
  check_platform
  ensure_uv
  log_phase "preflight" "Preflight checks passed. No filesystem mutation was performed."
}

main "$@"
