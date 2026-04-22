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

run_installer() {
  local fakebin="$1"
  shift

  env -i \
    HOME="/tmp/test-home" \
    PATH="$fakebin:/usr/bin:/bin" \
    bash "$INSTALLER" "$@"
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

make_empty_bin() {
  mktemp -d
}

assert_no_mutation() {
  local root="$1"
  local skill_name="$2"
  [[ ! -e "$root" ]] || fail "preflight should not create skill root: $root"
  [[ ! -e "$root/$skill_name" ]] || fail "preflight should not create skill directory: $root/$skill_name"
  [[ ! -e "$root/$skill_name/.venv" ]] || fail "preflight should not create venv path"
  [[ ! -e "$root/$skill_name/.mcp.json" ]] || fail "preflight should not create MCP config"
}

# 1) defaults resolve in non-interactive mode + fake PATH uv succeeds
{
  fakebin="$(make_fake_uv_bin)"
  output="$(run_installer "$fakebin" --non-interactive 2>&1)"
  assert_contains "$output" "[phase:config] Non-interactive resolution: using flags and defaults only." "defaults: mode message"
  assert_contains "$output" "skill_root='~/.agents/skills'" "defaults: skill root"
  assert_contains "$output" "skill_name='search-with-ddgs'" "defaults: skill name"
  assert_contains "$output" "server_name='ddgs'" "defaults: server name"
  assert_contains "$output" "[phase:uv] Detected uv in PATH." "defaults: uv detected"
  assert_contains "$output" "[phase:preflight] Preflight checks passed." "defaults: success"
  pass "defaults resolve in non-interactive mode"
}

# 2) explicit flags override defaults and trim whitespace
{
  fakebin="$(make_fake_uv_bin)"
  output="$(run_installer "$fakebin" \
    --non-interactive \
    --skill-root "  /tmp/custom-root  " \
    --skill-name "  custom-skill  " \
    --server-name "  custom-server  " 2>&1)"
  assert_contains "$output" "skill_root='/tmp/custom-root'" "flags: skill root"
  assert_contains "$output" "skill_name='custom-skill'" "flags: skill name"
  assert_contains "$output" "server_name='custom-server'" "flags: server name"
  pass "explicit flags override defaults"
}

# 3) interactive prompt accepts bare Enter defaults
{
  fakebin="$(make_fake_uv_bin)"
  output="$(printf '\n\n\n' | env -i \
    HOME="/tmp/test-home" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_FORCE_INTERACTIVE=1 \
    bash "$INSTALLER" 2>&1)"
  assert_contains "$output" "[phase:config] Interactive mode: collecting installer settings." "prompt: interactive mode"
  assert_contains "$output" "skill_root='~/.agents/skills'" "prompt: default root"
  assert_contains "$output" "skill_name='search-with-ddgs'" "prompt: default name"
  assert_contains "$output" "server_name='ddgs'" "prompt: default server"
  pass "interactive prompt accepts enter defaults"
}

# 4) unknown flag fails with targeted message
{
  fakebin="$(make_fake_uv_bin)"
  set +e
  output="$(run_installer "$fakebin" --bogus 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "unknown flag should exit non-zero"
  assert_contains "$output" "Unknown option: --bogus" "unknown flag: error text"
  assert_contains "$output" "Run 'install.sh --help' for supported options." "unknown flag: next action"
  pass "unknown flag rejected"
}

# 5) missing option value fails clearly
{
  fakebin="$(make_fake_uv_bin)"
  set +e
  output="$(run_installer "$fakebin" --skill-root 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "missing value should exit non-zero"
  assert_contains "$output" "Missing value for --skill-root." "missing value: targeted error"
  pass "missing option value rejected"
}

# 6) unsupported platform blocks preflight before mutation
{
  fakebin="$(make_fake_uv_bin)"
  tmp_root="$(mktemp -d)"
  target_root="$tmp_root/skills-root"

  set +e
  output="$(env -i \
    HOME="/tmp/test-home" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_UNAME_CMD="printf 'Solaris'" \
    bash "$INSTALLER" --non-interactive --skill-root "$target_root" --skill-name "candidate" 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "unsupported platform should exit non-zero"
  assert_contains "$output" "[phase:platform] ERROR: Unsupported platform: solaris." "unsupported platform message"
  assert_no_mutation "$target_root" "candidate"
  pass "unsupported platform is rejected before mutation"
}

# 7) empty platform probe is treated as preflight failure
{
  fakebin="$(make_fake_uv_bin)"

  set +e
  output="$(env -i \
    HOME="/tmp/test-home" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_UNAME_CMD="printf ''" \
    bash "$INSTALLER" --non-interactive 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "empty platform probe should exit non-zero"
  assert_contains "$output" "Could not determine platform from uname probe." "empty platform probe message"
  pass "empty platform probe fails preflight"
}

# 8) non-interactive mode suppresses prompting
{
  fakebin="$(make_fake_uv_bin)"
  output="$(run_installer "$fakebin" --non-interactive 2>&1)"
  assert_not_contains "$output" "Skill root [" "non-interactive should not prompt"
  pass "non-interactive mode suppresses prompts"
}

# 9) missing uv prints official guidance and declined install fails with no mutation
{
  emptybin="$(make_empty_bin)"
  tmp_root="$(mktemp -d)"
  target_root="$tmp_root/skills-root"

  set +e
  output="$(printf '\n\n\nn\n' | env -i \
    HOME="/tmp/test-home" \
    PATH="$emptybin:/usr/bin:/bin" \
    INSTALLER_FORCE_INTERACTIVE=1 \
    bash "$INSTALLER" --skill-root "$target_root" --skill-name "candidate" 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "declined guided install should exit non-zero"
  assert_contains "$output" "[phase:uv] INSTALL:   curl -LsSf https://astral.sh/uv/install.sh | sh" "uv guidance curl"
  assert_contains "$output" "[phase:uv] INSTALL:   wget -qO- https://astral.sh/uv/install.sh | sh" "uv guidance wget"
  assert_contains "$output" "[phase:uv] ERROR: uv installation declined." "uv decline message"
  assert_no_mutation "$target_root" "candidate"
  pass "missing uv guidance + decline path is explicit and side-effect free"
}

# 10) guided installer failure reports exit code and no mutation
{
  emptybin="$(make_empty_bin)"
  tmp_root="$(mktemp -d)"
  target_root="$tmp_root/skills-root"

  set +e
  output="$(printf '\n\n\ny\n' | env -i \
    HOME="/tmp/test-home" \
    PATH="$emptybin:/usr/bin:/bin" \
    INSTALLER_FORCE_INTERACTIVE=1 \
    INSTALLER_UV_INSTALL_CMD='(exit 17)' \
    bash "$INSTALLER" --skill-root "$target_root" --skill-name "candidate" 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "guided installer failure should exit non-zero"
  assert_contains "$output" "Guided uv installer failed with exit code 17." "guided installer failure message"
  assert_no_mutation "$target_root" "candidate"
  pass "guided installer failure is surfaced with exit code"
}

# 11) post-install re-check failure remains fatal
{
  emptybin="$(make_empty_bin)"
  tmp_root="$(mktemp -d)"
  target_root="$tmp_root/skills-root"

  set +e
  output="$(printf '\n\n\ny\n' | env -i \
    HOME="/tmp/test-home" \
    PATH="$emptybin:/usr/bin:/bin" \
    INSTALLER_FORCE_INTERACTIVE=1 \
    INSTALLER_UV_INSTALL_CMD='true' \
    bash "$INSTALLER" --skill-root "$target_root" --skill-name "candidate" 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "failed uv re-check should exit non-zero"
  assert_contains "$output" "uv still unavailable after guided install attempt." "post-install re-check message"
  assert_no_mutation "$target_root" "candidate"
  pass "post-install re-check failure remains fatal"
}

# 12) malformed uv probe output is treated as unavailable
{
  fakebin="$(make_fake_uv_bin)"
  set +e
  output="$(env -i \
    HOME="/tmp/test-home" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_UV_PATH_CMD="printf '/tmp/uv\n/extra'" \
    INSTALLER_FORCE_INTERACTIVE=1 \
    bash "$INSTALLER" --non-interactive 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "malformed uv probe output should exit non-zero"
  assert_contains "$output" "uv not found in PATH." "malformed uv output treated as unavailable"
  pass "malformed uv probe output does not bypass preflight"
}

printf '\nAll tests passed (%d checks).\n' "$PASS_COUNT"
