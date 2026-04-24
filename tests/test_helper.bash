#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/install.sh"

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
