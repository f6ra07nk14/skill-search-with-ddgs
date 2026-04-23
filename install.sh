#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SKILL_ROOT="~/.agents/skills"
DEFAULT_SKILL_NAME="search-with-ddgs"
DEFAULT_SERVER_NAME="ddgs"

SKILL_ROOT=""
SKILL_NAME=""
SERVER_NAME=""
NON_INTERACTIVE=0
RESOLVED_SKILL_ROOT=""
RESOLVED_SKILL_PATH=""
RESOLVED_VENV_PATH=""
RESOLVED_DDGS_PATH=""

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

Installer entrypoint for the search-with-ddgs skill.
This S02 scope resolves installer config, runs prerequisite checks,
creates the target skill directory, provisions a local .venv,
installs ddgs[api,mcp], and verifies the local ddgs executable.

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

expand_user_path() {
  local raw_path="$1"

  if [[ "$raw_path" == "~" ]]; then
    printf '%s' "$HOME"
    return
  fi

  if [[ "$raw_path" == "~/"* ]]; then
    printf '%s/%s' "$HOME" "${raw_path:2}"
    return
  fi

  printf '%s' "$raw_path"
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

platform_probe_output() {
  if [[ -n "${INSTALLER_UNAME_CMD:-}" ]]; then
    eval "$INSTALLER_UNAME_CMD"
  else
    uname -s
  fi
}

check_platform() {
  local platform_raw
  local platform_status
  local platform

  set +e
  platform_raw="$(platform_probe_output 2>/dev/null)"
  platform_status=$?
  set -e

  platform_raw="$(trim "$platform_raw")"

  if [[ $platform_status -ne 0 || -z "$platform_raw" ]]; then
    fatal_phase "platform" "Could not determine platform from uname probe." "Retry in a normal shell where 'uname -s' succeeds."
  fi

  platform="$(printf '%s' "$platform_raw" | tr '[:upper:]' '[:lower:]')"

  case "$platform" in
    darwin|linux)
      log_phase "platform" "Supported platform detected: $platform."
      ;;
    *)
      fatal_phase "platform" "Unsupported platform: $platform." "Use macOS or Linux for this installer."
      ;;
  esac
}

uv_probe_output() {
  if [[ -n "${INSTALLER_UV_PATH_CMD:-}" ]]; then
    eval "$INSTALLER_UV_PATH_CMD"
  else
    command -v uv
  fi
}

print_uv_install_guidance() {
  printf '[phase:uv] INSTALL: Install uv via one of the official commands:\n' >&2
  printf '[phase:uv] INSTALL:   curl -LsSf https://astral.sh/uv/install.sh | sh\n' >&2
  printf '[phase:uv] INSTALL:   wget -qO- https://astral.sh/uv/install.sh | sh\n' >&2
  printf '[phase:uv] INSTALL: Docs: https://docs.astral.sh/uv/getting-started/installation/\n' >&2
}

uv_available() {
  local uv_raw
  local uv_status
  local uv_path

  set +e
  uv_raw="$(uv_probe_output 2>/dev/null)"
  uv_status=$?
  set -e

  if [[ $uv_status -ne 0 ]]; then
    return 1
  fi

  uv_raw="$(trim "$uv_raw")"

  # Guard against malformed probe output such as empty/multi-line values.
  if [[ -z "$uv_raw" || "$uv_raw" == *$'\n'* ]]; then
    return 1
  fi

  uv_path="${uv_raw%% *}"

  if [[ -z "$uv_path" ]]; then
    return 1
  fi

  if [[ "$uv_path" == */* && ! -x "$uv_path" ]]; then
    return 1
  fi

  return 0
}

guided_uv_install_cmd() {
  if [[ -n "${INSTALLER_UV_INSTALL_CMD:-}" ]]; then
    printf '%s' "$INSTALLER_UV_INSTALL_CMD"
  else
    printf '%s' 'curl -LsSf https://astral.sh/uv/install.sh | sh'
  fi
}

run_guided_uv_install() {
  local cmd="$1"
  local install_status

  set +e
  eval "$cmd"
  install_status=$?
  set -e

  if [[ $install_status -ne 0 ]]; then
    fatal_phase "uv" "Guided uv installer failed with exit code $install_status." "Install uv manually, then rerun this installer."
  fi
}

attempt_guided_uv_install() {
  local answer
  local normalized_answer
  local cmd

  print_uv_install_guidance

  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    fatal_phase "uv" "uv is not installed." "Install uv manually, then rerun with --non-interactive."
  fi

  if ! is_interactive; then
    fatal_phase "uv" "uv is not installed and prompts are unavailable (non-TTY)." "Run in a TTY session or install uv manually before rerunning."
  fi

  printf 'uv is missing. Run guided uv installer now? [y/N]: ' >&2
  IFS= read -r answer || true
  normalized_answer="$(trim "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')")"

  if [[ "$normalized_answer" != "y" && "$normalized_answer" != "yes" ]]; then
    fatal_phase "uv" "uv installation declined." "Install uv manually, then rerun this installer."
  fi

  cmd="$(guided_uv_install_cmd)"
  log_phase "uv" "Attempting guided uv install."
  run_guided_uv_install "$cmd"
  log_phase "uv" "Guided uv install attempt finished; re-checking uv."
}

ensure_uv() {
  log_phase "uv" "Checking for uv in PATH."
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

resolve_install_paths() {
  local skill_root_resolved
  local skill_path

  skill_root_resolved="$(expand_user_path "$SKILL_ROOT")"
  skill_root_resolved="$(trim "$skill_root_resolved")"

  if [[ -z "$skill_root_resolved" ]]; then
    fatal_phase "filesystem" "Resolved skill root is empty after normalization." "Provide a valid --skill-root value and rerun."
  fi

  if [[ -z "$SKILL_NAME" ]]; then
    fatal_phase "filesystem" "Resolved skill name is empty after normalization." "Provide a valid --skill-name value and rerun."
  fi

  skill_path="$skill_root_resolved/$SKILL_NAME"

  if [[ "$skill_path" == "/" || "$skill_path" == "//" ]]; then
    fatal_phase "filesystem" "Resolved skill path is invalid: '$skill_path'." "Use a non-root --skill-root and a non-empty --skill-name."
  fi

  if [[ -e "$skill_path" ]]; then
    fatal_phase "filesystem" "Target skill directory already exists: $skill_path" "Choose a different --skill-root/--skill-name or remove the existing directory before rerunning."
  fi

  RESOLVED_SKILL_ROOT="$skill_root_resolved"
  RESOLVED_SKILL_PATH="$skill_path"
  RESOLVED_VENV_PATH="$RESOLVED_SKILL_PATH/.venv"

  log_phase "filesystem" "Resolved install path: $RESOLVED_SKILL_PATH"
}

validate_destination_paths() {
  local writable_ancestor

  if [[ -d "$RESOLVED_SKILL_ROOT" ]]; then
    if [[ ! -w "$RESOLVED_SKILL_ROOT" ]]; then
      fatal_phase "filesystem" "Skill root is not writable: $RESOLVED_SKILL_ROOT" "Grant write permission or choose another --skill-root."
    fi
    return
  fi

  if [[ -e "$RESOLVED_SKILL_ROOT" && ! -d "$RESOLVED_SKILL_ROOT" ]]; then
    fatal_phase "filesystem" "Skill root exists but is not a directory: $RESOLVED_SKILL_ROOT" "Choose a directory path for --skill-root."
  fi

  writable_ancestor="$RESOLVED_SKILL_ROOT"
  while [[ ! -d "$writable_ancestor" ]]; do
    writable_ancestor="$(dirname "$writable_ancestor")"
    if [[ "$writable_ancestor" == "." || -z "$writable_ancestor" ]]; then
      writable_ancestor="/"
      break
    fi
  done

  if [[ ! -w "$writable_ancestor" ]]; then
    fatal_phase "filesystem" "No writable ancestor for skill root: $RESOLVED_SKILL_ROOT (nearest existing: $writable_ancestor)" "Grant write permission on an ancestor path or choose another --skill-root."
  fi
}

create_skill_directory() {
  local mkdir_status

  if [[ -z "$RESOLVED_SKILL_PATH" ]]; then
    fatal_phase "filesystem" "Resolved skill path is empty; refusing filesystem mutation." "Rerun with a valid configuration."
  fi

  if [[ ! -d "$RESOLVED_SKILL_ROOT" ]]; then
    log_phase "filesystem" "Creating skill root: $RESOLVED_SKILL_ROOT"
    set +e
    mkdir -p "$RESOLVED_SKILL_ROOT"
    mkdir_status=$?
    set -e

    if [[ $mkdir_status -ne 0 ]]; then
      fatal_phase "filesystem" "Failed to create skill root '$RESOLVED_SKILL_ROOT' (exit $mkdir_status)." "Check path permissions and retry."
    fi
  fi

  log_phase "filesystem" "Creating skill directory: $RESOLVED_SKILL_PATH"
  set +e
  mkdir "$RESOLVED_SKILL_PATH"
  mkdir_status=$?
  set -e

  if [[ $mkdir_status -ne 0 ]]; then
    fatal_phase "filesystem" "Failed to create skill directory '$RESOLVED_SKILL_PATH' (exit $mkdir_status)." "Check path permissions/conflicts and retry."
  fi
}

copy_project_metadata() {
  local phase="metadata-copy"
  local source_pyproject="$INSTALLER_DIR/pyproject.toml"
  local source_lock="$INSTALLER_DIR/uv.lock"
  local target_pyproject="$RESOLVED_SKILL_PATH/pyproject.toml"
  local target_lock="$RESOLVED_SKILL_PATH/uv.lock"
  local copy_status

  if [[ -z "$RESOLVED_SKILL_PATH" ]]; then
    fatal_phase "$phase" "Resolved skill path is empty; refusing metadata copy." "Resolve installer paths before provisioning."
  fi

  log_phase "$phase" "Copying project metadata into $RESOLVED_SKILL_PATH"

  if [[ ! -e "$source_pyproject" ]]; then
    fatal_phase "$phase" "Required metadata file is missing: $source_pyproject" "Restore repo-root pyproject.toml and rerun."
  fi

  if [[ ! -f "$source_pyproject" ]]; then
    fatal_phase "$phase" "Required metadata path is not a regular file: $source_pyproject" "Replace it with a readable pyproject.toml file and rerun."
  fi

  if [[ ! -r "$source_pyproject" ]]; then
    fatal_phase "$phase" "Required metadata file is not readable: $source_pyproject" "Grant read permissions on pyproject.toml and rerun."
  fi

  if [[ ! -s "$source_pyproject" ]]; then
    fatal_phase "$phase" "Required metadata file is empty: $source_pyproject" "Populate pyproject.toml with a valid dependency manifest and rerun."
  fi

  set +e
  cp "$source_pyproject" "$target_pyproject"
  copy_status=$?
  set -e

  if [[ $copy_status -ne 0 ]]; then
    fatal_phase "$phase" "Failed to copy '$source_pyproject' to '$target_pyproject' (exit $copy_status)." "Check destination filesystem permissions and rerun."
  fi

  if [[ ! -f "$target_pyproject" ]]; then
    fatal_phase "$phase" "Metadata copy reported success but target file is missing: $target_pyproject" "Inspect filesystem behavior and rerun."
  fi

  if [[ ! -s "$target_pyproject" ]]; then
    fatal_phase "$phase" "Copied metadata file is empty at target: $target_pyproject" "Inspect source metadata and filesystem behavior, then rerun."
  fi

  log_phase "$phase" "Copied required metadata: $target_pyproject"

  if [[ -e "$source_lock" ]]; then
    if [[ ! -f "$source_lock" ]]; then
      fatal_phase "$phase" "Optional lockfile path exists but is not a regular file: $source_lock" "Replace it with a readable uv.lock file or remove it before rerunning."
    fi

    if [[ ! -r "$source_lock" ]]; then
      fatal_phase "$phase" "Optional lockfile is not readable: $source_lock" "Grant read permissions on uv.lock or remove it before rerunning."
    fi

    set +e
    cp "$source_lock" "$target_lock"
    copy_status=$?
    set -e

    if [[ $copy_status -ne 0 ]]; then
      fatal_phase "$phase" "Failed to copy '$source_lock' to '$target_lock' (exit $copy_status)." "Check destination filesystem permissions and rerun."
    fi

    if [[ ! -f "$target_lock" ]]; then
      fatal_phase "$phase" "Metadata copy reported success but target file is missing: $target_lock" "Inspect filesystem behavior and rerun."
    fi

    log_phase "$phase" "Copied optional lockfile: $target_lock"
  else
    log_phase "$phase" "Optional lockfile not found at $source_lock; skipping lockfile copy."
  fi

  log_phase "$phase" "Metadata copy complete; environment provisioning may proceed."
}

run_uv_venv() {
  local venv_path="$1"

  if [[ -n "${INSTALLER_UV_VENV_CMD:-}" ]]; then
    INSTALLER_VENV_PATH="$venv_path" bash -c "$INSTALLER_UV_VENV_CMD"
  else
    uv venv "$venv_path"
  fi
}

create_local_venv() {
  local venv_status

  if [[ -z "$RESOLVED_VENV_PATH" ]]; then
    fatal_phase "venv" "Resolved venv path is empty." "Check --skill-root/--skill-name values and rerun."
  fi

  log_phase "venv" "Creating local environment at $RESOLVED_VENV_PATH"

  set +e
  run_uv_venv "$RESOLVED_VENV_PATH"
  venv_status=$?
  set -e

  if [[ $venv_status -ne 0 ]]; then
    fatal_phase "venv" "uv venv failed for '$RESOLVED_VENV_PATH' with exit code $venv_status." "Inspect uv output, then rerun after resolving the failure."
  fi

  if [[ ! -d "$RESOLVED_VENV_PATH" ]]; then
    fatal_phase "venv" "uv venv reported success but expected path is missing: $RESOLVED_VENV_PATH" "Inspect uv output and verify the target path before retrying."
  fi

  log_phase "venv" "Local environment ready: $RESOLVED_VENV_PATH"
}

run_uv_pip_install() {
  local venv_path="$1"
  local package_spec="$2"

  if [[ -n "${INSTALLER_UV_PIP_INSTALL_CMD:-}" ]]; then
    INSTALLER_VENV_PATH="$venv_path" INSTALLER_PACKAGE_SPEC="$package_spec" bash -c "$INSTALLER_UV_PIP_INSTALL_CMD"
  else
    uv pip install --python "$venv_path/bin/python" "$package_spec"
  fi
}

install_ddgs_package() {
  local package_status
  local package_spec="ddgs[api,mcp]"

  if [[ -z "$RESOLVED_VENV_PATH" ]]; then
    fatal_phase "package-install" "Resolved venv path is empty; cannot install packages." "Resolve installer paths and rerun."
  fi

  log_phase "package-install" "Installing $package_spec into $RESOLVED_VENV_PATH"

  set +e
  run_uv_pip_install "$RESOLVED_VENV_PATH" "$package_spec"
  package_status=$?
  set -e

  if [[ $package_status -ne 0 ]]; then
    fatal_phase "package-install" "uv pip install failed for '$RESOLVED_VENV_PATH' with exit code $package_status." "Inspect uv output in the local environment and rerun when resolved."
  fi

  log_phase "package-install" "Package installation completed in $RESOLVED_VENV_PATH"
}

verify_ddgs_executable() {
  local ddgs_path

  if [[ -z "$RESOLVED_VENV_PATH" ]]; then
    fatal_phase "executable-verification" "Resolved venv path is empty; cannot verify executable." "Resolve installer paths and rerun."
  fi

  ddgs_path="$RESOLVED_VENV_PATH/bin/ddgs"
  log_phase "executable-verification" "Checking executable at $ddgs_path"

  if [[ ! -e "$ddgs_path" ]]; then
    fatal_phase "executable-verification" "Missing ddgs executable after install: $ddgs_path" "Inspect package installation output and rerun in a clean target directory."
  fi

  if [[ ! -x "$ddgs_path" ]]; then
    fatal_phase "executable-verification" "ddgs path is not executable: $ddgs_path" "Fix permissions or reinstall the local environment before retrying."
  fi

  RESOLVED_DDGS_PATH="$ddgs_path"
  log_phase "executable-verification" "Verified executable: $ddgs_path"
}

render_skill_template() {
  local phase="template-render"
  local template_path="$INSTALLER_DIR/SKILL.md.jinja"
  local destination_path="$RESOLVED_SKILL_PATH/SKILL.md"
  local temp_path=""
  local template_content=""
  local rendered_content=""
  local read_status
  local mktemp_status
  local write_status
  local rename_status

  if [[ -z "$RESOLVED_SKILL_PATH" ]]; then
    fatal_phase "$phase" "Resolved skill path is empty; cannot render SKILL.md." "Resolve installer paths and rerun."
  fi

  if [[ -z "$RESOLVED_DDGS_PATH" ]]; then
    fatal_phase "$phase" "Resolved ddgs executable path is unavailable." "Run executable verification before template rendering."
  fi

  log_phase "$phase" "Rendering SKILL.md from $template_path"

  if [[ ! -e "$template_path" ]]; then
    fatal_phase "$phase" "Template not found: $template_path" "Restore SKILL.md.jinja in the installer repository and rerun."
  fi

  if [[ ! -f "$template_path" ]]; then
    fatal_phase "$phase" "Template path is not a regular file: $template_path" "Replace it with a readable SKILL.md.jinja file and rerun."
  fi

  if [[ ! -r "$template_path" ]]; then
    fatal_phase "$phase" "Template file is not readable: $template_path" "Grant read permissions on SKILL.md.jinja and rerun."
  fi

  set +e
  template_content="$(<"$template_path")"
  read_status=$?
  set -e

  if [[ $read_status -ne 0 ]]; then
    fatal_phase "$phase" "Failed to read template: $template_path" "Inspect template permissions/content and rerun."
  fi

  if [[ -z "$template_content" ]]; then
    fatal_phase "$phase" "Template content is empty: $template_path" "Populate SKILL.md.jinja with valid skill content and rerun."
  fi

  rendered_content="$template_content"
  rendered_content="${rendered_content//\{\{SKILL_NAME\}\}/$SKILL_NAME}"
  rendered_content="${rendered_content//\{\{SERVER_NAME\}\}/$SERVER_NAME}"
  rendered_content="${rendered_content//\{\{DDGS_EXECUTABLE_PATH\}\}/$RESOLVED_DDGS_PATH}"

  if [[ -z "$rendered_content" ]]; then
    fatal_phase "$phase" "Rendered SKILL.md content is empty after substitution." "Check template placeholders and rerun."
  fi

  if [[ "$rendered_content" == *"{{SKILL_NAME}}"* || "$rendered_content" == *"{{SERVER_NAME}}"* || "$rendered_content" == *"{{DDGS_EXECUTABLE_PATH}}"* ]]; then
    fatal_phase "$phase" "Template placeholder substitution failed for one or more required variables." "Ensure SKILL.md.jinja uses {{SKILL_NAME}}, {{SERVER_NAME}}, and {{DDGS_EXECUTABLE_PATH}} exactly."
  fi

  set +e
  temp_path="$(mktemp "$RESOLVED_SKILL_PATH/.SKILL.md.tmp.XXXXXX")"
  mktemp_status=$?
  set -e

  if [[ $mktemp_status -ne 0 || -z "$temp_path" ]]; then
    fatal_phase "$phase" "Failed to create temporary render file under $RESOLVED_SKILL_PATH." "Check destination directory permissions and retry."
  fi

  set +e
  printf '%s\n' "$rendered_content" >"$temp_path"
  write_status=$?
  set -e

  if [[ $write_status -ne 0 ]]; then
    rm -f "$temp_path" || true
    fatal_phase "$phase" "Failed writing rendered content to temporary file: $temp_path" "Check destination directory permissions and available disk space, then rerun."
  fi

  set +e
  mv -f "$temp_path" "$destination_path"
  rename_status=$?
  set -e

  if [[ $rename_status -ne 0 ]]; then
    rm -f "$temp_path" || true
    fatal_phase "$phase" "Failed to publish rendered SKILL.md to $destination_path." "Check destination path permissions and retry."
  fi

  if [[ ! -f "$destination_path" ]]; then
    fatal_phase "$phase" "Render completed but destination file is missing: $destination_path" "Inspect filesystem behavior and rerun the installer."
  fi

  log_phase "$phase" "Rendered skill document: $destination_path"
}

json_escape_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

emit_mcp_handoff_snippet() {
  local phase="install"
  local escaped_server_name
  local escaped_ddgs_path

  if [[ -z "$SERVER_NAME" ]]; then
    fatal_phase "$phase" "Resolved server name is empty; refusing to emit MCP handoff snippet." "Set --server-name to a non-empty value and rerun."
  fi

  if [[ -z "$RESOLVED_DDGS_PATH" ]]; then
    fatal_phase "$phase" "Resolved ddgs executable path is empty; refusing to emit MCP handoff snippet." "Resolve executable verification before emitting handoff output."
  fi

  escaped_server_name="$(json_escape_string "$SERVER_NAME")"
  escaped_ddgs_path="$(json_escape_string "$RESOLVED_DDGS_PATH")"

  log_phase "$phase" "Final MCP handoff snippet (copy under mcpServers in your MCP config):"
  printf '{\n'
  printf '  "mcpServers": {\n'
  printf '    "%s": {\n' "$escaped_server_name"
  printf '      "command": "%s",\n' "$escaped_ddgs_path"
  printf '      "args": ["mcp"]\n'
  printf '    }\n'
  printf '  }\n'
  printf '}\n'
}

provision_skill_environment() {
  log_phase "filesystem" "Validating destination paths."
  resolve_install_paths
  validate_destination_paths
  create_skill_directory
  copy_project_metadata
  create_local_venv
  install_ddgs_package
  verify_ddgs_executable
  render_skill_template
}

main() {
  parse_args "$@"
  resolve_config
  check_platform
  ensure_uv
  provision_skill_environment
  emit_mcp_handoff_snippet
  log_phase "install" "S04 install complete. Local ddgs environment is ready."
}

main "$@"
