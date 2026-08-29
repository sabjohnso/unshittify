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

# --- tool_use_events_since_line --------------------------------------------

@test "tool_use_events_since_line starts at the given line, not the turn boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(tool_use_event Edit)" \
    "$(user_prompt_event 'do the work')" \
    "$(tool_use_event Read)")")"
  run tool_use_events_since_line "$transcript" 3
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"Read"'* ]]
  [[ "$output" != *'"name":"Edit"'* ]]
}

# --- agent_invoked_since_line -----------------------------------------------

@test "agent_invoked_since_line succeeds on an exact subagent_type match" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  run agent_invoked_since_line "$transcript" 1 communication:prose-reviewer
  [ "$status" -eq 0 ]
}

@test "agent_invoked_since_line fails on a near-miss name" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer-preview)")")"
  run agent_invoked_since_line "$transcript" 1 communication:prose-reviewer
  [ "$status" -ne 0 ]
}

@test "agent_invoked_since_line fails when only a skill by the same name ran" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Skill skill=communication:prose-reviewer)")")"
  run agent_invoked_since_line "$transcript" 1 communication:prose-reviewer
  [ "$status" -ne 0 ]
}

@test "agent_invoked_since_line is duplicate-insensitive" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  run agent_invoked_since_line "$transcript" 1 communication:prose-reviewer
  [ "$status" -eq 0 ]
}

@test "agent_invoked_since_line ignores invocations before the start line" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(user_prompt_event)" \
    "$(tool_use_event Edit)")")"
  run agent_invoked_since_line "$transcript" 2 communication:prose-reviewer
  [ "$status" -ne 0 ]
}

# --- transcript_judgeable ---------------------------------------------------

@test "transcript_judgeable fails on an empty path" {
  run transcript_judgeable ""
  [ "$status" -ne 0 ]
}

@test "transcript_judgeable fails on a nonexistent file" {
  run transcript_judgeable /nonexistent/transcript.jsonl
  [ "$status" -ne 0 ]
}

@test "transcript_judgeable succeeds on an existing file" {
  transcript="$(write_transcript "$(user_prompt_event)")"
  run transcript_judgeable "$transcript"
  [ "$status" -eq 0 ]
}

# --- harness injections are not turn boundaries ---------------------------
#
# A boundary must be a message the USER actually sent. The harness records
# several of its own messages in the user role with plain string content;
# each one that is treated as a boundary silently discards the evidence of
# everything the assistant did before it in the same turn.
#
# The task-notification case is the damaging one, and it is not hypothetical:
# it is written after the Agent tool_use that spawned the subagent, so an
# asynchronously delegated review can never be seen by a hook that anchors on
# the last qualifying user message.

@test "a task notification is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(typed_prompt_event 'review this project')" \
    "$(tool_use_event Agent subagent_type=communication:prose-reviewer)" \
    "$(task_notification_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "a delegated review stays visible after its completion notification" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(typed_prompt_event 'review this project')" \
    "$(tool_use_event Agent subagent_type=communication:prose-reviewer)" \
    "$(task_notification_event)")")"
  start_line="$(find_turn_start_line "$transcript")"
  run agent_invoked_since_line "$transcript" "$start_line" communication:prose-reviewer
  [ "$status" -eq 0 ]
}

@test "a slash-command marker is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'do the thing')" \
    "$(slash_command_marker_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "local command stdout is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'do the thing')" \
    "$(local_command_stdout_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "a typed prompt after a task notification is still a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(typed_prompt_event 'first prompt')" \
    "$(task_notification_event)" \
    "$(typed_prompt_event 'second prompt')")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
}

@test "a plain string prompt with no origin field is still a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(tool_use_event Read)" \
    "$(user_prompt_event 'an older-format prompt with no origin recorded')")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# --- the boundary rule only ever moves the boundary earlier -----------------
#
# The rejection rules in find_turn_start_line are stated in the code and in
# CLAUDE.md as only ever moving the turn start EARLIER, which is what makes a
# misjudgement cost a redundant review rather than a missed one. A stated
# invariant with no test is exactly the gap this suite exists to close.

@test "rejecting a harness message never moves the boundary later" {
  local injection
  for injection in "$(task_notification_event)" \
                   "$(slash_command_marker_event)" \
                   "$(local_command_stdout_event)"; do
    transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
      "$(typed_prompt_event 'the real prompt')" \
      "$(tool_use_event Agent subagent_type=communication:prose-reviewer)" \
      "$injection")")"
    run find_turn_start_line "$transcript"
    [ "$status" -eq 0 ]
    [ "$output" -le 3 ]
    [ "$output" -eq 1 ]
  done
}

@test "appending harness messages is idempotent for the boundary" {
  local one many
  one="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'the real prompt')" \
    "$(task_notification_event)")")"
  many="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(typed_prompt_event 'the real prompt')" \
    "$(task_notification_event a1)" \
    "$(task_notification_event a2)" \
    "$(task_notification_event a3)")")"
  [ "$(find_turn_start_line "$one")" -eq "$(find_turn_start_line "$many")" ]
}
