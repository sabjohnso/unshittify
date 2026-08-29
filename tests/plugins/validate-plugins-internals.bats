#!/usr/bin/env bats
# Unit tests against the internal functions of validate-plugins.sh, sourcing
# it directly (its BASH_SOURCE guard means sourcing does not run main).
#
# These are possible because the check functions only PRINT violations - the
# violation count lives in main, not in a global the checks mutate. Testing a
# check in isolation was impossible while `report` incremented shared state.

load helpers

setup() {
  # shellcheck source=/dev/null
  source "$VALIDATOR"
  FIXTURE="$(mktemp "${BATS_TMPDIR:-/tmp}/fixture.XXXXXX.md")"
}

# write_frontmatter <frontmatter-body>  - writes FIXTURE and loads it
write_frontmatter() {
  printf -- '---\n%s\n---\n\n# Title\n\nBody.\n' "$1" > "$FIXTURE"
  load_frontmatter "$(frontmatter_of "$FIXTURE")"
}

@test "sourcing the script does not execute main" {
  [ "$(type -t main)" = "function" ]
}

# --- frontmatter parsing ----------------------------------------------------

@test "load_frontmatter records each key's value and line number" {
  write_frontmatter 'description: A thing.
argument-hint: "[hint]"
allowed-tools: Read, Grep'
  [ "$(frontmatter_value description)" = "A thing." ]
  [ "$(frontmatter_value argument-hint)" = "[hint]" ]
  [ "$(frontmatter_line description)" -eq 2 ]
  [ "$(frontmatter_line allowed-tools)" -eq 4 ]
}

@test "an absent key yields an empty value and an empty line" {
  write_frontmatter 'description: A thing.'
  [ -z "$(frontmatter_value model)" ]
  [ -z "$(frontmatter_line model)" ]
}

@test "load_frontmatter strips the surrounding quotes from a value" {
  write_frontmatter 'description: "A quoted thing with a (#:keyword) in it."'
  [ "$(frontmatter_value description)" = "A quoted thing with a (#:keyword) in it." ]
}

@test "a file with no frontmatter yields no keys" {
  printf '# Just a heading\n\nBody.\n' > "$FIXTURE"
  [ -z "$(frontmatter_of "$FIXTURE")" ]
}

# --- unquote ----------------------------------------------------------------

@test "unquote removes matching double or single quotes and leaves bare text" {
  [ "$(unquote '"quoted"')" = "quoted" ]
  [ "$(unquote "'quoted'")" = "quoted" ]
  [ "$(unquote 'bare')" = "bare" ]
  [ "$(unquote '')" = "" ]
}

@test "unquote leaves an inner quote alone" {
  [ "$(unquote '"say \"hi\""')" = 'say \"hi\"' ]
}

# --- check_yaml_truncation --------------------------------------------------

@test "check_yaml_truncation reports an unquoted value cut by a comment" {
  write_frontmatter 'description: Options (#:transparent, #:mutable). Use when defining.'
  run check_yaml_truncation "$FIXTURE" "$(frontmatter_of "$FIXTURE")"
  [ -n "$output" ]
  [[ "$output" == *":2: "* ]]
}

@test "check_yaml_truncation stays silent on the quoted form" {
  write_frontmatter 'description: "Options (#:transparent, #:mutable). Use when defining."'
  run check_yaml_truncation "$FIXTURE" "$(frontmatter_of "$FIXTURE")"
  [ -z "$output" ]
}

@test "check_yaml_truncation stays silent when no space precedes the hash" {
  write_frontmatter 'description: Build a reader (#:dispatch). Use when extending.'
  run check_yaml_truncation "$FIXTURE" "$(frontmatter_of "$FIXTURE")"
  [ -z "$output" ]
}

@test "check_yaml_truncation reports every affected key, not just the first" {
  write_frontmatter 'description: One (#:a, #:b).
argument-hint: Two (#:c, #:d).'
  run check_yaml_truncation "$FIXTURE" "$(frontmatter_of "$FIXTURE")"
  [ "$(printf '%s\n' "$output" | grep -c "$(basename "$FIXTURE")")" -eq 2 ]
}

# --- check_tool_names -------------------------------------------------------

@test "check_tool_names accepts every known tool, bare or argument-scoped" {
  run check_tool_names "$FIXTURE" 3 'Read, Grep, Glob, Bash(git status:*), Agent(communication:prose-reviewer)'
  [ -z "$output" ]
}

@test "check_tool_names reports the last tool in a list" {
  # The token loop once dropped the final entry, because `read` returns
  # nonzero on a line with no trailing newline - and a stale tool name sits
  # at the end of a list as often as anywhere else.
  run check_tool_names "$FIXTURE" 3 'Read, Grep, Nonexistent'
  [[ "$output" == *"Nonexistent"* ]]
}

@test "check_tool_names reports each unknown tool once" {
  run check_tool_names "$FIXTURE" 3 'Taks, Read, Wrtie'
  [ "$(printf '%s\n' "$output" | grep -c 'unknown tool')" -eq 2 ]
}

# --- report -----------------------------------------------------------------

@test "report prints one jumpable path:line: line and nothing else" {
  run report /some/file.md 42 'the message'
  [ "$output" = "/some/file.md:42: the message" ]
}

@test "report keeps no count of its own" {
  # The checks are pure output; main counts. Two reports print two lines and
  # leave no shared state behind for a later check to inherit.
  run bash -c "source '$VALIDATOR'; report a.md 1 one; report b.md 2 two"
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
}
