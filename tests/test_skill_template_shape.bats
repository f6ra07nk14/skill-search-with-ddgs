#!/usr/bin/env bats

load test_helper.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

run_render_helper() {
  local template_path="$1"
  local destination="$2"
  local skill_name="$3"
  local server_name="$4"
  local ddgs_path="$5"

  mkdir -p "$(dirname "$destination")"

  uv run python "$ROOT_DIR/render_skill.py" \
    --template "$template_path" \
    --destination "$destination" \
    --skill-name "$skill_name" \
    --server-name "$server_name" \
    --ddgs-executable-path "$ddgs_path"
}

render_template_fixture() {
  local skill_name="$1"
  local server_name="$2"
  local ddgs_path="$3"
  local destination="${4:-$TEST_TMP_ROOT/rendered-skill/SKILL.md}"

  run_render_helper "$ROOT_DIR/SKILL.md.jinja" "$destination" "$skill_name" "$server_name" "$ddgs_path"
}

list_template_placeholders() {
  grep -o '{{[A-Z_][A-Z_]*}}' "$ROOT_DIR/SKILL.md.jinja" | sort -u
}

@test "render helper publishes the requested destination with substituted runtime values" {
  local skill_name="rewrite-check"
  local server_name=$'odd"name\\with\ttab'
  local ddgs_path="$TEST_TMP_ROOT/runtime/bin with spaces/ddgs --odd"

  mkdir -p "$(dirname "$ddgs_path")"
  : >"$ddgs_path"
  chmod +x "$ddgs_path"

  run render_template_fixture "$skill_name" "$server_name" "$ddgs_path"

  assert_success "render helper should succeed for representative values"

  local rendered_path="$TEST_TMP_ROOT/rendered-skill/SKILL.md"
  [[ -f "$rendered_path" ]] || fail_test "render helper should create the requested destination file"
  assert_output_contains "$rendered_path" "render helper should print the rendered destination path"

  local rendered
  rendered="$(<"$rendered_path")"

  assert_contains "$rendered" "name: $skill_name" "rendered file should preserve the selected skill name"
  assert_contains "$rendered" "$server_name" "rendered file should preserve the selected server name literally"
  assert_contains "$rendered" "$ddgs_path" "rendered file should preserve the selected executable path literally"
  assert_not_contains "$rendered" "{{SKILL_NAME}}" "rendered file should not retain the skill placeholder"
  assert_not_contains "$rendered" "{{SERVER_NAME}}" "rendered file should not retain the server placeholder"
  assert_not_contains "$rendered" "{{DDGS_EXECUTABLE_PATH}}" "rendered file should not retain the executable placeholder"
}

@test "render helper failures leave an existing destination untouched" {
  local template_dir
  template_dir="$(make_temp_dir)"

  local bad_template="$template_dir/bad-SKILL.md.jinja"
  local destination="$TEST_TMP_ROOT/rendered-skill/SKILL.md"
  local original_content='original skill content stays put'
  local ddgs_path="$TEST_TMP_ROOT/runtime/ddgs"

  printf '%s\n' \
    '---' \
    'name: {{SKILL_NAME}}' \
    '---' \
    '{{MISSING_RENDER_VALUE}}' >"$bad_template"

  mkdir -p "$(dirname "$ddgs_path")"
  mkdir -p "$(dirname "$destination")"
  : >"$ddgs_path"
  chmod +x "$ddgs_path"
  printf '%s' "$original_content" >"$destination"

  run run_render_helper "$bad_template" "$destination" "atomic-check" "failure-server" "$ddgs_path"

  assert_failure "render helper should fail for an invalid template"
  assert_output_contains "Failed to render template with Jinja2:" "render failure should surface the Jinja error"
  assert_output_not_contains "$destination" "failed renders should not report successful publication"

  local rendered
  rendered="$(<"$destination")"
  [[ "$rendered" == "$original_content" ]] || fail_test "failed renders should leave an existing destination file untouched"
}

@test "template source exposes only the supported runtime placeholders" {
  local expected_placeholders=$'{{DDGS_EXECUTABLE_PATH}}\n{{SERVER_NAME}}\n{{SKILL_NAME}}'

  run list_template_placeholders

  assert_success "placeholder discovery should succeed"
  [[ "$output" == "$expected_placeholders" ]] || fail_test "template should keep exactly the supported runtime placeholders"
}
