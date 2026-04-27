#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/install.sh"
SOURCE_PYPROJECT="$ROOT_DIR/pyproject.toml"
SOURCE_LOCK="$ROOT_DIR/uv.lock"
SOURCE_TEMPLATE="$ROOT_DIR/SKILL.md.jinja"

INSTALLER_UV_SYNC_CMD_DEFAULT='mkdir -p "$INSTALLER_VENV_PATH/bin" && ln -sf "$(command -v python3)" "$INSTALLER_VENV_PATH/bin/python" && : > "$INSTALLER_DDGS_PATH" && chmod +x "$INSTALLER_DDGS_PATH" && : > "$INSTALLER_PROJECT_DIR/uv.lock"'

TEST_TMP_ROOT=""
TEST_HOME=""

fail_test() {
  printf 'FAIL: %s\n' "$1" >&2
  return 1
}

setup_test_env() {
  TEST_TMP_ROOT="$(mktemp -d)"
  TEST_HOME="$TEST_TMP_ROOT/home"
  mkdir -p "$TEST_HOME"
  export TEST_TMP_ROOT TEST_HOME
}

teardown_test_env() {
  if [[ -n "${TEST_TMP_ROOT:-}" && -d "${TEST_TMP_ROOT:-}" ]]; then
    rm -rf "$TEST_TMP_ROOT"
  fi
}

make_temp_dir() {
  mktemp -d "$TEST_TMP_ROOT/tmp.XXXXXX"
}

make_fake_uv_bin() {
  local dir
  dir="$(mktemp -d "$TEST_TMP_ROOT/bin.XXXXXX")"
  cat >"$dir/uv" <<'UV'
#!/usr/bin/env bash
exit 0
UV
  chmod +x "$dir/uv"
  printf '%s' "$dir"
}

make_empty_bin() {
  mktemp -d "$TEST_TMP_ROOT/bin-empty.XXXXXX"
}

init_source_metadata_fixtures() {
  SOURCE_PYPROJECT_BACKUP=""
  SOURCE_LOCK_BACKUP=""
  SOURCE_LOCK_CREATED_BY_TEST=0
  SOURCE_PYPROJECT_MODE="$(stat -c '%a' "$SOURCE_PYPROJECT" 2>/dev/null || true)"
  SOURCE_LOCK_MODE=""

  if [[ -e "$SOURCE_LOCK" ]]; then
    SOURCE_LOCK_MODE="$(stat -c '%a' "$SOURCE_LOCK" 2>/dev/null || true)"
  fi
}

backup_source_pyproject() {
  if [[ -n "${SOURCE_PYPROJECT_BACKUP:-}" ]]; then
    return
  fi

  SOURCE_PYPROJECT_BACKUP="$TEST_TMP_ROOT/source-pyproject.backup"
  mv "$SOURCE_PYPROJECT" "$SOURCE_PYPROJECT_BACKUP"
}

restore_source_pyproject() {
  if [[ -n "${SOURCE_PYPROJECT_BACKUP:-}" && -e "$SOURCE_PYPROJECT_BACKUP" ]]; then
    mv "$SOURCE_PYPROJECT_BACKUP" "$SOURCE_PYPROJECT"
  fi

  if [[ -n "${SOURCE_PYPROJECT_MODE:-}" && -e "$SOURCE_PYPROJECT" ]]; then
    chmod "$SOURCE_PYPROJECT_MODE" "$SOURCE_PYPROJECT"
  fi
}

backup_source_lock_if_present() {
  if [[ -n "${SOURCE_LOCK_BACKUP:-}" ]]; then
    return
  fi

  SOURCE_LOCK_BACKUP=""

  if [[ -e "$SOURCE_LOCK" ]]; then
    SOURCE_LOCK_BACKUP="$TEST_TMP_ROOT/source-lock.backup"
    mv "$SOURCE_LOCK" "$SOURCE_LOCK_BACKUP"
  fi
}

restore_source_lock() {
  if [[ -n "${SOURCE_LOCK_BACKUP:-}" && -e "$SOURCE_LOCK_BACKUP" ]]; then
    rm -f "$SOURCE_LOCK"
    mv "$SOURCE_LOCK_BACKUP" "$SOURCE_LOCK"

    if [[ -n "${SOURCE_LOCK_MODE:-}" && -e "$SOURCE_LOCK" ]]; then
      chmod "$SOURCE_LOCK_MODE" "$SOURCE_LOCK"
    fi

    return
  fi

  if [[ "${SOURCE_LOCK_CREATED_BY_TEST:-0}" -eq 1 ]]; then
    rm -f "$SOURCE_LOCK"
  fi
}

write_source_lock_fixture() {
  local content="$1"

  printf '%s' "$content" >"$SOURCE_LOCK"
  SOURCE_LOCK_CREATED_BY_TEST=1
}

init_source_template_fixture() {
  SOURCE_TEMPLATE_BACKUP=""
  SOURCE_TEMPLATE_MODE="$(stat -c '%a' "$SOURCE_TEMPLATE" 2>/dev/null || true)"
}

backup_source_template() {
  if [[ -n "${SOURCE_TEMPLATE_BACKUP:-}" ]]; then
    return
  fi

  SOURCE_TEMPLATE_BACKUP="$TEST_TMP_ROOT/source-template.backup"
  mv "$SOURCE_TEMPLATE" "$SOURCE_TEMPLATE_BACKUP"
}

restore_source_template() {
  if [[ -n "${SOURCE_TEMPLATE_BACKUP:-}" && -e "$SOURCE_TEMPLATE_BACKUP" ]]; then
    rm -f "$SOURCE_TEMPLATE"
    mv "$SOURCE_TEMPLATE_BACKUP" "$SOURCE_TEMPLATE"
  fi

  if [[ -n "${SOURCE_TEMPLATE_MODE:-}" && -e "$SOURCE_TEMPLATE" ]]; then
    chmod "$SOURCE_TEMPLATE_MODE" "$SOURCE_TEMPLATE"
  fi
}

restore_source_metadata_fixtures() {
  restore_source_lock
  restore_source_pyproject
}

run_installer() {
  local fakebin="$1"
  local home_dir="$2"
  shift 2

  env -i \
    HOME="$home_dir" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_UV_SYNC_CMD="$INSTALLER_UV_SYNC_CMD_DEFAULT" \
    bash "$INSTALLER" "$@"
}

run_installer_force_interactive() {
  local stdin_input="$1"
  local fakebin="$2"
  local home_dir="$3"
  shift 3

  printf '%s' "$stdin_input" | env -i \
    HOME="$home_dir" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_FORCE_INTERACTIVE=1 \
    INSTALLER_UV_SYNC_CMD="$INSTALLER_UV_SYNC_CMD_DEFAULT" \
    bash "$INSTALLER" "$@"
}

run_installer_env() {
  local fakebin="$1"
  local home_dir="$2"
  local -a extra_env=()
  shift 2

  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      break
    fi
    extra_env+=("$1")
    shift
  done

  env -i \
    HOME="$home_dir" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_UV_SYNC_CMD="$INSTALLER_UV_SYNC_CMD_DEFAULT" \
    "${extra_env[@]}" \
    bash "$INSTALLER" "$@"
}

run_installer_raw_env() {
  local fakebin="$1"
  local home_dir="$2"
  local -a extra_env=()
  shift 2

  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      break
    fi
    extra_env+=("$1")
    shift
  done

  env -i \
    HOME="$home_dir" \
    PATH="$fakebin:/usr/bin:/bin" \
    "${extra_env[@]}" \
    bash "$INSTALLER" "$@"
}

run_installer_raw_force_interactive() {
  local stdin_input="$1"
  local fakebin="$2"
  local home_dir="$3"
  shift 3

  printf '%s' "$stdin_input" | env -i \
    HOME="$home_dir" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_FORCE_INTERACTIVE=1 \
    bash "$INSTALLER" "$@"
}

assert_success() {
  local context="$1"
  [[ "$status" -eq 0 ]] || fail_test "$context (expected status 0, got $status)"
}

assert_failure() {
  local context="$1"
  [[ "$status" -ne 0 ]] || fail_test "$context (expected non-zero status, got 0)"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  [[ "$haystack" == *"$needle"* ]] || fail_test "$context (missing: $needle)"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  [[ "$haystack" != *"$needle"* ]] || fail_test "$context (unexpected: $needle)"
}

assert_output_contains() {
  local needle="$1"
  local context="$2"
  assert_contains "$output" "$needle" "$context"
}

assert_output_not_contains() {
  local needle="$1"
  local context="$2"
  assert_not_contains "$output" "$needle" "$context"
}

assert_occurrence_count() {
  local haystack="$1"
  local needle="$2"
  local expected_count="$3"
  local context="$4"
  local actual_count

  actual_count=$( (grep -Fo -- "$needle" <<<"$haystack" | wc -l | tr -d ' ') || true )
  [[ "$actual_count" == "$expected_count" ]] || fail_test "$context (expected $expected_count, got $actual_count for: $needle)"
}

assert_line_order() {
  local haystack="$1"
  local first="$2"
  local second="$3"
  local context="$4"
  local first_line
  local second_line

  first_line=$(grep -nF -- "$first" <<<"$haystack" | head -n1 | cut -d: -f1)
  second_line=$(grep -nF -- "$second" <<<"$haystack" | head -n1 | cut -d: -f1)

  [[ -n "$first_line" ]] || fail_test "$context (missing first marker: $first)"
  [[ -n "$second_line" ]] || fail_test "$context (missing second marker: $second)"
  (( first_line < second_line )) || fail_test "$context (expected '$first' before '$second')"
}

run_installer_with_sync_hook() {
  local fakebin="$1"
  local home_dir="$2"
  local skill_root="$3"
  local skill_name="$4"
  local sync_hook="$5"
  local python_bootstrap_hook
  local combined_sync_hook
  shift 5

  if [[ -z "$sync_hook" ]]; then
    fail_test "sync hook must not be empty"
    return 1
  fi

  python_bootstrap_hook='mkdir -p "$INSTALLER_VENV_PATH/bin" && ln -sf "$(command -v python3)" "$INSTALLER_VENV_PATH/bin/python"'
  combined_sync_hook="$python_bootstrap_hook && $sync_hook"

  run_installer_env "$fakebin" "$home_dir" \
    "INSTALLER_UV_SYNC_CMD=$combined_sync_hook" \
    -- \
    --non-interactive \
    --skill-root "$skill_root" \
    --skill-name "$skill_name" \
    "$@"
}

assert_no_mutation() {
  local root="$1"
  local skill_name="$2"

  [[ ! -e "$root" ]] || fail_test "preflight should not create skill root: $root"
  [[ ! -e "$root/$skill_name" ]] || fail_test "preflight should not create skill directory: $root/$skill_name"
}

assert_preflight_abort() {
  local haystack="$1"
  local context="$2"

  assert_not_contains "$haystack" "[phase:metadata-copy]" "$context should stop before metadata copy"
  assert_not_contains "$haystack" "[phase:project-sync]" "$context should stop before project sync"
  assert_not_contains "$haystack" '"mcpServers": {' "$context should not emit MCP handoff snippet"
  assert_not_contains "$haystack" "[phase:install] S04 install complete. Local ddgs environment is ready." "$context should not emit completion line"
}
