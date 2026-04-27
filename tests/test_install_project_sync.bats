#!/usr/bin/env bats

load test_helper.bash

setup() {
  setup_test_env
  init_source_metadata_fixtures
}

teardown() {
  restore_source_metadata_fixtures
  teardown_test_env
}

@test "metadata-copy runs before sync and preserves canonical ddgs handoff path" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="metadata-before-venv"
  server_name="ordered-sync-server"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    '[[ -f "$INSTALLER_PROJECT_DIR/pyproject.toml" ]] || { echo "pyproject missing before sync" >&2; exit 71; }; : > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi' \
    --server-name "$server_name"

  assert_success "project-sync success path should complete"

  target_dir="$skill_root/$skill_name"
  target_pyproject="$target_dir/pyproject.toml"
  target_lock="$target_dir/uv.lock"
  ddgs_path="$target_dir/.venv/bin/ddgs"
  target_skill_doc="$target_dir/SKILL.md"

  [[ -f "$target_pyproject" ]] || fail_test "metadata-copy should place pyproject.toml in target directory"
  cmp -s "$SOURCE_PYPROJECT" "$target_pyproject" || fail_test "copied target pyproject.toml should match source manifest"
  [[ -f "$target_lock" ]] || fail_test "project-sync should retain target uv.lock"
  [[ -x "$ddgs_path" ]] || fail_test "sync success should produce executable handoff path"
  [[ -s "$target_skill_doc" ]] || fail_test "sync success should render a non-empty target-local SKILL.md"

  skill_content="$(<"$target_skill_doc")"
  assert_contains "$skill_content" "$server_name" "rendered skill should preserve selected server name"
  assert_contains "$skill_content" "$ddgs_path" "rendered skill should preserve the canonical ddgs path"

  assert_output_contains "[phase:metadata-copy] Copying project metadata into $target_dir" "metadata-copy start"
  assert_output_contains "[phase:metadata-copy] Copied required metadata: $target_pyproject" "metadata-copy copied pyproject"
  assert_output_contains "[phase:metadata-copy] Metadata copy complete; environment provisioning may proceed." "metadata-copy completion"
  assert_output_contains "[phase:project-sync] Retained target lockfile: $target_lock" "project-sync retained lockfile"
  assert_output_contains "[phase:template-render] Rendered skill document: $target_skill_doc" "template-render should report the rendered skill document"
  assert_output_contains "[phase:install] Final MCP handoff snippet" "install should announce the final handoff block"
  assert_output_contains "\"$server_name\": {" "handoff snippet should keep selected server name"
  assert_output_contains "\"command\": \"$ddgs_path\"" "handoff snippet should keep canonical ddgs path"
  assert_output_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "success should emit completion line"
  assert_occurrence_count "$output" '"mcpServers": {' 1 "success path should emit one MCP handoff snippet"
  assert_line_order "$output" "[phase:metadata-copy] Metadata copy complete; environment provisioning may proceed." "[phase:project-sync] Running uv sync --directory '$target_dir'" "metadata-copy should finish before project-sync"
  assert_line_order "$output" "[phase:project-sync] Project sync complete for $target_dir" "[phase:executable-verification] Verified executable: $ddgs_path" "project-sync should complete before executable verification"
  assert_line_order "$output" "[phase:executable-verification] Verified executable: $ddgs_path" "[phase:template-render] Rendering SKILL.md via target-local interpreter:" "template render should begin after executable verification"
  assert_line_order "$output" "[phase:template-render] Rendered skill document: $target_skill_doc" "[phase:install] Final MCP handoff snippet" "handoff snippet should follow successful target-local render"
  assert_line_order "$output" "[phase:install] Final MCP handoff snippet" "[phase:install] S04 install complete. Local ddgs environment is ready." "completion should follow MCP handoff"
}

@test "absent source uv.lock is logged and target uv.lock is retained after sync" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="no-source-lock"

  backup_source_lock_if_present

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi'

  assert_success "missing source uv.lock should still complete"

  target_lock="$skill_root/$skill_name/uv.lock"
  [[ -f "$target_lock" ]] || fail_test "installer should retain target uv.lock after sync when source lockfile is absent"
  assert_output_contains "[phase:metadata-copy] Optional lockfile not found at $SOURCE_LOCK; skipping lockfile copy." "missing source lockfile should be logged"
  assert_output_contains "[phase:project-sync] Retained target lockfile: $target_lock" "generated target lockfile should be reported"
}

@test "project-sync non-zero exits with phase diagnostics and no completion output" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="project-sync-failure"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin"; exit 23'

  assert_failure "project-sync failure should exit non-zero"
  assert_output_contains "[phase:project-sync] ERROR: uv sync failed" "project-sync failure should report phase-prefixed error"
  assert_output_contains "exit code 23" "project-sync failure should surface exit code"
  assert_output_not_contains '[phase:template-render]' "project-sync failure should stop before template render"
  assert_output_not_contains '"mcpServers": {' "project-sync failure should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "project-sync failure should suppress completion line"

  [[ -d "$skill_root/$skill_name" ]] || fail_test "failed sync should leave target directory for diagnostics"
}

@test "project-sync failure keeps copied metadata but suppresses handoff and completion output" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="sync-failure-suppresses-handoff"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    '[[ -f "$INSTALLER_PROJECT_DIR/pyproject.toml" ]] || { echo "pyproject missing before forced sync failure" >&2; exit 91; }; : > "$INSTALLER_PROJECT_DIR/uv.lock"; exit 73'

  assert_failure "forced sync failure should exit non-zero"

  target_dir="$skill_root/$skill_name"
  target_pyproject="$target_dir/pyproject.toml"
  target_lock="$target_dir/uv.lock"

  [[ -f "$target_pyproject" ]] || fail_test "sync failure should retain copied target pyproject.toml for diagnostics"
  [[ -f "$target_lock" ]] || fail_test "sync failure should retain target uv.lock when hook produced one"
  assert_output_contains "[phase:metadata-copy] Metadata copy complete; environment provisioning may proceed." "sync failure should still complete metadata-copy"
  assert_output_contains "[phase:project-sync] ERROR: uv sync failed for '$target_dir' with exit code 73." "sync failure should report project-sync error with exit code"
  assert_output_not_contains "[phase:executable-verification]" "sync failure should stop before executable verification"
  assert_output_not_contains "[phase:template-render]" "sync failure should stop before template rendering"
  assert_output_not_contains '"mcpServers": {' "sync failure should suppress MCP handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "sync failure should suppress completion line"
}

@test "malformed sync layout fails canonical executable verification and suppresses handoff" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="malformed-sync-layout"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    'mkdir -p "$INSTALLER_PROJECT_DIR/bin"; : > "$INSTALLER_PROJECT_DIR/bin/ddgs"; chmod +x "$INSTALLER_PROJECT_DIR/bin/ddgs"; : > "$INSTALLER_PROJECT_DIR/uv.lock"'

  assert_failure "malformed sync layout should exit non-zero"

  expected_ddgs="$skill_root/$skill_name/.venv/bin/ddgs"
  misplaced_ddgs="$skill_root/$skill_name/bin/ddgs"

  [[ -x "$misplaced_ddgs" ]] || fail_test "fixture should create misplaced executable for canonical-path check"
  assert_output_contains "[phase:executable-verification] ERROR: Missing ddgs executable after install: $expected_ddgs" "malformed layout should fail executable verification on canonical path"
  assert_output_not_contains '"mcpServers": {' "malformed layout should suppress MCP handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "malformed layout should suppress completion line"
}
