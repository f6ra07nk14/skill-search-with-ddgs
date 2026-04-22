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

  env -i \
    HOME="$home_dir" \
    PATH="$fakebin:/usr/bin:/bin" \
    INSTALLER_UV_VENV_CMD="$venv_hook" \
    INSTALLER_UV_PIP_INSTALL_CMD="$pip_hook" \
    bash "$INSTALLER" --non-interactive --skill-root "$skill_root" --skill-name "$skill_name"
}

# 1) fresh install creates <root>/<skill_name>/.venv/bin/ddgs and logs package/executable phases
{
  fakebin="$(make_fake_uv_bin)"
  home_dir="$(mktemp -d)"
  skill_root="$(mktemp -d)/skills-root"
  skill_name="fresh-skill"

  output="$(run_installer_with_hooks \
    "$fakebin" \
    "$home_dir" \
    "$skill_root" \
    "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"' \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_VENV_PATH/bin/ddgs" && chmod +x "$INSTALLER_VENV_PATH/bin/ddgs"' 2>&1)"

  ddgs_path="$skill_root/$skill_name/.venv/bin/ddgs"
  [[ -x "$ddgs_path" ]] || fail "fresh install should create executable: $ddgs_path"
  assert_contains "$output" "[phase:package-install] Installing ddgs[api,mcp]" "fresh install package phase"
  assert_contains "$output" "[phase:executable-verification] Verified executable:" "fresh install executable verification"
  assert_contains "$output" "[phase:install] S02 install complete. Local ddgs environment is ready." "fresh install completion"
  pass "fresh install creates local ddgs executable"
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
  pass "non-executable ddgs path is rejected"
}

printf '\nAll tests passed (%d checks).\n' "$PASS_COUNT"
