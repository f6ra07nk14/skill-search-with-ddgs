#!/usr/bin/env bats

load test_helper.bash

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

render_template_fixture() {
  local skill_name="$1"
  local server_name="$2"
  local ddgs_path="$3"
  local destination="$TEST_TMP_ROOT/rendered-skill/SKILL.md"

  mkdir -p "$(dirname "$destination")"

  uv run python "$ROOT_DIR/render_skill.py" \
    --template "$ROOT_DIR/SKILL.md.jinja" \
    --destination "$destination" \
    --skill-name "$skill_name" \
    --server-name "$server_name" \
    --ddgs-executable-path "$ddgs_path"
}

list_template_placeholders() {
  grep -o '{{[A-Z_][A-Z_]*}}' "$ROOT_DIR/SKILL.md.jinja" | sort -u
}

@test "rendered skill keeps the writing-skills-first shape and placeholder contract" {
  ddgs_path="$TEST_TMP_ROOT/runtime/ddgs"
  mkdir -p "$(dirname "$ddgs_path")"
  : >"$ddgs_path"
  chmod +x "$ddgs_path"

  run render_template_fixture "rewrite-check" "rewrite-ddgs" "$ddgs_path"

  assert_success "render helper should succeed for representative values"

  rendered_path="$TEST_TMP_ROOT/rendered-skill/SKILL.md"
  [[ -f "$rendered_path" ]] || fail_test "render helper should create the rendered destination file"
  assert_output_contains "$rendered_path" "render helper should print the rendered destination path"

  rendered="$(<"$rendered_path")"

  assert_contains "$rendered" "name: rewrite-check" "rendered file should preserve the selected skill name"
  assert_contains "$rendered" $'description: Use when a task needs current information from the web, recent news, or content from a known external URL that is not available in the local codebase or model memory.' "rendered description should stay trigger-only"
  assert_contains "$rendered" "## Overview" "rendered file should include Overview"
  assert_contains "$rendered" "## When to Use" "rendered file should include When to Use"
  assert_contains "$rendered" "## Workflow" "rendered file should include Workflow"
  assert_contains "$rendered" "## Common Mistakes" "rendered file should include Common Mistakes"
  assert_occurrence_count "$rendered" "## Overview" 1 "rendered file should keep exactly one Overview section"
  assert_occurrence_count "$rendered" "## When to Use" 1 "rendered file should keep exactly one When to Use section"
  assert_occurrence_count "$rendered" "## Workflow" 1 "rendered file should keep exactly one Workflow section"
  assert_occurrence_count "$rendered" "## Common Mistakes" 1 "rendered file should keep exactly one Common Mistakes section"
  assert_line_order "$rendered" "## Overview" "## When to Use" "rendered file should keep Overview before When to Use"
  assert_line_order "$rendered" "## When to Use" "## Workflow" "rendered file should keep When to Use before Workflow"
  assert_line_order "$rendered" "## Workflow" "## Common Mistakes" "rendered file should keep Workflow before Common Mistakes"
  assert_contains "$rendered" '`rewrite-ddgs`' "rendered file should preserve the selected server name in the workflow"
  assert_contains "$rendered" "$ddgs_path" "rendered file should preserve the resolved executable path"
  assert_contains "$rendered" "same URL with the runtime page reader before broader fallback" "rendered file should keep same-URL fallback guidance"
  assert_contains "$rendered" "rewrite the query once" "rendered file should keep weak-result rewrite guidance"
  assert_contains "$rendered" "state the queries used" "rendered file should keep query-reporting guidance"
  assert_contains "$rendered" "fallback tooling was required" "rendered file should keep fallback disclosure guidance"
  assert_not_contains "$rendered" "## Required Sequence" "rendered file should drop Required Sequence"
  assert_not_contains "$rendered" "## References" "rendered file should drop References"
  assert_not_contains "$rendered" "<table>" "rendered file should drop HTML table dumps"
  assert_not_contains "$rendered" "{{SKILL_NAME}}" "rendered file should not retain the skill placeholder"
  assert_not_contains "$rendered" "{{SERVER_NAME}}" "rendered file should not retain the server placeholder"
  assert_not_contains "$rendered" "{{DDGS_EXECUTABLE_PATH}}" "rendered file should not retain the executable placeholder"
}

@test "template source keeps only the supported section set and runtime placeholders" {
  template_content="$(<"$ROOT_DIR/SKILL.md.jinja")"

  assert_contains "$template_content" "## Overview" "template should include Overview"
  assert_contains "$template_content" "## When to Use" "template should include When to Use"
  assert_contains "$template_content" "## Workflow" "template should include Workflow"
  assert_contains "$template_content" "## Common Mistakes" "template should include Common Mistakes"
  assert_occurrence_count "$template_content" "## Overview" 1 "template should keep exactly one Overview section"
  assert_occurrence_count "$template_content" "## When to Use" 1 "template should keep exactly one When to Use section"
  assert_occurrence_count "$template_content" "## Workflow" 1 "template should keep exactly one Workflow section"
  assert_occurrence_count "$template_content" "## Common Mistakes" 1 "template should keep exactly one Common Mistakes section"
  assert_line_order "$template_content" "## Overview" "## When to Use" "template should keep Overview before When to Use"
  assert_line_order "$template_content" "## When to Use" "## Workflow" "template should keep When to Use before Workflow"
  assert_line_order "$template_content" "## Workflow" "## Common Mistakes" "template should keep Workflow before Common Mistakes"
  assert_not_contains "$template_content" "## Required Sequence" "template should drop Required Sequence"
  assert_not_contains "$template_content" "## References" "template should drop References"
  assert_not_contains "$template_content" "<table>" "template should drop HTML tables"

  run list_template_placeholders

  assert_success "placeholder discovery should succeed"
  assert_occurrence_count "$output" "{{" 3 "template should keep exactly three runtime placeholders"
  assert_output_contains "{{SKILL_NAME}}" "template should preserve the skill-name placeholder"
  assert_output_contains "{{SERVER_NAME}}" "template should preserve the server-name placeholder"
  assert_output_contains "{{DDGS_EXECUTABLE_PATH}}" "template should preserve the executable-path placeholder"
}
