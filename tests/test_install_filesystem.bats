#!/usr/bin/env bats

load test_helper.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "existing target directory conflict fails before mutation and suppresses handoff" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="conflict-skill"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi'

  assert_success "seed install for conflict test should succeed"

  marker="$skill_root/$skill_name/marker.txt"
  printf 'keep' >"$marker"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"; if [[ ! -f "$INSTALLER_PROJECT_DIR/uv.lock" ]]; then : > "$INSTALLER_PROJECT_DIR/uv.lock"; fi'

  assert_failure "conflict run should fail"
  assert_output_contains "[phase:filesystem] ERROR: Target skill directory already exists:" "conflict should be reported in filesystem phase"
  assert_output_not_contains '"mcpServers": {' "conflict should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "conflict should suppress completion line"

  marker_content="$(<"$marker")"
  [[ "$marker_content" == "keep" ]] || fail_test "conflict path should not overwrite existing files"
}
