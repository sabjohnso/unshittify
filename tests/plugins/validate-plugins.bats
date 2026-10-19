#!/usr/bin/env bats
# Tests for validate-plugins.sh, the structural validator of plugins/.
#
# Everything under plugins/ is a JSON manifest or a Markdown prompt that the
# harness loads directly. So nothing in the ordinary build catches a defect
# there. Each test below pins one rule that went wrong in this repository at
# least once.

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
# An unquoted YAML scalar ends at a space and then a #. So a description
# that mentions a Racket #:keyword loses all the text after it, with the
# "Use when..." clause that makes the skill triggerable at all. The file on
# disk looks complete. That is why four skills shipped this way and nobody
# saw it.

@test "an unquoted description that a YAML comment truncates fails" {
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
  # YAML starts a comment only at a space and then a #. So a # that opens a
  # parenthesis or directly follows one is inert, and the validator must not
  # report it.
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo lang \
    'description: Build a reader (#:dispatch) for it. Use when extending the reader.'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- uncited reference files ----------------------------------------------
#
# A reference.md that the SKILL.md never names is unreachable. Nothing
# tells the model to open it, so its content is as good as absent from the
# repository.

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
# Agent) leaves a skill unable to do the one step that its own body
# requires.

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
# The allowed-tools of a skill can scope the arguments of a tool. The tools
# list of an agent holds bare names in this repository. The known-name check
# strips the argument off each token before it matches the token. So a
# scoped token in an agent validated clean, and the rule lived only in the
# prose of the meta plugin.

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

@test "an argument-scoped tool in the allowed-tools list of a skill passes" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing \
    "$(printf '%s\nallowed-tools: Bash(git status:*)' "$(valid_skill_frontmatter)")"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- manifest agreement ---------------------------------------------------
#
# The description of each plugin is written twice, in its own plugin.json
# and in the root marketplace.json. They drifted before.

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

@test "a plugin directory that is absent from the marketplace manifest fails" {
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
# Every agent in this repository names its model. So the cost and the
# capability of an agent do not change with the model of the session.
# Nothing enforced it.

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

@test "the validator reports every violation, not only the first" {
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
# `tools:` with the entries on the indented lines that follow is the other
# legal YAML spelling of the same list. The check that catches a stale
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

@test "the validator checks a block-sequence allowed-tools list too" {
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

@test "the validator reports frontmatter that opens but never closes" {
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

@test "a file with CRLF line ends parses as frontmatter" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  write_raw_skill "$root" demo thing \
    "$(printf -- '---\r\ndescription: Does the fixture thing. Use when asked.\r\n---\r\n\r\nGoal: do it.\r\n')"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

@test "a file with a UTF-8 byte-order mark parses as frontmatter" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  write_raw_skill "$root" demo thing \
    "$(printf -- '\xef\xbb\xbf---\ndescription: Does the fixture thing. Use when asked.\n---\n\nGoal: do it.\n')"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

@test "the validator reports a file with no frontmatter once, with no cascade" {
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
# Two parsers read one input. The truncation check stripped exactly one
# leading space before it looked for the opening quote, and the frontmatter
# loader stripped all of them. With two spaces, or a tab, the validator
# reported a correctly quoted description as truncated.

@test "extra spaces before a quoted value do not look like a truncation" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo structs \
    'description:  "Handles #:transparent structs. Use when asked."'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

@test "a tab before a quoted value does not look like a truncation" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo structs \
    "$(printf 'description:\t"Handles #:transparent structs. Use when asked."')"
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- the known-tool list --------------------------------------------------

@test "the validator accepts harness tools that are absent from the known list" {
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

@test "the validator accepts an MCP tool name by pattern" {
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

@test "the validator reports a duplicate frontmatter key and does not take the last value" {
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
# A skill that writes `tools:` where the harness reads `allowed-tools:`
# gets no tools and no complaint. A rejection of unknown keys catches the
# whole class of misspelled keys, not one key at a time.

@test "the validator reports a skill that uses tools instead of allowed-tools" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing \
    'description: Does the fixture thing. Use when the user asks for a fixture.
tools: Read, Taks'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown frontmatter key 'tools'"* ]]
}

@test "the validator reports an agent with an unknown frontmatter key" {
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

@test "the validator accepts every documented skill frontmatter key" {
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

@test "a sibling that is not Markdown must be cited too" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  add_sibling "$root" demo thing reference.txt
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reference.txt"* ]]
}

@test "the validator reports a subdirectory inside a skill directory" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  mkdir -p "${root}/plugins/demo/skills/thing/references"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"references"* ]]
}

@test "the validator reports a scripts subdirectory inside a skill directory" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  mkdir -p "${root}/plugins/demo/skills/thing/scripts"
  printf 'print("hi")\n' > "${root}/plugins/demo/skills/thing/scripts/run.py"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts"* ]]
}

@test "the validator reports a citation that names a file that does not exist" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)" \
    'Goal: do it. For the full table, read `missing-table.md` in this skill directory.'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing-table.md"* ]]
}

@test "a citation of a different file does not satisfy the requirement for reference.md" {
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

@test "a document at the marketplace root can be named although it is not a sibling" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  printf '# House rules\n' > "${root}/CLAUDE.md"
  add_skill "$root" demo thing "$(valid_skill_frontmatter)" \
    'Goal: do it, following CLAUDE.md.'
  run "$VALIDATOR" "$root"
  [ "$status" -eq 0 ]
}

# --- manifests ------------------------------------------------------------

@test "the validator reports a marketplace manifest with no plugins array and leaks no jq error" {
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

@test "the validator reports a missing marketplace manifest" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  rm "${root}/.claude-plugin/marketplace.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing marketplace manifest"* ]]
}

@test "the validator reports invalid JSON in the marketplace manifest" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  printf '{ "plugins": [ }\n' > "${root}/.claude-plugin/marketplace.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "the validator reports a marketplace entry with no matching plugin directory" {
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

@test "the validator reports a plugin.json whose name differs from its directory" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo thing "$(valid_skill_frontmatter)"
  jq '.name = "wrong"' "${root}/plugins/demo/.claude-plugin/plugin.json" > "${root}/p.tmp"
  mv "${root}/p.tmp" "${root}/plugins/demo/.claude-plugin/plugin.json"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"wrong"* ]]
}

@test "the validator reports a marketplace source that points to no directory" {
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

@test "the validator reports two marketplace entries with the same name" {
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
# A mistyped path in CI must not look like a pass.

@test "the validator reports a root with no plugins directory" {
  root="$(new_marketplace)"
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plugins"* ]]
}

@test "the validator reports a root whose plugins directory holds no skills and no agents" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no skills and no agents"* ]]
}

# --- agent frontmatter, continued -----------------------------------------

@test "the validator reports an unknown model value" {
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

@test "the validator reports an agent with no description" {
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

@test "the validator reports an agent with no tools list" {
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

@test "the validator reports an agent with no name as missing, not as a wrong value" {
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
# The report format exists so that an editor can jump to the violation.
# The validator must not report a field with a known line number against
# line 1.

@test "the validator reports a mismatched agent name on its own line" {
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

@test "the validator reports an unknown model on its own line" {
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

@test "a failed tree ends with the violation count" {
  root="$(new_marketplace)"
  add_plugin "$root" demo
  add_skill "$root" demo one 'argument-hint: "[a hint]"'
  add_skill "$root" demo two 'argument-hint: "[a hint]"'
  run "$VALIDATOR" "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 violation(s)."* ]]
}
