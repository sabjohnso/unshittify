#!/usr/bin/env bats
# Unit tests for the shared transcript helpers in hooks/lib/transcript.sh,
# exercised by sourcing the library directly (it defines functions only, runs
# nothing) and calling find_turn_start_line / tool_use_events_since_turn_start
# against synthetic transcript fixtures.

load helpers

setup() {
  # shellcheck source=/dev/null
  source "${HOOKS_DIR}/lib/transcript.sh"
}

# --- find_turn_start_line -------------------------------------------------

@test "the last genuine user prompt is the boundary even when a marker follows it" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'do the thing')" \
    "$(tool_use_event Skill skill=communication:review-prose)" \
    "$(last_prompt_marker)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "a tool_result user message is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'do the thing')" \
    "$(tool_result_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "an isMeta injection is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'do the thing')" \
    "$(meta_injection_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "an array-content prompt is a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(tool_use_event Read)" \
    "$(user_prompt_array_event 'do the thing')")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "the most recent genuine prompt wins" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'first prompt')" \
    "$(tool_use_event Edit)" \
    "$(user_prompt_event 'second prompt')")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
}

@test "falls back to the last-prompt marker when no genuine prompt exists" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "an empty transcript returns 1 and is silent" {
  transcript="$(mktemp "${BATS_TMPDIR:-/tmp}/empty.XXXXXX.jsonl")"
  : > "$transcript"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a non-empty transcript with no prompt or marker returns 1 and warns" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no user prompt or last-prompt marker in non-empty transcript"* ]]
}

# --- tool_use_events_since_turn_start -------------------------------------

@test "emits one shaped event per tool_use since the turn start" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(user_prompt_event 'do and review')" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Skill skill=development:review-nst)" \
    "$(tool_use_event Agent subagent_type=nst-reviewer)")")"
  run tool_use_events_since_turn_start "$transcript"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '"name":"Edit"')" -eq 1 ]
  [[ "$output" == *'"skill":"development:review-nst"'* ]]
  [[ "$output" == *'"subagent_type":"nst-reviewer"'* ]]
}

@test "emits nothing on stdout when there is no turn start" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  # stderr carries the schema-anomaly warning; stdout must be empty.
  result="$(tool_use_events_since_turn_start "$transcript" 2>/dev/null)"
  [ -z "$result" ]
}

@test "excludes tool_use events that precede the turn boundary" {
  # A review from a previous turn (before the current prompt) must not count.
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(tool_use_event Skill skill=development:review-nst)" \
    "$(user_prompt_event 'now do the work')" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Skill skill=development:review-tdd)")")"
  run tool_use_events_since_turn_start "$transcript"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"skill":"development:review-nst"'* ]]
  [[ "$output" == *'"skill":"development:review-tdd"'* ]]
  [[ "$output" == *'"name":"Edit"'* ]]
}

@test "warns and yields no events on stdout when a line after the boundary is malformed" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'do the work')" \
    'this is not json')")"
  result="$(tool_use_events_since_turn_start "$transcript" 2>/dev/null)"
  [ -z "$result" ]
  run tool_use_events_since_turn_start "$transcript"
  [[ "$output" == *"failed to parse tool_use events"* ]]
}
