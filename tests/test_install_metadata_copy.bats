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

@test "present source uv.lock is copied into target metadata" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="with-source-lock"

  backup_source_lock_if_present
  write_source_lock_fixture $'version = 1\nrevision = "fixture-lock"\n'

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi'

  assert_success "present source uv.lock should complete"

  target_lock="$skill_root/$skill_name/uv.lock"
  [[ -f "$target_lock" ]] || fail_test "installer should copy source uv.lock when present"
  target_lock_content="$(<"$target_lock")"
  assert_contains "$target_lock_content" "fixture-lock" "copied target uv.lock should preserve source contents"
  assert_output_contains "[phase:metadata-copy] Copied optional lockfile: $target_lock" "metadata-copy should report copied optional lockfile"
}

@test "missing source pyproject.toml fails in metadata-copy before project-sync" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="missing-pyproject"

  backup_source_pyproject

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi'

  assert_failure "missing pyproject.toml should fail install"
  assert_output_contains "[phase:metadata-copy] ERROR: Required metadata file is missing: $SOURCE_PYPROJECT" "missing pyproject should fail metadata-copy"
  assert_output_not_contains "[phase:project-sync]" "missing pyproject should stop before project-sync"
  assert_output_not_contains "[phase:template-render]" "missing pyproject should stop before template-render"
  assert_output_not_contains '"mcpServers": {' "missing pyproject should stop before MCP handoff"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "missing pyproject should suppress completion line"
}

@test "unreadable source pyproject.toml fails in metadata-copy before provisioning" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="unreadable-pyproject"

  chmod 000 "$SOURCE_PYPROJECT"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi'

  assert_failure "unreadable pyproject.toml should fail install"
  assert_output_contains "[phase:metadata-copy] ERROR: Required metadata file is not readable: $SOURCE_PYPROJECT" "unreadable pyproject should fail metadata-copy"
  assert_output_not_contains "[phase:project-sync]" "unreadable pyproject should stop before project-sync"
  assert_output_not_contains '"mcpServers": {' "unreadable pyproject should stop before MCP handoff"
}

@test "unreadable source uv.lock fails in metadata-copy before project-sync" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="unreadable-lock"

  backup_source_lock_if_present
  write_source_lock_fixture $'version = 1\nrevision = "unreadable"\n'
  chmod 000 "$SOURCE_LOCK"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi'

  assert_failure "unreadable source uv.lock should fail install"
  assert_output_contains "[phase:metadata-copy] ERROR: Optional lockfile is not readable: $SOURCE_LOCK" "unreadable source lockfile should fail metadata-copy"
  assert_output_not_contains "[phase:project-sync]" "unreadable source lockfile should stop before project-sync"
  assert_output_not_contains '"mcpServers": {' "unreadable source lockfile should stop before MCP handoff"
}

@test "unusual but valid target paths with spaces still receive copied metadata" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills root with spaces"
  skill_name='skill name with spaces'

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi'

  assert_success "valid paths with spaces should complete"

  target_pyproject="$skill_root/$skill_name/pyproject.toml"
  [[ -f "$target_pyproject" ]] || fail_test "metadata-copy should handle unusual valid target paths"
  assert_output_contains "[phase:metadata-copy] Copied required metadata: $target_pyproject" "metadata-copy log should quote unusual target path correctly"
}
