#!/usr/bin/env bats

load test_helper.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "defaults resolve in non-interactive mode and complete deterministic install" {
  fakebin="$(make_fake_uv_bin)"

  run run_installer "$fakebin" "$TEST_HOME" --non-interactive

  assert_success "defaults should complete successfully"
  assert_output_contains "[phase:config] Non-interactive resolution: using flags and defaults only." "defaults: mode message"
  assert_output_contains "skill_root='~/.agents/skills'" "defaults: skill root"
  assert_output_contains "skill_name='search-with-ddgs'" "defaults: skill name"
  assert_output_contains "server_name='ddgs'" "defaults: server name"
  assert_output_contains "[phase:uv] Detected uv in PATH." "defaults: uv detected"
  assert_output_contains "[phase:install] S04 install complete. Local ddgs environment is ready." "defaults: install success"
}

@test "explicit flags override defaults and trim whitespace" {
  fakebin="$(make_fake_uv_bin)"
  custom_root="$(make_temp_dir)/custom-root"

  run run_installer "$fakebin" "$TEST_HOME" \
    --non-interactive \
    --skill-root "  $custom_root  " \
    --skill-name "  custom-skill  " \
    --server-name "  custom-server  "

  assert_success "explicit flags should complete successfully"
  assert_output_contains "skill_root='$custom_root'" "flags: skill root"
  assert_output_contains "skill_name='custom-skill'" "flags: skill name"
  assert_output_contains "server_name='custom-server'" "flags: server name"
}

@test "interactive prompt accepts bare Enter defaults" {
  fakebin="$(make_fake_uv_bin)"

  run run_installer_force_interactive $'\n\n\n' "$fakebin" "$TEST_HOME"

  assert_success "interactive defaults should complete successfully"
  assert_output_contains "[phase:config] Interactive mode: collecting installer settings." "prompt: interactive mode"
  assert_output_contains "skill_root='~/.agents/skills'" "prompt: default root"
  assert_output_contains "skill_name='search-with-ddgs'" "prompt: default name"
  assert_output_contains "server_name='ddgs'" "prompt: default server"
}

@test "unknown flag fails with targeted message" {
  fakebin="$(make_fake_uv_bin)"

  run run_installer "$fakebin" "$TEST_HOME" --bogus

  assert_failure "unknown flag should fail"
  assert_output_contains "Unknown option: --bogus" "unknown flag: error text"
  assert_output_contains "Run 'install.sh --help' for supported options." "unknown flag: next action"
}

@test "missing option value fails clearly" {
  fakebin="$(make_fake_uv_bin)"

  run run_installer "$fakebin" "$TEST_HOME" --skill-root

  assert_failure "missing value should fail"
  assert_output_contains "Missing value for --skill-root." "missing value: targeted error"
}

@test "unsupported platform blocks before mutation" {
  fakebin="$(make_fake_uv_bin)"
  target_root="$(make_temp_dir)/skills-root"

  run run_installer_env "$fakebin" "$TEST_HOME" \
    "INSTALLER_UNAME_CMD=printf 'Solaris'" \
    -- \
    --non-interactive \
    --skill-root "$target_root" \
    --skill-name "candidate"

  assert_failure "unsupported platform should fail"
  assert_output_contains "[phase:platform] ERROR: Unsupported platform: solaris." "unsupported platform message"
  assert_no_mutation "$target_root" "candidate"
  assert_preflight_abort "$output" "unsupported platform"
}

@test "empty platform probe is treated as preflight failure" {
  fakebin="$(make_fake_uv_bin)"

  run run_installer_env "$fakebin" "$TEST_HOME" \
    "INSTALLER_UNAME_CMD=printf ''" \
    -- \
    --non-interactive

  assert_failure "empty platform probe should fail"
  assert_output_contains "Could not determine platform from uname probe." "empty platform probe message"
  assert_preflight_abort "$output" "empty platform probe"
}

@test "non-interactive mode suppresses prompting" {
  fakebin="$(make_fake_uv_bin)"

  run run_installer "$fakebin" "$TEST_HOME" --non-interactive

  assert_success "non-interactive defaults should complete successfully"
  assert_output_not_contains "Skill root [" "non-interactive should not prompt"
}

@test "missing uv prints guidance and declined install fails with no mutation" {
  emptybin="$(make_empty_bin)"
  target_root="$(make_temp_dir)/skills-root"

  run run_installer_raw_force_interactive $'\n\n\nn\n' "$emptybin" "$TEST_HOME" \
    --skill-root "$target_root" \
    --skill-name "candidate"

  assert_failure "declined guided install should fail"
  assert_output_contains "[phase:uv] INSTALL:   curl -LsSf https://astral.sh/uv/install.sh | sh" "uv guidance curl"
  assert_output_contains "[phase:uv] INSTALL:   wget -qO- https://astral.sh/uv/install.sh | sh" "uv guidance wget"
  assert_output_contains "[phase:uv] ERROR: uv installation declined." "uv decline message"
  assert_no_mutation "$target_root" "candidate"
  assert_preflight_abort "$output" "guided uv decline"
}

@test "malformed uv probe output is treated as unavailable" {
  fakebin="$(make_fake_uv_bin)"

  run run_installer_env "$fakebin" "$TEST_HOME" \
    "INSTALLER_UV_PATH_CMD=printf '/tmp/uv\\n/extra'" \
    "INSTALLER_FORCE_INTERACTIVE=1" \
    -- \
    --non-interactive

  assert_failure "malformed uv probe output should fail"
  assert_output_contains "uv not found in PATH." "malformed uv output treated as unavailable"
  assert_output_not_contains "Skill root [" "malformed uv probe should remain prompt-free in non-interactive mode"
  assert_preflight_abort "$output" "malformed uv probe"
}

@test "missing uv in non-interactive mode fails fast without prompt or snippet output" {
  emptybin="$(make_empty_bin)"

  run run_installer_raw_env "$emptybin" "$TEST_HOME" -- --non-interactive

  assert_failure "missing uv non-interactive mode should fail"
  assert_output_contains "[phase:uv] ERROR: uv not found in PATH." "missing uv non-interactive phase error"
  assert_output_contains "[phase:uv] NEXT: Install uv manually, then rerun with --non-interactive." "missing uv non-interactive next action"
  assert_output_not_contains "Run guided uv installer now?" "missing uv non-interactive should not prompt for guided install"
  assert_output_not_contains "Skill root [" "missing uv non-interactive should not prompt for config"
  assert_preflight_abort "$output" "missing uv non-interactive"
  assert_occurrence_count "$output" '"mcpServers": {' 0 "missing uv non-interactive should emit zero handoff snippets"
}
