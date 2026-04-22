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

  actual_count=$( (grep -Fo -- "$needle" <<<"$haystack" | wc -l | tr -d ' ') || true )
  [[ "$actual_count" == "$expected_count" ]] || fail "$context (expected $expected_count, got $actual_count for: $needle)"
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
  skill_content="$(<"$skill_doc")"

  assert_file_contains "$skill_doc" "$server_name" "rendered SKILL.md should include selected server name"
  assert_file_contains "$skill_doc" "$ddgs_path" "rendered SKILL.md should include concrete ddgs executable path"
  assert_occurrence_count "$skill_content" "---" 2 "rendered SKILL.md should include opening and closing YAML frontmatter boundaries"
  assert_contains "$skill_content" "name: $skill_name" "rendered SKILL.md should include frontmatter name"
  assert_contains "$skill_content" "description: Use this skill when a task requires current information" "rendered SKILL.md should include trigger-oriented frontmatter description"
  assert_contains "$skill_content" "prefer $server_name before fallback search tools." "rendered SKILL.md description should include resolved server fallback guidance"
  assert_contains "$skill_content" "# $skill_name" "rendered SKILL.md should include markdown title"
  assert_contains "$skill_content" "## When to Use" "rendered SKILL.md should include When to Use heading"
  assert_contains "$skill_content" "## Required Sequence" "rendered SKILL.md should include Required Sequence heading"
  assert_contains "$skill_content" "## Installed Executable" "rendered SKILL.md should include Installed Executable heading"
  assert_contains "$skill_content" "## Response Requirements" "rendered SKILL.md should include Response Requirements heading"
  assert_contains "$skill_content" "## Forbidden" "rendered SKILL.md should include Forbidden heading"
  assert_contains "$skill_content" "## Workflow" "rendered SKILL.md should preserve Workflow anchor"
  assert_contains "$skill_content" "## References" "rendered SKILL.md should preserve References anchor"
  assert_contains "$skill_content" "1. **Availability check first**" "rendered SKILL.md should include MCP-first workflow step"
  assert_contains "$skill_content" 'Run `mcp_servers`.' "rendered SKILL.md should require mcp_servers as first workflow action"
  fallback_unavailable_marker="If \`$server_name\` is missing, skip to Step 6 (fallback disclosure path)."
  assert_contains "$skill_content" "$fallback_unavailable_marker" "rendered SKILL.md should document unavailable-server fallback path"
  assert_contains "$skill_content" "5. **Rewrite once, then decide**" "rendered SKILL.md should include one-rewrite DDGS decision gate"
  assert_contains "$skill_content" "6. **Known URL and same-URL read path**" "rendered SKILL.md should include known URL handling step"
  assert_contains "$skill_content" 'If task starts with a known URL, begin with `extract_content`.' "rendered SKILL.md should include known URL extract_content rule"
  assert_contains "$skill_content" 'If `extract_content` fails on that URL, call `fetch_page` on the **same URL** before trying broader search fallback.' "rendered SKILL.md should include same-URL fetch_page fallback rule"
  assert_contains "$skill_content" "7. **Fallback disclosure is mandatory**" "rendered SKILL.md should include explicit fallback disclosure step"
  assert_contains "$skill_content" 'Any time you use `google_search` or `search-the-web` because DDGS was unavailable or weak after one rewrite, state this explicitly in the response and explain why.' "rendered SKILL.md should require explicit fallback disclosure"
  assert_contains "$skill_content" "### DDGS tools quick table" "rendered SKILL.md should include DDGS quick table heading"
  assert_contains "$skill_content" "### Shared search parameters and defaults" "rendered SKILL.md should include shared parameter reference heading"
  assert_contains "$skill_content" '### `extract_content` output format reference' "rendered SKILL.md should include extract_content format reference heading"
  assert_contains "$skill_content" "### Backend support matrix" "rendered SKILL.md should include backend support matrix heading"
  assert_contains "$skill_content" "#### Backend options by DDGS search tool" "rendered SKILL.md should include backend-options table heading"
  assert_contains "$skill_content" "#### Non-backend controls by tool" "rendered SKILL.md should include non-backend controls table heading"
  assert_contains "$skill_content" "### Operational tips" "rendered SKILL.md should include operational tips heading"
  assert_contains "$skill_content" "<table>" "rendered SKILL.md should include embedded quick reference tables"
  assert_contains "$skill_content" "<th>Tool</th><th>Use when</th><th>Required args</th><th>Key optional args</th><th>Returns</th>" "rendered SKILL.md should include DDGS tools quick table columns"
  assert_contains "$skill_content" "<th>Parameter</th><th>Applies to</th><th>Default</th><th>Notes</th>" "rendered SKILL.md should include shared parameters table columns"
  assert_contains "$skill_content" "<th><code>fmt</code> value</th><th>Meaning</th><th>Best use</th>" "rendered SKILL.md should include extract_content format table columns"
  assert_contains "$skill_content" "<th>Tool</th><th><code>backend</code> supported</th><th>Default</th>" "rendered SKILL.md should include backend options table columns"
  assert_contains "$skill_content" "<th>Tool</th><th><code>timelimit</code></th><th><code>region</code></th><th><code>safesearch</code></th><th><code>page</code></th><th><code>max_results</code></th>" "rendered SKILL.md should include non-backend controls table columns"
  assert_line_order "$skill_content" "## When to Use" "## Required Sequence" "rendered SKILL.md should keep expected heading order (When to Use -> Required Sequence)"
  assert_line_order "$skill_content" "## Required Sequence" "## Installed Executable" "rendered SKILL.md should keep expected heading order (Required Sequence -> Installed Executable)"
  assert_line_order "$skill_content" "## Installed Executable" "## Response Requirements" "rendered SKILL.md should keep expected heading order (Installed Executable -> Response Requirements)"
  assert_line_order "$skill_content" "## Response Requirements" "## Forbidden" "rendered SKILL.md should keep expected heading order (Response Requirements -> Forbidden)"
  assert_line_order "$skill_content" "## Forbidden" "## Workflow" "rendered SKILL.md should keep expected heading order (Forbidden -> Workflow)"
  assert_line_order "$skill_content" "## Workflow" "## References" "rendered SKILL.md should keep expected heading order (Workflow -> References)"
  assert_line_order "$skill_content" "1. **Availability check first**" "7. **Fallback disclosure is mandatory**" "rendered SKILL.md workflow should preserve MCP-first to fallback-disclosure sequence"
  assert_line_order "$skill_content" "### MCP server config snippet" "### DDGS tools quick table" "rendered SKILL.md references should order config snippet before quick table"
  assert_line_order "$skill_content" "### DDGS tools quick table" "### Shared search parameters and defaults" "rendered SKILL.md references should order quick table before shared parameters"
  assert_line_order "$skill_content" "### Shared search parameters and defaults" '### `extract_content` output format reference' "rendered SKILL.md references should order shared parameters before extract_content formats"
  assert_line_order "$skill_content" '### `extract_content` output format reference' "### Backend support matrix" "rendered SKILL.md references should order extract_content formats before backend matrix"
  assert_line_order "$skill_content" "### Backend support matrix" "### Operational tips" "rendered SKILL.md references should order backend matrix before operational tips"
  assert_not_contains "$skill_content" "<objective>" "rendered SKILL.md should not include legacy wrapper tags"
  assert_not_contains "$skill_content" "<when_to_use>" "rendered SKILL.md should not include legacy wrapper tags"
  assert_not_contains "$skill_content" "<required_sequence>" "rendered SKILL.md should not include legacy wrapper tags"
  assert_not_contains "$skill_content" "<tool_selection>" "rendered SKILL.md should not include legacy wrapper tags"
  assert_not_contains "$skill_content" "<response_requirements>" "rendered SKILL.md should not include legacy wrapper tags"
  assert_not_contains "$skill_content" "<forbidden>" "rendered SKILL.md should not include legacy wrapper tags"
  assert_not_contains "$skill_content" "{{SKILL_NAME}}" "rendered SKILL.md should not retain SKILL_NAME placeholder"
  assert_not_contains "$skill_content" "{{SERVER_NAME}}" "rendered SKILL.md should not retain SERVER_NAME placeholder"
  assert_not_contains "$skill_content" "{{DDGS_EXECUTABLE_PATH}}" "rendered SKILL.md should not retain executable-path placeholder"
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
  assert_not_contains "$output" "Skill root [" "fresh install should remain prompt-free in non-interactive mode"
  assert_line_order "$output" "[phase:executable-verification] Verified executable:" "[phase:template-render] Rendered skill document:" "fresh install should verify executable before template rendering"
  assert_line_order "$output" "[phase:template-render] Rendered skill document:" "[phase:install] Final MCP handoff snippet (copy under mcpServers in your MCP config):" "fresh install should emit snippet after template render"
  assert_line_order "$output" '"mcpServers": {' "[phase:install] S04 install complete. Local ddgs environment is ready." "fresh install should print snippet before completion log"
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
  assert_not_contains "$output" "Skill root [" "conflict failure should remain prompt-free in non-interactive mode"
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
  assert_not_contains "$output" "Skill root [" "package failure should remain prompt-free in non-interactive mode"
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
  assert_not_contains "$output" "Skill root [" "missing ddgs failure should remain prompt-free in non-interactive mode"
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
  assert_not_contains "$output" "Skill root [" "non-executable ddgs failure should remain prompt-free in non-interactive mode"
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
  assert_not_contains "$output" "Skill root [" "missing template failure should remain prompt-free in non-interactive mode"
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
  assert_not_contains "$output" "Skill root [" "unreadable template failure should remain prompt-free in non-interactive mode"
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
  skill_doc="$skill_root/$skill_name/SKILL.md"
  skill_content="$(<"$skill_doc")"
  escaped_server='"odd\"name\\with\ttab": {'
  assert_contains "$output" "$escaped_server" "unusual server names should be JSON-escaped"
  assert_contains "$output" "\"command\": \"$ddgs_path\"" "escaped server test should still print resolved command path"
  assert_occurrence_count "$output" '"mcpServers": {' 1 "escaped server run should emit exactly one handoff snippet"
  assert_file_contains "$skill_doc" "$server_name" "rendered SKILL.md should retain literal selected server name even when escaped in JSON output"
  assert_file_contains "$skill_doc" "$ddgs_path" "rendered SKILL.md should retain resolved ddgs path for unusual server names"
  assert_contains "$skill_content" "## Workflow" "rendered SKILL.md should still include workflow section for unusual server names"
  assert_contains "$skill_content" "### DDGS tools quick table" "rendered SKILL.md should still include quick reference heading for unusual server names"
  assert_not_contains "$output" "Skill root [" "escaped server run should remain prompt-free in non-interactive mode"
  assert_contains "$output" "[phase:install] S04 install complete. Local ddgs environment is ready." "escaped server test should still complete"
  pass "unusual server names are emitted as literal JSON strings"
}

printf '\nAll tests passed (%d checks).\n' "$PASS_COUNT"
