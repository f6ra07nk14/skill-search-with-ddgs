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
Renders a single-file SKILL.md whose frontmatter description stays trigger-only.
The generated body keeps Overview, When to Use, one Workflow, and Common Mistakes.
On success, the final mcpServers handoff points at the installed .venv/bin/ddgs path.
For deeper DDGS details, use runtime tool inspection or current docs instead of inline generated tables.

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

run_uv_sync() {
  local project_dir="$1"

  if [[ -n "${INSTALLER_UV_SYNC_CMD:-}" ]]; then
    INSTALLER_PROJECT_DIR="$project_dir" \
    INSTALLER_SKILL_PATH="$project_dir" \
    INSTALLER_VENV_PATH="$project_dir/.venv" \
    INSTALLER_DDGS_PATH="$project_dir/.venv/bin/ddgs" \
    bash -c "$INSTALLER_UV_SYNC_CMD"
  else
    uv sync --directory "$project_dir"
  fi
}

sync_project_environment() {
  local phase="project-sync"
  local sync_status
  local target_pyproject="$RESOLVED_SKILL_PATH/pyproject.toml"
  local target_lock="$RESOLVED_SKILL_PATH/uv.lock"

  if [[ -z "$RESOLVED_SKILL_PATH" ]]; then
    fatal_phase "$phase" "Resolved skill path is empty; cannot sync project environment." "Resolve installer paths before provisioning."
  fi

  if [[ ! -f "$target_pyproject" ]]; then
    fatal_phase "$phase" "Required metadata is missing at target: $target_pyproject" "Recreate the target directory from repo metadata and rerun."
  fi

  if [[ ! -s "$target_pyproject" ]]; then
    fatal_phase "$phase" "Required metadata is empty at target: $target_pyproject" "Repair target pyproject.toml and rerun."
  fi

  log_phase "$phase" "Running uv sync --directory '$RESOLVED_SKILL_PATH'"

  set +e
  run_uv_sync "$RESOLVED_SKILL_PATH"
  sync_status=$?
  set -e

  if [[ $sync_status -ne 0 ]]; then
    fatal_phase "$phase" "uv sync failed for '$RESOLVED_SKILL_PATH' with exit code $sync_status." "Inspect sync output and target metadata, then rerun."
  fi

  if [[ -f "$target_lock" ]]; then
    log_phase "$phase" "Retained target lockfile: $target_lock"
  else
    log_phase "$phase" "No target lockfile found after sync; continuing with executable verification."
  fi

  log_phase "$phase" "Project sync complete for $RESOLVED_SKILL_PATH"
}

verify_ddgs_executable() {
  local ddgs_path

  if [[ -z "$RESOLVED_VENV_PATH" ]]; then
    fatal_phase "executable-verification" "Resolved venv path is empty; cannot verify executable." "Resolve installer paths and rerun."
  fi

  ddgs_path="$RESOLVED_VENV_PATH/bin/ddgs"
  log_phase "executable-verification" "Checking executable at $ddgs_path"

  if [[ ! -e "$ddgs_path" ]]; then
    fatal_phase "executable-verification" "Missing ddgs executable after install: $ddgs_path" "Inspect project-sync output and rerun in a clean target directory."
  fi

  if [[ ! -x "$ddgs_path" ]]; then
    fatal_phase "executable-verification" "ddgs path is not executable: $ddgs_path" "Fix permissions or reinstall the local environment before retrying."
  fi

  RESOLVED_DDGS_PATH="$ddgs_path"
  log_phase "executable-verification" "Verified executable: $ddgs_path"
}

render_skill_template() {
  local phase="template-render"
  local source_renderer="$INSTALLER_DIR/render_skill.py"
  local source_template="$INSTALLER_DIR/SKILL.md.jinja"
  local destination_path="$RESOLVED_SKILL_PATH/SKILL.md"
  local stage_dir="$RESOLVED_SKILL_PATH/.template-render-stage"
  local staged_renderer="$stage_dir/render_skill.py"
  local staged_template="$stage_dir/SKILL.md.jinja"
  local venv_python="$RESOLVED_VENV_PATH/bin/python"
  local stage_status
  local render_status
  local cleanup_status
  local render_output=""

  if [[ -z "$RESOLVED_SKILL_PATH" ]]; then
    fatal_phase "$phase" "Resolved skill path is empty; cannot render SKILL.md." "Resolve installer paths and rerun."
  fi

  if [[ -z "$RESOLVED_DDGS_PATH" ]]; then
    fatal_phase "$phase" "Resolved ddgs executable path is unavailable." "Run executable verification before template rendering."
  fi

  if [[ -z "$RESOLVED_VENV_PATH" ]]; then
    fatal_phase "$phase" "Resolved venv path is empty; cannot execute target-local renderer." "Resolve installer paths and rerun."
  fi

  if [[ ! -e "$source_renderer" ]]; then
    fatal_phase "$phase" "Render helper not found: $source_renderer" "Restore render_skill.py in the installer repository and rerun."
  fi

  if [[ ! -f "$source_renderer" ]]; then
    fatal_phase "$phase" "Render helper path is not a regular file: $source_renderer" "Replace it with a readable render_skill.py file and rerun."
  fi

  if [[ ! -r "$source_renderer" ]]; then
    fatal_phase "$phase" "Render helper file is not readable: $source_renderer" "Grant read permissions on render_skill.py and rerun."
  fi

  if [[ ! -e "$source_template" ]]; then
    fatal_phase "$phase" "Template not found: $source_template" "Restore SKILL.md.jinja in the installer repository and rerun."
  fi

  if [[ ! -f "$source_template" ]]; then
    fatal_phase "$phase" "Template path is not a regular file: $source_template" "Replace it with a readable SKILL.md.jinja file and rerun."
  fi

  if [[ ! -r "$source_template" ]]; then
    fatal_phase "$phase" "Template file is not readable: $source_template" "Grant read permissions on SKILL.md.jinja and rerun."
  fi

  if [[ ! -x "$venv_python" ]]; then
    fatal_phase "$phase" "Target-local python executable is missing or not executable: $venv_python" "Ensure project sync provisions .venv/bin/python before template rendering."
  fi

  log_phase "$phase" "Staging render helper and template into $stage_dir"

  set +e
  mkdir -p "$stage_dir"
  stage_status=$?
  set -e

  if [[ $stage_status -ne 0 ]]; then
    fatal_phase "$phase" "Failed to create staging directory under $RESOLVED_SKILL_PATH." "Check destination directory permissions and retry."
  fi

  set +e
  cp "$source_renderer" "$staged_renderer"
  stage_status=$?
  set -e

  if [[ $stage_status -ne 0 ]]; then
    fatal_phase "$phase" "Failed to stage render helper into $stage_dir." "Check source/destination permissions and retry."
  fi

  set +e
  cp "$source_template" "$staged_template"
  stage_status=$?
  set -e

  if [[ $stage_status -ne 0 ]]; then
    fatal_phase "$phase" "Failed to stage template into $stage_dir." "Check source/destination permissions and retry."
  fi

  if [[ ! -s "$staged_renderer" ]]; then
    fatal_phase "$phase" "Staged render helper is empty or missing: $staged_renderer" "Restore render_skill.py and retry."
  fi

  if [[ ! -s "$staged_template" ]]; then
    fatal_phase "$phase" "Staged template is empty or missing: $staged_template" "Restore SKILL.md.jinja and retry."
  fi

  log_phase "$phase" "Rendering SKILL.md via target-local interpreter: $venv_python"

  set +e
  render_output="$(PYTHONDONTWRITEBYTECODE=1 "$venv_python" "$staged_renderer" \
    --template "$staged_template" \
    --destination "$destination_path" \
    --skill-name "$SKILL_NAME" \
    --server-name "$SERVER_NAME" \
    --ddgs-executable-path "$RESOLVED_DDGS_PATH" 2>&1)"
  render_status=$?
  set -e

  if [[ $render_status -ne 0 ]]; then
    if [[ -n "$render_output" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        error_phase "$phase" "$line"
      done <<< "$render_output"
    fi
    fatal_phase "$phase" "Target-local render helper failed with exit code $render_status." "Inspect staged helper output above and rerun after fixing template/runtime issues."
  fi

  if [[ ! -f "$destination_path" ]]; then
    fatal_phase "$phase" "Render completed but destination file is missing: $destination_path" "Inspect filesystem behavior and rerun the installer."
  fi

  set +e
  rm -rf "$stage_dir"
  cleanup_status=$?
  set -e

  if [[ $cleanup_status -ne 0 ]]; then
    fatal_phase "$phase" "Rendered SKILL.md but failed to remove staged helper files from $stage_dir." "Inspect filesystem permissions under the target directory and remove staged files before rerunning."
  fi

  log_phase "$phase" "Removed staged render helpers from $stage_dir"
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
  sync_project_environment
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
