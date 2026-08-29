#!/usr/bin/env bats
# Tests for validate-plugins.sh, the structural validator over plugins/.
#
# Everything under plugins/ is a JSON manifest or a Markdown prompt the
# harness loads directly, so nothing in the ordinary build catches a defect
# there. Each test below pins one rule that had already gone wrong in this
# repository at least once.

load helpers

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
