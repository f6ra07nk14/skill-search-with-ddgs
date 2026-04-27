#!/usr/bin/env bats

load test_helper.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
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

@test "unusual server names are JSON-escaped in handoff snippet" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="escaped-server-name"
  server_name=$'odd"name\\with\ttab'

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"' \
    --server-name "$server_name"

  assert_success "install with unusual server name should succeed"

  target_dir="$skill_root/$skill_name"
  ddgs_path="$target_dir/.venv/bin/ddgs"
  skill_doc="$target_dir/SKILL.md"
  render_stage="$target_dir/.template-render-stage"
  escaped_server='"odd\"name\\with\ttab": {'

  [[ -x "$ddgs_path" ]] || fail_test "escaped-server scenario should materialize executable: $ddgs_path"
  [[ -s "$skill_doc" ]] || fail_test "escaped-server scenario should create non-empty SKILL.md: $skill_doc"
  [[ ! -e "$render_stage" ]] || fail_test "escaped-server scenario should remove staging directory: $render_stage"

  assert_output_contains "[phase:template-render] Rendered skill document: $skill_doc" "escaped-server scenario should render before handoff"
  assert_output_contains "[phase:install] Final MCP handoff snippet" "escaped-server scenario should announce the MCP handoff block"
  assert_output_contains "$escaped_server" "handoff snippet should emit JSON-escaped server name"
  assert_output_contains "\"command\": \"$ddgs_path\"" "handoff snippet should keep canonical command path"
  assert_occurrence_count "$output" '"mcpServers": {' 1 "escaped-server scenario should emit exactly one handoff snippet"
  assert_line_order "$output" "[phase:template-render] Rendered skill document: $skill_doc" "[phase:install] Final MCP handoff snippet" "escaped-server scenario should render before emitting MCP handoff"
  assert_line_order "$output" "[phase:install] Final MCP handoff snippet" "[phase:install] S04 install complete. Local ddgs environment is ready." "escaped-server scenario should complete after MCP handoff"
  assert_output_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "escaped-server scenario should complete"
}
