#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$ROOT_DIR/README.md"

PASS_COUNT=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$context (missing: $needle)"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  [[ "$haystack" != *"$needle"* ]] || fail "$context (unexpected: $needle)"
}

assert_heading_exists() {
  local content="$1"
  local heading="$2"
  grep -Fq -- "$heading" <<<"$content" || fail "missing heading: $heading"
}

assert_heading_order() {
  local content="$1"
  local first="$2"
  local second="$3"
  local context="$4"
  local first_line
  local second_line

  first_line=$(grep -nF -- "$first" <<<"$content" | head -n1 | cut -d: -f1)
  second_line=$(grep -nF -- "$second" <<<"$content" | head -n1 | cut -d: -f1)

  [[ -n "$first_line" ]] || fail "$context (missing first heading: $first)"
  [[ -n "$second_line" ]] || fail "$context (missing second heading: $second)"
  (( first_line < second_line )) || fail "$context (expected '$first' before '$second')"
}

[[ -f "$README" ]] || fail "README.md should exist"
content="$(<"$README")"

assert_heading_exists "$content" "## What this installs"
assert_heading_exists "$content" "## Prerequisite"
assert_heading_exists "$content" "## Quick start"
assert_heading_exists "$content" "## What success looks like"
assert_heading_exists "$content" "## MCP handoff"
assert_heading_exists "$content" "## Use the installed skill"

assert_heading_order "$content" "## What this installs" "## Prerequisite" "tutorial flow should explain installed result before prerequisite"
assert_heading_order "$content" "## Prerequisite" "## Quick start" "tutorial flow should place prerequisite before quick start"
assert_heading_order "$content" "## Quick start" "## What success looks like" "tutorial flow should define success after quick start"
assert_heading_order "$content" "## What success looks like" "## MCP handoff" "tutorial flow should show success boundary before handoff details"
assert_heading_order "$content" "## MCP handoff" "## Use the installed skill" "tutorial flow should describe MCP wiring before usage guidance"
pass "README heading flow matches first-run tutorial order"

assert_contains "$content" 'bash install.sh' "README should use installer entry command"
assert_contains "$content" 'uv' "README should name uv prerequisite"
assert_contains "$content" '"mcpServers": {' "README should include MCP handoff snippet"
assert_contains "$content" '[phase:install] S04 install complete. Local ddgs environment is ready.' "README should include final install completion signal"
assert_contains "$content" 'SKILL.md' "README should delegate detailed post-install behavior to generated SKILL.md"
pass "README includes required installer-aligned anchors"

assert_not_contains "$content" 'GSD' "README should avoid planning-jargon terms"
assert_not_contains "$content" 'milestone' "README should avoid planning-jargon terms"
assert_not_contains "$content" 'slice' "README should avoid planning-jargon terms"
pass "README avoids internal planning terminology"

printf '\nAll tests passed (%d checks).\n' "$PASS_COUNT"
