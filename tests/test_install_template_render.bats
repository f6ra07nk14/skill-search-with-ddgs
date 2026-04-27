#!/usr/bin/env bats

load test_helper.bash

setup() {
  setup_test_env
  init_source_template_fixture
}

teardown() {
  restore_source_template
  teardown_test_env
}

@test "missing template fails in template-render phase without partial SKILL.md" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="missing-template"

  backup_source_template

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"'

  assert_failure "missing template should fail"

  target_dir="$skill_root/$skill_name"
  ddgs_path="$target_dir/.venv/bin/ddgs"
  render_stage="$target_dir/.template-render-stage"
  skill_doc="$target_dir/SKILL.md"

  assert_output_contains "[phase:executable-verification] Verified executable: $ddgs_path" "missing template should reach executable verification before render"
  assert_output_contains "[phase:template-render] ERROR: Template not found: $SOURCE_TEMPLATE" "missing template should produce template-render error"
  assert_output_not_contains "[phase:template-render] Rendered skill document: $skill_doc" "missing template should not report a rendered skill document"
  assert_output_not_contains '[phase:install] Final MCP handoff snippet' "missing template should suppress handoff announcement"
  assert_output_not_contains '"mcpServers": {' "missing template should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "missing template should suppress completion line"

  [[ ! -e "$skill_doc" ]] || fail_test "missing template should not create destination SKILL.md"
  [[ ! -e "$render_stage" ]] || fail_test "missing template should not leave a render staging directory"
}

@test "unreadable template fails in template-render phase without partial SKILL.md" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="unreadable-template"

  chmod 000 "$SOURCE_TEMPLATE"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    ': > "$INSTALLER_DDGS_PATH"; chmod +x "$INSTALLER_DDGS_PATH"'

  assert_failure "unreadable template should fail"

  target_dir="$skill_root/$skill_name"
  ddgs_path="$target_dir/.venv/bin/ddgs"
  render_stage="$target_dir/.template-render-stage"
  skill_doc="$target_dir/SKILL.md"

  assert_output_contains "[phase:executable-verification] Verified executable: $ddgs_path" "unreadable template should reach executable verification before render"
  assert_output_contains "[phase:template-render] ERROR: Template file is not readable: $SOURCE_TEMPLATE" "unreadable template should produce template-render error"
  assert_output_not_contains "[phase:template-render] Rendered skill document: $skill_doc" "unreadable template should not report a rendered skill document"
  assert_output_not_contains '[phase:install] Final MCP handoff snippet' "unreadable template should suppress handoff announcement"
  assert_output_not_contains '"mcpServers": {' "unreadable template should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "unreadable template should suppress completion line"

  [[ ! -e "$skill_doc" ]] || fail_test "unreadable template should not create destination SKILL.md"
  [[ ! -e "$render_stage" ]] || fail_test "unreadable template should not leave a render staging directory"
}

@test "render helper runtime failure preserves staged diagnostics and suppresses completion" {
  fakebin="$(make_fake_uv_bin)"
  skill_root="$(make_temp_dir)/skills-root"
  skill_name="runtime-render-failure"

  run run_installer_with_sync_hook "$fakebin" "$TEST_HOME" "$skill_root" "$skill_name" \
    'mkdir -p "$INSTALLER_VENV_PATH/bin" && : > "$INSTALLER_DDGS_PATH" && chmod +x "$INSTALLER_DDGS_PATH" && rm -f "$INSTALLER_VENV_PATH/bin/python" && printf "#!/usr/bin/env bash\necho \"fixture render runtime failure\" >&2\nexit 97\n" > "$INSTALLER_VENV_PATH/bin/python" && chmod +x "$INSTALLER_VENV_PATH/bin/python"'

  assert_failure "render helper runtime failure should fail"

  target_dir="$skill_root/$skill_name"
  ddgs_path="$target_dir/.venv/bin/ddgs"
  render_stage="$target_dir/.template-render-stage"
  skill_doc="$target_dir/SKILL.md"
  staged_renderer="$render_stage/render_skill.py"
  staged_template="$render_stage/SKILL.md.jinja"

  assert_output_contains "[phase:executable-verification] Verified executable: $ddgs_path" "runtime render failure should begin after executable verification"
  assert_output_contains "[phase:template-render] Rendering SKILL.md via target-local interpreter:" "runtime render failure should reach render execution"
  assert_output_contains "[phase:template-render] ERROR: fixture render runtime failure" "runtime render failure should surface helper stderr"
  assert_output_contains "[phase:template-render] ERROR: Target-local render helper failed with exit code 97." "runtime render failure should report render exit code"
  assert_line_order "$output" "[phase:executable-verification] Verified executable: $ddgs_path" "[phase:template-render] Rendering SKILL.md via target-local interpreter:" "runtime render should start only after executable verification"
  assert_output_not_contains "[phase:template-render] Rendered skill document: $skill_doc" "runtime render failure should not report a rendered skill document"
  assert_output_not_contains '[phase:install] Final MCP handoff snippet' "runtime render failure should suppress handoff announcement"
  assert_output_not_contains '"mcpServers": {' "runtime render failure should suppress handoff snippet"
  assert_output_not_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "runtime render failure should suppress completion line"

  [[ ! -e "$skill_doc" ]] || fail_test "runtime render failure should not leave final SKILL.md"
  [[ -d "$render_stage" ]] || fail_test "runtime render failure should retain render staging directory for diagnostics"
  [[ -f "$staged_renderer" ]] || fail_test "runtime render failure should retain staged render helper"
  [[ -f "$staged_template" ]] || fail_test "runtime render failure should retain staged template"
}
