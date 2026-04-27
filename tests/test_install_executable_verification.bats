#!/usr/bin/env bats

load test_helper.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "missing ddgs executable fails verification and suppresses handoff" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="missing-ddgs"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"'

  assert_failure "missing ddgs should fail"

  target_dir="$skill_root/$skill_name"
  expected_ddgs="$target_dir/.venv/bin/ddgs"

  assert_output_contains "[phase:project-sync] Project sync complete for $target_dir" "missing ddgs should fail after project-sync completes"
  assert_output_contains "[phase:executable-verification] Checking executable at $expected_ddgs" "missing ddgs should check the canonical executable path"
  assert_output_contains "[phase:executable-verification] ERROR: Missing ddgs executable after install: $expected_ddgs" "missing ddgs should fail executable verification"
  assert_line_order "$output" "[phase:project-sync] Project sync complete for $target_dir" "[phase:executable-verification] Checking executable at $expected_ddgs" "missing ddgs should fail only after project-sync completes"
  assert_output_not_contains '[phase:template-render]' "missing ddgs should stop before template render"
  assert_output_not_contains '[phase:install] Final MCP handoff snippet' "missing ddgs should suppress handoff announcement"
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

  target_dir="$skill_root/$skill_name"
  expected_ddgs="$target_dir/.venv/bin/ddgs"

  assert_output_contains "[phase:project-sync] Project sync complete for $target_dir" "non-executable ddgs should fail after project-sync completes"
  assert_output_contains "[phase:executable-verification] Checking executable at $expected_ddgs" "non-executable ddgs should check the canonical executable path"
  assert_output_contains "[phase:executable-verification] ERROR: ddgs path is not executable: $expected_ddgs" "non-executable path should fail executable verification"
  assert_line_order "$output" "[phase:project-sync] Project sync complete for $target_dir" "[phase:executable-verification] Checking executable at $expected_ddgs" "non-executable ddgs should fail only after project-sync completes"
  assert_output_not_contains '[phase:template-render]' "non-executable ddgs should stop before template render"
  assert_output_not_contains '[phase:install] Final MCP handoff snippet' "non-executable ddgs should suppress handoff announcement"
  assert_output_not_contains '"mcpServers": {' "non-executable ddgs should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "non-executable ddgs should suppress completion line"
}

@test "malformed sync layout fails canonical executable verification and suppresses handoff" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="malformed-sync-layout"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    'mkdir -p "$INSTALLER_PROJECT_DIR/bin"; : > "$INSTALLER_PROJECT_DIR/bin/ddgs"; chmod +x "$INSTALLER_PROJECT_DIR/bin/ddgs"; : > "$INSTALLER_PROJECT_DIR/uv.lock"'

  assert_failure "malformed sync layout should exit non-zero"

  target_dir="$skill_root/$skill_name"
  expected_ddgs="$target_dir/.venv/bin/ddgs"
  misplaced_ddgs="$target_dir/bin/ddgs"

  [[ -x "$misplaced_ddgs" ]] || fail_test "fixture should create misplaced executable for canonical-path check"
  assert_output_contains "[phase:project-sync] Project sync complete for $target_dir" "malformed layout should still complete project-sync"
  assert_output_contains "[phase:executable-verification] Checking executable at $expected_ddgs" "malformed layout should verify the canonical executable path"
  assert_output_contains "[phase:executable-verification] ERROR: Missing ddgs executable after install: $expected_ddgs" "malformed layout should fail executable verification on canonical path"
  assert_line_order "$output" "[phase:project-sync] Project sync complete for $target_dir" "[phase:executable-verification] Checking executable at $expected_ddgs" "malformed layout should fail after project-sync completes"
  assert_output_not_contains '[phase:template-render]' "malformed layout should stop before template render"
  assert_output_not_contains '[phase:install] Final MCP handoff snippet' "malformed layout should suppress handoff announcement"
  assert_output_not_contains '"mcpServers": {' "malformed layout should suppress MCP handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "malformed layout should suppress completion line"
}
