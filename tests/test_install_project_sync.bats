#!/usr/bin/env bats

load test_helper.bash

SOURCE_PYPROJECT="$ROOT_DIR/pyproject.toml"
SOURCE_LOCK="$ROOT_DIR/uv.lock"

setup() {
  setup_test_env
  SOURCE_PYPROJECT_BACKUP=""
  SOURCE_LOCK_BACKUP=""
  SOURCE_LOCK_CREATED_BY_TEST=0
  SOURCE_PYPROJECT_MODE="$(stat -c '%a' "$SOURCE_PYPROJECT" 2>/dev/null || true)"
  SOURCE_LOCK_MODE=""

  if [[ -e "$SOURCE_LOCK" ]]; then
    SOURCE_LOCK_MODE="$(stat -c '%a' "$SOURCE_LOCK" 2>/dev/null || true)"
  fi
}

teardown() {
  restore_source_lock
  restore_source_pyproject
  teardown_test_env
}

backup_source_pyproject() {
  SOURCE_PYPROJECT_BACKUP="$TEST_TMP_ROOT/source-pyproject.backup"
  mv "$SOURCE_PYPROJECT" "$SOURCE_PYPROJECT_BACKUP"
}

restore_source_pyproject() {
  if [[ -n "${SOURCE_PYPROJECT_BACKUP:-}" && -e "$SOURCE_PYPROJECT_BACKUP" ]]; then
    mv "$SOURCE_PYPROJECT_BACKUP" "$SOURCE_PYPROJECT"
  fi

  if [[ -n "${SOURCE_PYPROJECT_MODE:-}" && -e "$SOURCE_PYPROJECT" ]]; then
    chmod "$SOURCE_PYPROJECT_MODE" "$SOURCE_PYPROJECT"
  fi
}

backup_source_lock_if_present() {
  SOURCE_LOCK_BACKUP=""

  if [[ -e "$SOURCE_LOCK" ]]; then
    SOURCE_LOCK_BACKUP="$TEST_TMP_ROOT/source-lock.backup"
    mv "$SOURCE_LOCK" "$SOURCE_LOCK_BACKUP"
  fi
}

restore_source_lock() {
  if [[ -n "${SOURCE_LOCK_BACKUP:-}" && -e "$SOURCE_LOCK_BACKUP" ]]; then
    rm -f "$SOURCE_LOCK"
    mv "$SOURCE_LOCK_BACKUP" "$SOURCE_LOCK"

    if [[ -n "${SOURCE_LOCK_MODE:-}" && -e "$SOURCE_LOCK" ]]; then
      chmod "$SOURCE_LOCK_MODE" "$SOURCE_LOCK"
    fi

    return
  fi

  if [[ "${SOURCE_LOCK_CREATED_BY_TEST:-0}" -eq 1 ]]; then
    rm -f "$SOURCE_LOCK"
  fi
}

write_source_lock_fixture() {
  local content="$1"

  printf '%s' "$content" >"$SOURCE_LOCK"
  SOURCE_LOCK_CREATED_BY_TEST=1
}

@test "metadata-copy runs before sync and preserves canonical ddgs handoff path" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="metadata-before-venv"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    '[[ -f "$INSTALLER_PROJECT_DIR/pyproject.toml" ]] || { echo "pyproject missing before sync" >&2; exit 71; }; : > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi'

  assert_success "project-sync success path should complete"

  target_dir="$skill_root/$skill_name"
  target_pyproject="$target_dir/pyproject.toml"
  target_lock="$target_dir/uv.lock"
  target_python="$target_dir/.venv/bin/python"
  ddgs_path="$target_dir/.venv/bin/ddgs"

  [[ -f "$target_pyproject" ]] || fail_test "metadata-copy should place pyproject.toml in target directory"
  cmp -s "$SOURCE_PYPROJECT" "$target_pyproject" || fail_test "copied target pyproject.toml should match source manifest"
  [[ -f "$target_lock" ]] || fail_test "project-sync should retain target uv.lock"
  [[ -x "$target_python" ]] || fail_test "sync-hook seam should materialize target-local python executable"
  [[ -x "$ddgs_path" ]] || fail_test "sync success should produce executable handoff path"

  assert_output_contains "[phase:metadata-copy] Copying project metadata into $target_dir" "metadata-copy start"
  assert_output_contains "[phase:metadata-copy] Copied required metadata: $target_pyproject" "metadata-copy copied pyproject"
  assert_output_contains "[phase:metadata-copy] Metadata copy complete; environment provisioning may proceed." "metadata-copy completion"
  assert_output_contains "[phase:project-sync] Retained target lockfile: $target_lock" "project-sync retained lockfile"
  assert_output_contains "\"command\": \"$ddgs_path\"" "handoff snippet should keep canonical ddgs path"
  assert_output_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "success should emit completion line"
  assert_occurrence_count "$output" '"mcpServers": {' 1 "success path should emit one MCP handoff snippet"
  assert_line_order "$output" "[phase:metadata-copy] Metadata copy complete; environment provisioning may proceed." "[phase:project-sync] Running uv sync --directory '$target_dir'" "metadata-copy should finish before project-sync"
  assert_line_order "$output" "[phase:project-sync] Project sync complete for $target_dir" "[phase:executable-verification] Verified executable: $ddgs_path" "project-sync should complete before executable verification"
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
