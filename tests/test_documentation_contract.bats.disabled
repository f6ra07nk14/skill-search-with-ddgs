#!/usr/bin/env bats

load test_helper.bash

@test "README describes the shipped writing-skills-first contract" {
  readme="$(<"$ROOT_DIR/README.md")"

  assert_contains "$readme" "trigger-only" "README should describe the trigger-only skill description"
  assert_contains "$readme" '`Overview`, `When to Use`, one `Workflow`, and `Common Mistakes`' "README should describe the shipped section shape"
  assert_contains "$readme" '"mcpServers": {' "README should preserve the canonical mcpServers handoff"
  assert_contains "$readme" ".venv/bin/ddgs" "README should mention the installed executable path"
  assert_contains "$readme" "runtime tool inspection or current docs" "README should defer heavy DDGS reference content to runtime inspection/current docs"

  assert_not_contains "$readme" "Required Sequence" "README should not reintroduce the legacy Required Sequence section"
  assert_not_contains "$readme" "## References" "README should not reintroduce the legacy References section"
  assert_not_contains "$readme" "<table>" "README should not reintroduce HTML table dumps"
  assert_not_contains "$readme" "workflow summary" "README should not describe the skill description as a workflow summary"
  assert_not_contains "$readme" "global Python" "README should not drift back to global-runtime framing"
}

@test "install help repeats the single-file skill contract" {
  run bash "$ROOT_DIR/install.sh" --help

  assert_success "install help should exit successfully"
  assert_output_contains "frontmatter description stays trigger-only." "help should describe the trigger-only description"
  assert_output_contains "Overview, When to Use, one Workflow, and Common Mistakes." "help should describe the shipped section shape"
  assert_output_contains "mcpServers" "help should preserve the canonical handoff wording"
  assert_output_contains ".venv/bin/ddgs" "help should mention the installed executable path"
  assert_output_contains "runtime tool inspection or current docs" "help should defer heavy DDGS details to runtime inspection/current docs"

  assert_output_not_contains "Required Sequence" "help should not reintroduce the legacy Required Sequence section"
  assert_output_not_contains "References" "help should not reintroduce the legacy References section"
  assert_output_not_contains "<table>" "help should not reintroduce HTML table dumps"
  assert_output_not_contains "workflow summary" "help should not describe the skill description as a workflow summary"
  assert_output_not_contains "global Python" "help should not drift back to global-runtime framing"
  assert_occurrence_count "$output" "Workflow" 1 "help should describe exactly one Workflow"
}
