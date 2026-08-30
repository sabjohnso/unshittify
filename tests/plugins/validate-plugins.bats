#!/usr/bin/env bats
# Tests for validate-plugins.sh, the structural validator over plugins/.
#
# Everything under plugins/ is a JSON manifest or a Markdown prompt the
# harness loads directly, so nothing in the ordinary build catches a defect
# there. Each test below pins one rule that had already gone wrong in this
# repository at least once.

load helpers

teardown() {
  cleanup_fixtures
}

@test "a clean tree passes" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  add_agent "$root" demo doer "$(valid_agent_frontmatter doer)"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- YAML comment truncation ----------------------------------------------
#
# An unquoted YAML scalar ends at a space-then-#, so a description mentioning
# a Racket #:keyword loses everything after it - including the "Use when..."
# clause that makes the skill triggerable at all. The file on disk looks
# complete, which is why four skills shipped this way unnoticed.

@test "an unquoted description truncated by a YAML comment fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo structs \
    'description: Define a struct with options (#:transparent, #:mutable). Use when defining a struct.'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"structs/SKILL.md"* ]]
  [[ "$output" == *"truncat"* ]]
}

@test "the same description quoted passes" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo structs \
    'description: "Define a struct with options (#:transparent, #:mutable). Use when defining a struct."'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

@test "a hash with no preceding space does not trip the check" {
  # YAML only starts a comment at a space-then-#, so a # that opens a
  # parenthesis or follows one directly is inert and must not be reported.
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo lang \
    'description: Build a reader (#:dispatch) for it. Use when extending the reader.'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- uncited reference files ----------------------------------------------
#
# A reference.md the SKILL.md never names is unreachable: nothing instructs
# the model to open it, so its content may as well not be in the repository.

@test "a reference.md the SKILL.md never cites fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  printf 'A large lookup table.\n' > "${root}/plugins/demo/skills/thing/reference.md"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reference.md"* ]]
}

@test "a reference.md the SKILL.md cites passes" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)" \
    'Goal: do it. For the full table, read `reference.md` in this skill directory.'
  printf 'A large lookup table.\n' > "${root}/plugins/demo/skills/thing/reference.md"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- unknown tool names ---------------------------------------------------
#
# allowed-tools and tools name harness tools. A renamed tool (Task became
# Agent) leaves a skill unable to do the one step its own body requires.

@test "an unknown tool in allowed-tools fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing \
    "$(printf '%s\nallowed-tools: Read, Task(communication:prose-reviewer)' "$(valid_skill_frontmatter)")"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Task"* ]]
}

@test "known tools in allowed-tools pass" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing \
    "$(printf '%s\nallowed-tools: Read, Grep, Bash(git status:*), Agent(communication:prose-reviewer)' "$(valid_skill_frontmatter)")"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

@test "an unknown tool in an agent tools list fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Read, Taks
model: haiku'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Taks"* ]]
}

# --- agent tool lists take bare names --------------------------------------
#
# A skill's allowed-tools may scope a tool's arguments; an agent's tools list
# is bare names in this repository. The known-name check strips the argument
# off each token before matching it, so a scoped token in an agent validated
# clean and the rule lived only in the meta plugin's prose.

@test "an argument-scoped tool in an agent tools list fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Read, Bash(git status:*)
model: haiku'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Bash(git status:*)"* ]]
}

@test "an argument-scoped tool in a skill allowed-tools list still passes" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing \
    "$(printf '%s\nallowed-tools: Bash(git status:*)' "$(valid_skill_frontmatter)")"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- manifest agreement ---------------------------------------------------
#
# Each plugin's description is written twice, in its own plugin.json and in
# the root marketplace.json. They have drifted before.

@test "a description that differs between the two manifests fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo "The original description."
  jq '.plugins[0].description = "A different description."' \
    "${root}/.claude-plugin/marketplace.json" > "${root}/m.tmp"
  mv "${root}/m.tmp" "${root}/.claude-plugin/marketplace.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"description"* ]]
}

@test "a plugin directory missing from the marketplace manifest fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  mkdir -p "${root}/plugins/orphan/.claude-plugin"
  jq -n '{name:"orphan", description:"Unlisted.", version:"0.1.0"}' \
    > "${root}/plugins/orphan/.claude-plugin/plugin.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"orphan"* ]]
}

@test "invalid JSON in a plugin manifest fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  printf '{ "name": "demo", }\n' > "${root}/plugins/demo/.claude-plugin/plugin.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"JSON"* ]]
}

# --- agent frontmatter ----------------------------------------------------
#
# Every agent in this repository names its model, so an agent's cost and
# capability do not swing with the session's model. Nothing enforced it.

@test "an agent with no model field fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Read, Grep'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"model"* ]]
}

@test "an agent whose name does not match its filename fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: not-doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Read, Grep
model: haiku'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"doer"* ]]
}

@test "a skill with no description fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing 'argument-hint: "[a hint]"'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"description"* ]]
}

# --- reporting ------------------------------------------------------------

@test "every violation is reported, not just the first" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo one 'argument-hint: "[a hint]"'
  add_skill "$root" demo two 'argument-hint: "[a hint]"'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'SKILL.md')" -eq 2 ]
}

@test "each violation names the file and line it is on" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo structs \
    'description: Define a struct with options (#:transparent, #:mutable). Use when defining a struct.'
  run "$VALIDATOR" "$root"
  [[ "$output" =~ SKILL\.md:[0-9]+: ]]
}

# --- tools written as a YAML block sequence -------------------------------
#
# `tools:` with the entries on following indented lines is the other legal
# YAML spelling of the same list. The check that exists to catch a stale
# `Task` saw an empty value there and reported nothing.

@test "an unknown tool in a block-sequence tools list fails" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
model: haiku
tools:
  - Read
  - Taks'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Taks"* ]]
}

@test "known tools in a block-sequence tools list pass" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
model: haiku
tools:
  - Read
  - Grep'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

@test "a block-sequence allowed-tools list is checked too" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing \
    'description: Does the fixture thing. Use when the user asks for a fixture.
allowed-tools:
  - Read
  - Taks'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Taks"* ]]
}

# --- frontmatter framing --------------------------------------------------

@test "frontmatter that opens but never closes is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  write_raw_agent "$root" demo doer \
    '---
name: doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Read, Grep
model: haiku

# doer

You do the fixture thing.
'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"never closes"* ]]
}

@test "CRLF line endings still parse as frontmatter" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  write_raw_skill "$root" demo thing \
    "$(printf -- '---\r\ndescription: Does the fixture thing. Use when asked.\r\n---\r\n\r\nGoal: do it.\r\n')"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

@test "a UTF-8 byte-order mark still parses as frontmatter" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  write_raw_skill "$root" demo thing \
    "$(printf -- '\xef\xbb\xbf---\ndescription: Does the fixture thing. Use when asked.\n---\n\nGoal: do it.\n')"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

@test "a file with no frontmatter is reported once, with no cascade" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  write_raw_agent "$root" demo doer '# doer

You do the fixture thing.
'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'doer.md:')" -eq 1 ]
  [[ "$output" == *"no YAML frontmatter block"* ]]
}

# --- the leading-blank false positive -------------------------------------
#
# One input was parsed by two parsers: the truncation check stripped exactly
# one leading space before looking for the opening quote, while the
# frontmatter loader stripped all of them. Two spaces, or a tab, and a
# properly quoted description was reported as truncated.

@test "extra spaces before a quoted value do not fake a truncation" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo structs \
    'description:  "Handles #:transparent structs. Use when asked."'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

@test "a tab before a quoted value does not fake a truncation" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo structs \
    "$(printf 'description:\t"Handles #:transparent structs. Use when asked."')"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- the known-tool list --------------------------------------------------

@test "harness tools missing from the known list are accepted" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Read, Bash, BashOutput, WebFetch, ToolSearch
model: haiku'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

@test "an MCP tool name is accepted by pattern" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Read, mcp__github__list_issues
model: haiku'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- duplicate frontmatter keys -------------------------------------------

@test "a duplicate frontmatter key is reported, not silently overridden" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Taks
tools: Read
model: haiku'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate"* ]]
}

# --- unknown frontmatter keys ---------------------------------------------
#
# A skill that writes `tools:` where the harness reads `allowed-tools:` gets
# no tools and no complaint. Rejecting unknown keys catches the whole
# misspelling class rather than one key at a time.

@test "a skill using tools instead of allowed-tools is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing \
    'description: Does the fixture thing. Use when the user asks for a fixture.
tools: Read, Taks'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown frontmatter key 'tools'"* ]]
}

@test "an agent with an unknown frontmatter key is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Read, Grep
model: haiku
allowed-tools: Read'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown frontmatter key 'allowed-tools'"* ]]
}

@test "every documented skill frontmatter key is accepted" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing \
    'description: Does the fixture thing. Use when the user asks for a fixture.
argument-hint: "[a hint]"
disable-model-invocation: true
allowed-tools: Read, Grep'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- sibling files and citations ------------------------------------------

@test "a sibling that is not Markdown must still be cited" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  add_sibling "$root" demo thing reference.txt
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reference.txt"* ]]
}

@test "a subdirectory inside a skill directory is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  mkdir -p "${root}/plugins/demo/skills/thing/references"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"references"* ]]
}

@test "a scripts subdirectory inside a skill directory is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  mkdir -p "${root}/plugins/demo/skills/thing/scripts"
  printf 'print("hi")\n' > "${root}/plugins/demo/skills/thing/scripts/run.py"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts"* ]]
}

@test "a citation naming a file that does not exist is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)" \
    'Goal: do it. For the full table, read `missing-table.md` in this skill directory.'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing-table.md"* ]]
}

@test "citing a different file does not satisfy the requirement for reference.md" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)" \
    'Goal: do it. Read `other-reference.md` in this skill directory.'
  add_sibling "$root" demo thing reference.md
  add_sibling "$root" demo thing other-reference.md
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sibling reference.md"* ]]
}

@test "a citation only in the frontmatter does not satisfy the requirement" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing \
    'description: "Does the fixture thing, as reference.md sets out. Use when asked."'
  add_sibling "$root" demo thing reference.md
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sibling reference.md"* ]]
}

@test "a document at the marketplace root may be named without being a sibling" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  printf '# House rules\n' > "${root}/CLAUDE.md"
  add_skill "$root" demo thing "$(valid_skill_frontmatter)" \
    'Goal: do it, following CLAUDE.md.'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- manifests ------------------------------------------------------------

@test "a marketplace manifest with no plugins array is reported, not leaked" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  jq -n '{name:"fixture", owner:{name:"Fixture Owner"}}' \
    > "${root}/.claude-plugin/marketplace.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plugins"* ]]
  [[ "$output" != *"jq: error"* ]]
}

@test "a missing marketplace manifest is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  rm "${root}/.claude-plugin/marketplace.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing marketplace manifest"* ]]
}

@test "invalid JSON in the marketplace manifest is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  printf '{ "plugins": [ }\n' > "${root}/.claude-plugin/marketplace.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "a marketplace entry with no matching plugin directory is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  jq '.plugins += [{name:"ghost", source:"./plugins/ghost", description:"Absent."}]' \
    "${root}/.claude-plugin/marketplace.json" > "${root}/m.tmp"
  mv "${root}/m.tmp" "${root}/.claude-plugin/marketplace.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ghost"* ]]
}

@test "a plugin.json whose name differs from its directory is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  jq '.name = "wrong"' "${root}/plugins/demo/.claude-plugin/plugin.json" > "${root}/p.tmp"
  mv "${root}/p.tmp" "${root}/plugins/demo/.claude-plugin/plugin.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"wrong"* ]]
}

@test "a marketplace source pointing nowhere is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  jq '.plugins[0].source = "./plugins/elsewhere"' \
    "${root}/.claude-plugin/marketplace.json" > "${root}/m.tmp"
  mv "${root}/m.tmp" "${root}/.claude-plugin/marketplace.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"source"* ]]
}

@test "two marketplace entries with the same name are reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  jq '.plugins += [.plugins[0]]' \
    "${root}/.claude-plugin/marketplace.json" > "${root}/m.tmp"
  mv "${root}/m.tmp" "${root}/.claude-plugin/marketplace.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"listed twice"* ]]
}

# --- a wrong root ---------------------------------------------------------
#
# A mistyped path in CI must not look like a passing run.

@test "a root with no plugins directory is reported" {
  root="$(new_marketplace)"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plugins"* ]]
}

@test "a root whose plugins directory holds no skills and no agents is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no skills and no agents"* ]]
}

# --- agent frontmatter, continued -----------------------------------------

@test "an unknown model value is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Read, Grep
model: gpt'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown model 'gpt'"* ]]
}

@test "an agent with no description is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
tools: Read, Grep
model: haiku'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no description"* ]]
}

@test "an agent with no tools list is reported" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
model: haiku'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no tools list"* ]]
}

@test "an agent with no name reads as missing, not as a wrong value" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'description: Does the fixture thing. Use when delegating a fixture.
tools: Read, Grep
model: haiku'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no name"* ]]
  [[ "$output" != *"name '' does not match"* ]]
}

# --- jumpable line numbers ------------------------------------------------
#
# The report format exists so an editor can jump to the violation. A field
# whose line number is known must not be reported against line 1.

@test "a mismatched agent name is reported on its own line" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'description: Does the fixture thing. Use when delegating a fixture.
name: not-doer
tools: Read, Grep
model: haiku'
  run "$VALIDATOR" "$root"
  [[ "$output" == *"doer.md:3: name 'not-doer'"* ]]
}

@test "an unknown model is reported on its own line" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_agent "$root" demo doer \
    'name: doer
description: Does the fixture thing. Use when delegating a fixture.
tools: Read, Grep
model: gpt'
  run "$VALIDATOR" "$root"
  [[ "$output" == *"doer.md:5: unknown model"* ]]
}

# --- the two lines a caller could parse ------------------------------------

@test "a clean tree prints exactly the success line" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  add_agent "$root" demo doer "$(valid_agent_frontmatter doer)"
  run "$VALIDATOR" "$root"
  [ "$output" = "plugins: clean." ]
}

@test "a failing tree ends with the violation count" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo one 'argument-hint: "[a hint]"'
  add_skill "$root" demo two 'argument-hint: "[a hint]"'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 violation(s)."* ]]
}
