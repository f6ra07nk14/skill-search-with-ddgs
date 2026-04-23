#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/install.sh"
SOURCE_PYPROJECT="$ROOT_DIR/pyproject.toml"
SOURCE_LOCK="$ROOT_DIR/uv.lock"

PASS_COUNT=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$context (missing: $needle)"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  [[ "$haystack" != *"$needle"* ]] || fail "$context (unexpected: $needle)"
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

  [[ -n "$first_line" ]] || fail "$context (missing first marker: $first)"
  [[ -n "$second_line" ]] || fail "$context (missing second marker: $second)"
  (( first_line < second_line )) || fail "$context (expected '$first' before '$second')"
}

make_fake_uv_bin() {
  local dir
  dir="$(mktemp -d)"
  cat >"$dir/uv" <<'UV'
#!/usr/bin/env bash
exit 0
UV
  chmod +x "$dir/uv"
  printf '%s' "$dir"
}

run_installer_with_hooks() {
  local fakebin="$1"
  local home_dir="$2"
  local skill_root="$3"
  local skill_name="$4"
  local venv_hook="$5"
  local pip_hook="$6"
  shift 6

  env -i \
    HOME="$home_dir" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_UV_VENV_CMD="$venv_hook" \
    INSTALLER_UV_PIP_INSTALL_CMD="$pip_hook" \
    bash "$INSTALLER" --non-interactive --skill-root "$skill_root" --skill-name "$skill_name" "$@"
}

# 1) metadata copy runs before environment provisioning and copies pyproject.toml
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="metadata-before-venv"

  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'target_dir="${INSTALLER_VENV_PATH%/.venv}"; [[ -f "$target_dir/pyproject.toml" ]] || { echo "pyproject missing before venv" >&2; exit 71; }; mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' 2>&1)"

  target_dir="$skill_root/$skill_name"
  target_pyproject="$target_dir/pyproject.toml"

  [[ -f "$target_pyproject" ]] || fail "metadata-copy should place pyproject.toml in target directory"
  cmp -s "$SOURCE_PYPROJECT" "$target_pyproject" || fail "copied target pyproject.toml should match source manifest"
  assert_contains "$output" "[phase:metadata-copy] Copying project metadata into $target_dir" "metadata-copy phase start"
  assert_contains "$output" "[phase:metadata-copy] Copied required metadata: $target_pyproject" "metadata-copy copied pyproject"
  assert_contains "$output" "[phase:metadata-copy] Metadata copy complete; environment provisioning may proceed." "metadata-copy completion"
  assert_line_order "$output" "[phase:metadata-copy] Metadata copy complete; environment provisioning may proceed." "[phase:venv] Creating local environment at $target_dir/.venv" "metadata-copy should finish before venv creation"
  pass "metadata-copy boundary executes before environment provisioning"
}

# 2) absent source uv.lock is tolerated and logged
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="no-source-lock"
  backup_lock=""

  if [[ -e "$SOURCE_LOCK" ]]; then
    backup_lock="$ROOT_DIR/.uv.lock.backup.$$.$RANDOM"
    mv "$SOURCE_LOCK" "$backup_lock"
  fi

  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' 2>&1)"

  if [[ -n "$backup_lock" && -e "$backup_lock" ]]; then
    mv "$backup_lock" "$SOURCE_LOCK"
  fi

  target_lock="$skill_root/$skill_name/uv.lock"
  [[ ! -e "$target_lock" ]] || fail "installer should not create target uv.lock when source lockfile is absent"
  assert_contains "$output" "[phase:metadata-copy] Optional lockfile not found at $SOURCE_LOCK; skipping lockfile copy." "absent lockfile should be logged"
  pass "missing source uv.lock does not fail metadata-copy phase"
}

# 3) present source uv.lock is copied into the target directory
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="with-source-lock"
  backup_lock=""

  if [[ -e "$SOURCE_LOCK" ]]; then
    backup_lock="$ROOT_DIR/.uv.lock.backup.$$.$RANDOM"
    mv "$SOURCE_LOCK" "$backup_lock"
  fi

  printf 'version = 1\nrevision = "fixture-lock"\n' >"$SOURCE_LOCK"

  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' 2>&1)"

  if [[ -n "$backup_lock" && -e "$backup_lock" ]]; then
    rm -f "$SOURCE_LOCK"
    mv "$backup_lock" "$SOURCE_LOCK"
  else
    rm -f "$SOURCE_LOCK"
  fi

  target_lock="$skill_root/$skill_name/uv.lock"
  [[ -f "$target_lock" ]] || fail "installer should copy source uv.lock when present"
  target_lock_content="$(<"$target_lock")"
  assert_contains "$target_lock_content" "fixture-lock" "copied target uv.lock should preserve source contents"
  assert_contains "$output" "[phase:metadata-copy] Copied optional lockfile: $target_lock" "metadata-copy should log copied lockfile"
  pass "source uv.lock is retained in target when present"
}

# 4) missing pyproject.toml fails in metadata-copy phase before venv/package/template/handoff
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="missing-pyproject"
  backup_pyproject="$ROOT_DIR/.pyproject.toml.backup.$$.$RANDOM"

  mv "$SOURCE_PYPROJECT" "$backup_pyproject"

  set +e
  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' 2>&1)"
  status=$?
  set -e

  mv "$backup_pyproject" "$SOURCE_PYPROJECT"

  [[ $status -ne 0 ]] || fail "missing pyproject.toml should fail install"
  assert_contains "$output" "[phase:metadata-copy] ERROR: Required metadata file is missing: $SOURCE_PYPROJECT" "missing pyproject phase error"
  assert_not_contains "$output" "[phase:venv]" "missing pyproject should stop before venv creation"
  assert_not_contains "$output" "[phase:package-install]" "missing pyproject should stop before package install"
  assert_not_contains "$output" "[phase:template-render]" "missing pyproject should stop before template render"
  assert_not_contains "$output" '"mcpServers": {' "missing pyproject should stop before handoff snippet"
  pass "missing pyproject fails fast in metadata-copy phase"
}

# 5) unreadable pyproject.toml fails in metadata-copy phase before provisioning
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="unreadable-pyproject"

  chmod 000 "$SOURCE_PYPROJECT"

  set +e
  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' 2>&1)"
  status=$?
  set -e

  chmod 644 "$SOURCE_PYPROJECT"

  [[ $status -ne 0 ]] || fail "unreadable pyproject.toml should fail install"
  assert_contains "$output" "[phase:metadata-copy] ERROR: Required metadata file is not readable: $SOURCE_PYPROJECT" "unreadable pyproject phase error"
  assert_not_contains "$output" "[phase:venv]" "unreadable pyproject should stop before venv creation"
  assert_not_contains "$output" '"mcpServers": {' "unreadable pyproject should stop before handoff snippet"
  pass "unreadable pyproject is rejected before provisioning"
}

# 6) unreadable source uv.lock fails in metadata-copy phase before provisioning
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="unreadable-lock"
  backup_lock=""

  if [[ -e "$SOURCE_LOCK" ]]; then
    backup_lock="$ROOT_DIR/.uv.lock.backup.$$.$RANDOM"
    mv "$SOURCE_LOCK" "$backup_lock"
  fi

  printf 'version = 1\nrevision = "unreadable"\n' >"$SOURCE_LOCK"
  chmod 000 "$SOURCE_LOCK"

  set +e
  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' 2>&1)"
  status=$?
  set -e

  chmod 644 "$SOURCE_LOCK"
  if [[ -n "$backup_lock" && -e "$backup_lock" ]]; then
    rm -f "$SOURCE_LOCK"
    mv "$backup_lock" "$SOURCE_LOCK"
  else
    rm -f "$SOURCE_LOCK"
  fi

  [[ $status -ne 0 ]] || fail "unreadable source uv.lock should fail install"
  assert_contains "$output" "[phase:metadata-copy] ERROR: Optional lockfile is not readable: $SOURCE_LOCK" "unreadable uv.lock phase error"
  assert_not_contains "$output" "[phase:venv]" "unreadable uv.lock should stop before venv creation"
  assert_not_contains "$output" '"mcpServers": {' "unreadable uv.lock should stop before handoff snippet"
  pass "unreadable source uv.lock is rejected before provisioning"
}

# 7) unusual but valid target paths still receive copied metadata
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills root with spaces"
  skill_name='skill name with spaces'

  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' 2>&1)"

  target_pyproject="$skill_root/$skill_name/pyproject.toml"
  [[ -f "$target_pyproject" ]] || fail "metadata-copy should handle unusual valid target paths"
  assert_contains "$output" "[phase:metadata-copy] Copied required metadata: $target_pyproject" "unusual path metadata copy log"
  pass "metadata-copy works with unusual but valid target paths"
}

printf '\nAll tests passed (%d checks).\n' "$PASS_COUNT"
