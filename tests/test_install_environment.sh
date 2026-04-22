#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/install.sh"

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

assert_occurrence_count() {
  local haystack="$1"
  local needle="$2"
  local expected_count="$3"
  local context="$4"
  local actual_count

  actual_count=$(grep -Fo -- "$needle" <<<"$haystack" | wc -l | tr -d ' ')
  [[ "$actual_count" == "$expected_count" ]] || fail "$context (expected $expected_count, got $actual_count for: $needle)"
}

assert_file_contains() {
  local file_path="$1"
  local needle="$2"
  local context="$3"
  grep -Fq -- "$needle" "$file_path" || fail "$context (missing: $needle)"
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

# 1) fresh install creates executable + rendered SKILL.md with injected values
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="fresh-skill"
  server_name="fresh-ddgs-server"

  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' \
    --server-name "$server_name" 2>&1)"

  ddgs_path="$skill_root/$skill_name/.venv/bin/ddgs"
  skill_doc="$skill_root/$skill_name/SKILL.md"
  [[ -x "$ddgs_path" ]] || fail "fresh install should create executable: $ddgs_path"
  [[ -s "$skill_doc" ]] || fail "fresh install should create non-empty SKILL.md: $skill_doc"
  assert_file_contains "$skill_doc" "$server_name" "rendered SKILL.md should include selected server name"
  assert_file_contains "$skill_doc" "$ddgs_path" "rendered SKILL.md should include concrete ddgs executable path"
  assert_contains "$output" "[phase:package-install] Installing ddgs[api,mcp]" "fresh install package phase"
  assert_contains "$output" "[phase:executable-verification] Verified executable:" "fresh install executable verification"
  assert_contains "$output" "[phase:template-render] Rendered skill document:" "fresh install template render"
  assert_contains "$output" "[phase:install] Final MCP handoff snippet (copy under mcpServers in your MCP config):" "fresh install handoff log"
  assert_contains "$output" '"mcpServers": {' "fresh install handoff block"
  assert_contains "$output" "\"$server_name\": {" "fresh install handoff server"
  assert_contains "$output" "\"command\": \"$ddgs_path\"" "fresh install handoff command path"
  assert_contains "$output" '"args": ["mcp"]' "fresh install handoff args"
  assert_occurrence_count "$output" '"mcpServers": {' 1 "fresh install should emit exactly one handoff snippet"
  assert_contains "$output" "[phase:install] S04 install complete. Local ddgs environment is ready." "fresh install completion"
  pass "fresh install creates rendered SKILL.md with injected values and MCP handoff"
}

# 2) second run with same target fails conflict without overwrite
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="conflict-skill"

  run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' >/dev/null

  marker="$skill_root/$skill_name/marker.txt"
  printf 'keep' >"$marker"

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

  [[ $status -ne 0 ]] || fail "second run should fail on existing target"
  assert_contains "$output" "[phase:filesystem] ERROR: Target skill directory already exists:" "conflict phase error"
  assert_not_contains "$output" '"mcpServers": {' "conflict path should not emit MCP handoff"
  [[ "$(cat "$marker")" == "keep" ]] || fail "conflict path should not overwrite existing files"
  pass "same-name conflict is refused before mutation"
}

# 3) package-install non-zero exits with package-install phase and leaves venv for inspection
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="package-fail"

  set +e
  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'exit 23' 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "package-install failure should exit non-zero"
  assert_contains "$output" "[phase:package-install] ERROR: uv pip install failed" "package failure phase"
  assert_contains "$output" "exit code 23" "package failure exit code surfaced"
  assert_not_contains "$output" '"mcpServers": {' "package failure should not emit MCP handoff"
  [[ -d "$skill_root/$skill_name/.venv" ]] || fail "venv should remain for inspection after package failure"
  pass "package-install failures are surfaced with phase-prefixed diagnostics"
}

# 4) missing ddgs after install hook reports executable-verification failure
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="missing-ddgs"

  set +e
  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'true' 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "missing ddgs executable should exit non-zero"
  assert_contains "$output" "[phase:executable-verification] ERROR: Missing ddgs executable after install:" "missing ddgs phase error"
  assert_not_contains "$output" '"mcpServers": {' "missing ddgs should not emit MCP handoff"
  pass "missing ddgs path is detected as verification failure"
}

# 5) non-executable ddgs path is rejected
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="non-executable-ddgs"

  set +e
  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod 0644 "$INSTALLER_VENV_PATH/bin/ddgs"' 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "non-executable ddgs should exit non-zero"
  assert_contains "$output" "[phase:executable-verification] ERROR: ddgs path is not executable:" "non-executable ddgs phase error"
  assert_not_contains "$output" '"mcpServers": {' "non-executable ddgs should not emit MCP handoff"
  pass "non-executable ddgs path is rejected"
}

# 6) missing template fails in template-render phase without creating partial SKILL.md
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="missing-template"
  backup_template="$ROOT_DIR/SKILL.md.jinja.bak-test"

  mv "$ROOT_DIR/SKILL.md.jinja" "$backup_template"

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

  mv "$backup_template" "$ROOT_DIR/SKILL.md.jinja"

  [[ $status -ne 0 ]] || fail "missing template should exit non-zero"
  assert_contains "$output" "[phase:template-render] ERROR: Template not found:" "missing template phase error"
  assert_contains "$output" "[phase:template-render] NEXT: Restore SKILL.md.jinja in the installer repository and rerun." "missing template next action"
  assert_not_contains "$output" '"mcpServers": {' "missing template should not emit MCP handoff"
  [[ ! -e "$skill_root/$skill_name/SKILL.md" ]] || fail "missing template should not leave destination SKILL.md"
  pass "missing template fails cleanly without destination artifact"
}

# 7) unreadable template fails in template-render phase without creating partial SKILL.md
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="unreadable-template"
  chmod 000 "$ROOT_DIR/SKILL.md.jinja"

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

  chmod 644 "$ROOT_DIR/SKILL.md.jinja"

  [[ $status -ne 0 ]] || fail "unreadable template should exit non-zero"
  assert_contains "$output" "[phase:template-render] ERROR: Template file is not readable:" "unreadable template phase error"
  assert_contains "$output" "[phase:template-render] NEXT: Grant read permissions on SKILL.md.jinja and rerun." "unreadable template next action"
  assert_not_contains "$output" '"mcpServers": {' "unreadable template should not emit MCP handoff"
  [[ ! -e "$skill_root/$skill_name/SKILL.md" ]] || fail "unreadable template should not leave destination SKILL.md"
  pass "unreadable template fails cleanly without destination artifact"
}

# 8) unusual server name renders as escaped JSON string without breaking control flow
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="literal-server-name"
  server_name=$'odd"name\\with\ttab'

  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' \
    --server-name "$server_name" 2>&1)"

  ddgs_path="$skill_root/$skill_name/.venv/bin/ddgs"
  escaped_server='"odd\"name\\with\ttab": {'
  assert_contains "$output" "$escaped_server" "unusual server names should be JSON-escaped"
  assert_contains "$output" "\"command\": \"$ddgs_path\"" "escaped server test should still print resolved command path"
  assert_contains "$output" "[phase:install] S04 install complete. Local ddgs environment is ready." "escaped server test should still complete"
  pass "unusual server names are emitted as literal JSON strings"
}

printf '\nAll tests passed (%d checks).\n' "$PASS_COUNT"
