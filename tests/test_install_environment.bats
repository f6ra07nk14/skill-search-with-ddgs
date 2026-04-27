#!/usr/bin/env bats

load test_helper.bash

setup() {
  setup_test_env
  SOURCE_TEMPLATE="$ROOT_DIR/SKILL.md.jinja"
  SOURCE_TEMPLATE_MODE="$(stat -c '%a' "$SOURCE_TEMPLATE" 2>/dev/null || true)"
  SOURCE_TEMPLATE_BACKUP=""
}

teardown() {
  restore_source_template
  teardown_test_env
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

@test "fresh install emits handoff snippet and removes render staging helpers" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="fresh-install-contract"
  server_name="fresh-ddgs-server"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi' \
    --server-name "$server_name"

  assert_success "fresh install should succeed"

  target_dir="$skill_root/$skill_name"
  ddgs_path="$target_dir/.venv/bin/ddgs"
  skill_doc="$target_dir/SKILL.md"
  render_stage="$target_dir/.template-render-stage"

  [[ -x "$ddgs_path" ]] || fail_test "fresh install should materialize executable: $ddgs_path"
  [[ -s "$skill_doc" ]] || fail_test "fresh install should create non-empty SKILL.md: $skill_doc"
  [[ ! -e "$render_stage" ]] || fail_test "successful render should remove staging directory: $render_stage"

  skill_content="$(<"$skill_doc")"
  assert_contains "$skill_content" "$server_name" "rendered file should preserve selected server name"
  assert_contains "$skill_content" "$ddgs_path" "rendered file should preserve canonical executable path"

  assert_output_contains "[phase:template-render] Removed staged render helpers from $render_stage" "fresh install should report staging cleanup"
  assert_output_contains "[phase:template-render] Rendered skill document: $skill_doc" "fresh install should report rendered destination"
  assert_output_contains "[phase:install] Final MCP handoff snippet" "fresh install should announce the MCP handoff block"
  assert_output_contains '"mcpServers": {' "fresh install should emit MCP handoff block"
  assert_output_contains "\"$server_name\": {" "fresh install should emit selected server in handoff block"
  assert_output_contains "\"command\": \"$ddgs_path\"" "fresh install should emit canonical executable command"
  assert_output_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "fresh install should emit completion line"
  assert_occurrence_count "$output" '"mcpServers": {' 1 "fresh install should emit exactly one handoff snippet"
  assert_line_order "$output" "[phase:template-render] Rendered skill document: $skill_doc" "[phase:install] Final MCP handoff snippet" "fresh install should render before emitting MCP handoff"
  assert_line_order "$output" "[phase:install] Final MCP handoff snippet" "[phase:install] S04 install complete. Local ddgs environment is ready." "fresh install should emit completion after MCP handoff"
}

@test "missing ddgs executable fails verification and suppresses handoff" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="missing-ddgs"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"'

  assert_failure "missing ddgs should fail"
  assert_output_contains "[phase:executable-verification] ERROR: Missing ddgs executable after install:" "missing ddgs should fail executable verification"
  assert_output_not_contains '[phase:template-render]' "missing ddgs should stop before template render"
  assert_output_not_contains '"mcpServers": {' "missing ddgs should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "missing ddgs should suppress completion line"
}

@test "non-executable ddgs path fails verification and suppresses handoff" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="non-executable-ddgs"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod 0644 "$INSTALLER_DDGS_PATH"'

  assert_failure "non-executable ddgs should fail"
  assert_output_contains "[phase:executable-verification] ERROR: ddgs path is not executable:" "non-executable path should fail executable verification"
  assert_output_not_contains '[phase:template-render]' "non-executable ddgs should stop before template render"
  assert_output_not_contains '"mcpServers": {' "non-executable ddgs should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "non-executable ddgs should suppress completion line"
}

@test "missing template fails in template-render phase without partial SKILL.md" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="missing-template"

  backup_source_template

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"'

  assert_failure "missing template should fail"
  assert_output_contains "[phase:template-render] ERROR: Template not found:" "missing template should produce template-render error"
  assert_output_not_contains '"mcpServers": {' "missing template should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "missing template should suppress completion line"

  [[ ! -e "$skill_root/$skill_name/SKILL.md" ]] || fail_test "missing template should not create destination SKILL.md"
}

@test "unreadable template fails in template-render phase without partial SKILL.md" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="unreadable-template"

  chmod 000 "$SOURCE_TEMPLATE"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"'

  assert_failure "unreadable template should fail"
  assert_output_contains "[phase:template-render] ERROR: Template file is not readable:" "unreadable template should produce template-render error"
  assert_output_not_contains '"mcpServers": {' "unreadable template should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "unreadable template should suppress completion line"

  [[ ! -e "$skill_root/$skill_name/SKILL.md" ]] || fail_test "unreadable template should not create destination SKILL.md"
}

@test "render helper runtime failure preserves staged diagnostics and suppresses completion" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="runtime-render-failure"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_DDGS_PATH" && chmod +x "$INSTALLER_DDGS_PATH" && rm -f "$INSTALLER_VENV_PATH/bin/python" && printf "#!/usr/bin/env bash\necho \"fixture render runtime failure\" >&2\nexit 97\n" > "$INSTALLER_VENV_PATH/bin/python" && chmod +x "$INSTALLER_VENV_PATH/bin/python"'

  assert_failure "render helper runtime failure should fail"

  render_stage="$skill_root/$skill_name/.template-render-stage"
  staged_renderer="$render_stage/render_skill.py"
  staged_template="$render_stage/SKILL.md.jinja"

  assert_output_contains "[phase:template-render] Rendering SKILL.md via target-local interpreter:" "runtime failure should reach render execution phase"
  assert_output_contains "[phase:template-render] ERROR: fixture render runtime failure" "runtime failure should surface helper stderr"
  assert_output_contains "[phase:template-render] ERROR: Target-local render helper failed with exit code 97." "runtime failure should report render exit code"
  assert_output_not_contains '"mcpServers": {' "runtime failure should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "runtime failure should suppress completion line"

  [[ ! -e "$skill_root/$skill_name/SKILL.md" ]] || fail_test "runtime failure should not leave final SKILL.md"
  [[ -d "$render_stage" ]] || fail_test "runtime failure should retain render staging directory for diagnostics"
  [[ -f "$staged_renderer" ]] || fail_test "runtime failure should retain staged render helper"
  [[ -f "$staged_template" ]] || fail_test "runtime failure should retain staged template"
}

@test "unusual server names are JSON-escaped in handoff snippet" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="escaped-server-name"
  server_name=$'odd"name\\with\ttab'

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"' \
    --server-name "$server_name"

  assert_success "install with unusual server name should succeed"

  ddgs_path="$skill_root/$skill_name/.venv/bin/ddgs"
  skill_doc="$skill_root/$skill_name/SKILL.md"
  skill_content="$(<"$skill_doc")"
  escaped_server='"odd\"name\\with\ttab": {'

  assert_output_contains "[phase:template-render] Rendered skill document: $skill_doc" "escaped-server scenario should render before handoff"
  assert_output_contains "[phase:install] Final MCP handoff snippet" "escaped-server scenario should announce the MCP handoff block"
  assert_output_contains "$escaped_server" "handoff snippet should emit JSON-escaped server name"
  assert_output_contains "\"command\": \"$ddgs_path\"" "handoff snippet should keep canonical command path"
  assert_occurrence_count "$output" '"mcpServers": {' 1 "escaped-server scenario should emit exactly one handoff snippet"
  assert_line_order "$output" "[phase:template-render] Rendered skill document: $skill_doc" "[phase:install] Final MCP handoff snippet" "escaped-server scenario should render before emitting MCP handoff"
  assert_line_order "$output" "[phase:install] Final MCP handoff snippet" "[phase:install] S04 install complete. Local ddgs environment is ready." "escaped-server scenario should complete after MCP handoff"
  assert_output_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "escaped-server scenario should complete"

  assert_contains "$skill_content" "$server_name" "rendered output should preserve literal server name"
  assert_contains "$skill_content" "$ddgs_path" "rendered output should preserve canonical ddgs path"
}
