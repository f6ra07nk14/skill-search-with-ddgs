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

# 1) defaults resolve in non-interactive mode
{
  fakebin="$(make_fake_uv_bin)"
  output="$(run_installer "$fakebin" --non-interactive 2>&1)"
  assert_contains "$output" "[phase:config] Non-interactive resolution: using flags and defaults only." "defaults: mode message"
  assert_contains "$output" "skill_root='~/.agents/skills'" "defaults: skill root"
  assert_contains "$output" "skill_name='search-with-ddgs'" "defaults: skill name"
  assert_contains "$output" "server_name='ddgs'" "defaults: server name"
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

# 6) empty / whitespace prompt answers fall back to defaults
{
  fakebin="$(make_fake_uv_bin)"
  output="$(printf '   \n  custom-name  \n   \n' | env -i \
    HOME="/tmp/test-home" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_FORCE_INTERACTIVE=1 \
    bash "$INSTALLER" 2>&1)"
  assert_contains "$output" "skill_root='~/.agents/skills'" "prompt whitespace: root default"
  assert_contains "$output" "skill_name='custom-name'" "prompt whitespace: trimmed custom name"
  assert_contains "$output" "server_name='ddgs'" "prompt whitespace: server default"
  pass "whitespace prompt values handled"
}

# 7) non-interactive mode suppresses prompting
{
  fakebin="$(make_fake_uv_bin)"
  output="$(run_installer "$fakebin" --non-interactive 2>&1)"
  assert_not_contains "$output" "Skill root [" "non-interactive should not prompt"
  pass "non-interactive mode suppresses prompts"
}

# 8) preflight does not mutate the target skill filesystem
{
  fakebin="$(make_fake_uv_bin)"
  tmp_root="$(mktemp -d)"
  target_root="$tmp_root/skills-root"

  output="$(run_installer "$fakebin" --non-interactive --skill-root "$target_root" --skill-name "candidate" 2>&1)"
  assert_contains "$output" "[phase:preflight] Preflight checks passed." "preflight no-mutation: succeeds"

  [[ ! -e "$target_root" ]] || fail "preflight should not create target root"
  [[ ! -e "$target_root/candidate" ]] || fail "preflight should not create skill directory"
  pass "preflight is side-effect free"
}

printf '\nAll tests passed (%d checks).\n' "$PASS_COUNT"
