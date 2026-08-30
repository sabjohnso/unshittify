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
  FIXTURE="$(mktemp "$(fixture_dir)/fixture.XXXXXX.md")"
}

teardown() {
  cleanup_fixtures
}

# write_frontmatter <frontmatter-body>  - writes FIXTURE and parses it
write_frontmatter() {
  printf -- '---\n%s\n---\n\n# Title\n\nBody.\n' "$1" > "$FIXTURE"
  read_markdown "$FIXTURE"
}

@test "sourcing the script does not execute main" {
  [ "$(type -t main)" = "function" ]
}

# --- frontmatter parsing ----------------------------------------------------

@test "read_markdown records each key's value and line number" {
  write_frontmatter 'description: A thing.
argument-hint: "[hint]"
allowed-tools: Read, Grep'
  [ "$(unquote "${FM_RAW[description]}")" = "A thing." ]
  [ "$(unquote "${FM_RAW[argument-hint]}")" = "[hint]" ]
  [ "${FM_LINE[description]}" -eq 2 ]
  [ "${FM_LINE[allowed-tools]}" -eq 4 ]
}

@test "an absent key yields an empty value and an empty line" {
  write_frontmatter 'description: A thing.'
  [ -z "${FM_RAW[model]:-}" ]
  [ -z "${FM_LINE[model]:-}" ]
}

@test "read_markdown keeps the quotes, leaving unquoting to the caller" {
  write_frontmatter 'description: "A quoted thing with a (#:keyword) in it."'
  [ "$(unquote "${FM_RAW[description]}")" = "A quoted thing with a (#:keyword) in it." ]
}

@test "read_markdown strips all leading blanks, however many" {
  write_frontmatter "$(printf 'description:  two spaces\nargument-hint:\ta tab')"
  [ "${FM_RAW[description]}" = "two spaces" ]
  [ "${FM_RAW[argument-hint]}" = "a tab" ]
}

@test "a file with no frontmatter reports status none" {
  printf '# Just a heading\n\nBody.\n' > "$FIXTURE"
  read_markdown "$FIXTURE"
  [ "$FM_STATUS" = "none" ]
  [ "${#FM_KEYS[@]}" -eq 0 ]
}

@test "frontmatter that never closes reports status unterminated" {
  printf -- '---\nname: doer\ntools: Read\n\n# doer\n' > "$FIXTURE"
  read_markdown "$FIXTURE"
  [ "$FM_STATUS" = "unterminated" ]
}

@test "a block sequence becomes one comma-joined value" {
  write_frontmatter 'tools:
  - Read
  - Taks'
  [ "${FM_RAW[tools]}" = "Read, Taks" ]
  [ "${FM_LINE[tools]}" -eq 2 ]
}

@test "read_markdown records a duplicate key rather than letting the last win" {
  write_frontmatter 'tools: Taks
tools: Read'
  [ "${#FM_DUPLICATES[@]}" -eq 1 ]
  [[ "${FM_DUPLICATES[0]}" == *"tools"* ]]
}

@test "read_markdown exposes the body without the frontmatter" {
  write_frontmatter 'description: A thing.'
  [[ "$FM_BODY" == *"Body."* ]]
  [[ "$FM_BODY" != *"description:"* ]]
}

@test "read_markdown tolerates CRLF endings and a byte-order mark" {
  printf -- '\xef\xbb\xbf---\r\ndescription: A thing.\r\n---\r\n\r\nBody.\r\n' > "$FIXTURE"
  read_markdown "$FIXTURE"
  [ "$FM_STATUS" = "ok" ]
  [ "${FM_RAW[description]}" = "A thing." ]
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
  run check_yaml_truncation "$FIXTURE"
  [ -n "$output" ]
  [[ "$output" == *":2: "* ]]
}

@test "check_yaml_truncation stays silent on the quoted form" {
  write_frontmatter 'description: "Options (#:transparent, #:mutable). Use when defining."'
  run check_yaml_truncation "$FIXTURE"
  [ -z "$output" ]
}

@test "check_yaml_truncation stays silent when no space precedes the hash" {
  write_frontmatter 'description: Build a reader (#:dispatch). Use when extending.'
  run check_yaml_truncation "$FIXTURE"
  [ -z "$output" ]
}

@test "check_yaml_truncation reports every affected key, not just the first" {
  write_frontmatter 'description: One (#:a, #:b).
argument-hint: Two (#:c, #:d).'
  run check_yaml_truncation "$FIXTURE"
  [ "$(printf '%s\n' "$output" | grep -c 'fixture')" -eq 2 ]
}

@test "check_yaml_truncation consumes the same normalised value the loader made" {
  # One input, one parser. The check once stripped a single leading space of
  # its own, so a quoted value indented by two was reported as truncated.
  write_frontmatter 'description:  "Options (#:transparent). Use when defining."'
  run check_yaml_truncation "$FIXTURE"
  [ -z "$output" ]
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

@test "check_tool_names accepts an MCP tool by pattern" {
  run check_tool_names "$FIXTURE" 3 'Read, mcp__github__list_issues'
  [ -z "$output" ]
}

# --- check_bare_tool_names --------------------------------------------------
#
# check_tool_names strips the argument off each token before matching it,
# which is what lets a skill scope one. An agent's list is bare names, so the
# scoping rule needs a check that reads the token before that strip.

@test "check_bare_tool_names reports an argument-scoped tool on the given line" {
  run check_bare_tool_names "$FIXTURE" 4 'Read, Bash(git status:*)'
  [[ "$output" == *":4: "* ]]
  [[ "$output" == *"Bash(git status:*)"* ]]
}

@test "check_bare_tool_names reports each scoped tool once" {
  run check_bare_tool_names "$FIXTURE" 4 'Bash(git status:*), Read, Agent(communication:prose-reviewer)'
  [ "$(printf '%s\n' "$output" | grep -c 'argument-scoped')" -eq 2 ]
}

@test "check_bare_tool_names stays silent on a list of bare names" {
  run check_bare_tool_names "$FIXTURE" 4 'Read, Grep, Glob, Bash'
  [ -z "$output" ]
}

# --- check_frontmatter_common -----------------------------------------------
#
# It returns 1 on a file with no usable frontmatter so its callers can stop,
# rather than reporting a cascade of missing keys against a file that has
# none of them.

@test "check_frontmatter_common reports a missing block and returns 1" {
  printf '# Title\n\nBody.\n' > "$FIXTURE"
  run check_frontmatter_common "$FIXTURE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no YAML frontmatter block"* ]]
}

@test "check_frontmatter_common reports an unterminated block and returns 1" {
  printf -- '---\nname: doer\n\n# doer\n' > "$FIXTURE"
  run check_frontmatter_common "$FIXTURE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"never closes"* ]]
}

@test "check_frontmatter_common returns 0 and stays silent on a good block" {
  printf -- '---\ndescription: A thing.\n---\n\nBody.\n' > "$FIXTURE"
  run check_frontmatter_common "$FIXTURE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_frontmatter_common reports a duplicate key on the second line" {
  printf -- '---\ntools: Taks\ntools: Read\n---\n\nBody.\n' > "$FIXTURE"
  run check_frontmatter_common "$FIXTURE"
  [[ "$output" == *":3: duplicate frontmatter key 'tools'"* ]]
}

# --- check_reference_cited --------------------------------------------------

@test "check_reference_cited reports a sibling the body never names" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf 'A table.\n' > "${dir}/reference.md"
  run check_reference_cited "${dir}/SKILL.md" "$dir" 'Goal: do the thing.'
  [[ "$output" == *"sibling reference.md"* ]]
}

@test "check_reference_cited is satisfied by a whole-word mention" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf 'A table.\n' > "${dir}/reference.md"
  run check_reference_cited "${dir}/SKILL.md" "$dir" 'Read `reference.md` here.'
  [ -z "$output" ]
}

@test "check_reference_cited is not satisfied by a longer name containing it" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf 'A table.\n' > "${dir}/reference.md"
  run check_reference_cited "${dir}/SKILL.md" "$dir" 'Read `other-reference.md` here.'
  [[ "$output" == *"sibling reference.md"* ]]
}

@test "check_reference_cited reports a subdirectory" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  mkdir -p "${dir}/references"
  run check_reference_cited "${dir}/SKILL.md" "$dir" 'Goal: do the thing.'
  [[ "$output" == *"references"* ]]
}

@test "check_reference_cited reports a citation that resolves to nothing" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  run check_reference_cited "${dir}/SKILL.md" "$dir" 'Read `missing.md` here.'
  [[ "$output" == *"missing.md"* ]]
}

@test "check_reference_cited accepts a citation resolving at the marketplace root" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf '# rules\n' > "${dir}/CLAUDE.md"
  mkdir -p "${dir}/skills/thing"
  run check_reference_cited "${dir}/skills/thing/SKILL.md" "$dir" 'Follow CLAUDE.md.'
  [ -z "$output" ]
}

# --- check_skill ------------------------------------------------------------

@test "check_skill reports a missing description" {
  printf -- '---\nargument-hint: "[hint]"\n---\n\nBody.\n' > "$FIXTURE"
  run check_skill "$FIXTURE" "$(fixture_dir)"
  [[ "$output" == *"no description"* ]]
}

@test "check_skill reports an unknown frontmatter key" {
  printf -- '---\ndescription: A thing.\ntools: Read\n---\n\nBody.\n' > "$FIXTURE"
  run check_skill "$FIXTURE" "$(fixture_dir)"
  [[ "$output" == *"unknown frontmatter key 'tools'"* ]]
}

@test "check_skill stays silent on a well-formed skill" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf -- '---\ndescription: A thing. Use when asked.\nallowed-tools: Read, Grep\n---\n\nBody.\n' \
    > "${dir}/SKILL.md"
  run check_skill "${dir}/SKILL.md" "$dir"
  [ -z "$output" ]
}

# --- check_agent ------------------------------------------------------------

@test "check_agent reports a missing name as missing, on line 1" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf -- '---\ndescription: A thing.\ntools: Read\nmodel: haiku\n---\n\nBody.\n' \
    > "${dir}/doer.md"
  run check_agent "${dir}/doer.md"
  [[ "$output" == *"no name"* ]]
  [[ "$output" != *"does not match"* ]]
}

@test "check_agent reports a mismatched name on the name's own line" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf -- '---\ndescription: A thing.\nname: other\ntools: Read\nmodel: haiku\n---\n\nBody.\n' \
    > "${dir}/doer.md"
  run check_agent "${dir}/doer.md"
  [[ "$output" == *":3: name 'other' does not match the filename 'doer'"* ]]
}

@test "check_agent reports a missing description on line 1 and a missing tools list" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf -- '---\nname: doer\nmodel: haiku\n---\n\nBody.\n' > "${dir}/doer.md"
  run check_agent "${dir}/doer.md"
  [[ "$output" == *"no description"* ]]
  [[ "$output" == *"no tools list"* ]]
}

@test "check_agent reports an unknown model on the model's own line" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf -- '---\nname: doer\ndescription: A thing.\ntools: Read\nmodel: gpt\n---\n\nBody.\n' \
    > "${dir}/doer.md"
  run check_agent "${dir}/doer.md"
  [[ "$output" == *":5: unknown model 'gpt'"* ]]
}

@test "check_agent reports an argument-scoped tool on the tools line" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf -- '---\nname: doer\ndescription: A thing.\ntools: Read, Bash(git status:*)\nmodel: haiku\n---\n\nBody.\n' \
    > "${dir}/doer.md"
  run check_agent "${dir}/doer.md"
  [[ "$output" == *":4: "*"Bash(git status:*)"* ]]
}

@test "check_agent stays silent on a well-formed agent" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  printf -- '---\nname: doer\ndescription: A thing.\ntools: Read, Grep\nmodel: haiku\n---\n\nBody.\n' \
    > "${dir}/doer.md"
  run check_agent "${dir}/doer.md"
  [ -z "$output" ]
}

# --- check_manifests --------------------------------------------------------

@test "check_manifests reports a marketplace manifest with no plugins array" {
  root="$(new_marketplace)"
  jq -n '{name:"fixture"}' > "${root}/.claude-plugin/marketplace.json"
  run check_manifests "$root"
  [[ "$output" == *"plugins"* ]]
  [[ "$output" != *"jq: error"* ]]
}

@test "check_manifests reports a plugin.json name that differs from its directory" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  jq '.name = "wrong"' "${root}/plugins/demo/.claude-plugin/plugin.json" > "${root}/p.tmp"
  mv "${root}/p.tmp" "${root}/plugins/demo/.claude-plugin/plugin.json"
  run check_manifests "$root"
  [[ "$output" == *"wrong"* ]]
}

@test "check_manifests reports a source that resolves to nothing" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  jq '.plugins[0].source = "./plugins/elsewhere"' \
    "${root}/.claude-plugin/marketplace.json" > "${root}/m.tmp"
  mv "${root}/m.tmp" "${root}/.claude-plugin/marketplace.json"
  run check_manifests "$root"
  [[ "$output" == *"source"* ]]
}

@test "check_manifests reports the same plugin name listed twice" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  jq '.plugins += [.plugins[0]]' "${root}/.claude-plugin/marketplace.json" > "${root}/m.tmp"
  mv "${root}/m.tmp" "${root}/.claude-plugin/marketplace.json"
  run check_manifests "$root"
  [[ "$output" == *"listed twice"* ]]
}

@test "check_manifests stays silent on two agreeing manifests" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  run check_manifests "$root"
  [ -z "$output" ]
}

# --- all_violations ---------------------------------------------------------

@test "all_violations reports a root with no plugins directory" {
  local dir
  dir="$(mktemp -d "$(fixture_dir)/fixture.XXXXXX")"
  run all_violations "$dir"
  [[ "$output" == *"plugins"* ]]
}

@test "all_violations reports a plugins tree holding no skills and no agents" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  run all_violations "$root"
  [[ "$output" == *"no skills and no agents"* ]]
}

@test "all_violations prints nothing for a clean tree" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  add_agent "$root" demo doer "$(valid_agent_frontmatter doer)"
  run all_violations "$root"
  [ -z "$output" ]
}

# --- main -------------------------------------------------------------------

@test "main prints the success line and exits 0 on a clean tree" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  add_agent "$root" demo doer "$(valid_agent_frontmatter doer)"
  run main "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "plugins: clean." ]
}

@test "main counts the violations it printed" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo one 'argument-hint: "[a hint]"'
  add_skill "$root" demo two 'argument-hint: "[a hint]"'
  run main "$root"
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 violation(s)."* ]]
}

@test "main exits 2 with a diagnostic when jq is not on PATH" {
  # A missing tool is an environment failure, not a plugin defect, and must
  # not be reported as one - a broken jq once read as "invalid JSON" on a
  # perfectly valid manifest.
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  run env PATH=/nonexistent /bin/bash "$VALIDATOR" "$root"
  [ "$status" -eq 2 ]
  [[ "$output" == *"jq"* ]]
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
