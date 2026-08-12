#!/usr/bin/env bats
# Unit tests against the internal functions of enforce-code-review.sh,
# exercised by sourcing the script (its BASH_SOURCE guard means sourcing it
# does not run main / does not read stdin) and calling
# missing_reviews_for_transcript directly against synthetic transcript
# fixtures - no stdin JSON payload involved.

load helpers

setup() {
  SCRIPT="${HOOKS_DIR}/enforce-code-review.sh"
  # shellcheck source=/dev/null
  source "$SCRIPT"
}

@test "sourcing the script does not execute main or read stdin" {
  # If main() ran, it would call `cat` and block waiting on this test's
  # stdin (a tty/empty pipe here); reaching this assertion at all proves it
  # didn't run.
  [ "$(type -t main)" = "function" ]
}

@test "missing_reviews_for_transcript: no code change yields empty missing set" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' "$(last_prompt_marker)" "$(tool_use_event Read)")")"
  result="$(missing_reviews_for_transcript "$transcript")"
  [ -z "$result" ]
}

@test "missing_reviews_for_transcript: code change with nothing invoked yields all four" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' "$(last_prompt_marker)" "$(tool_use_event Edit)")")"
  result="$(missing_reviews_for_transcript "$transcript")"
  [ "$(printf '%s\n' "$result" | wc -l)" -eq 4 ]
}

@test "monotonicity: appending a satisfying event shrinks the missing set, never grows it" {
  before_transcript="$(write_transcript "$(printf '%s\n%s\n' "$(last_prompt_marker)" "$(tool_use_event Edit)")")"
  before_missing="$(missing_reviews_for_transcript "$before_transcript")"
  before_count="$(printf '%s\n' "$before_missing" | grep -c . || true)"

  after_transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Skill skill=development:review-tdd)")")"
  after_missing="$(missing_reviews_for_transcript "$after_transcript")"
  after_count="$(printf '%s\n' "$after_missing" | grep -c . || true)"

  [ "$after_count" -le "$before_count" ]
  [[ "$after_missing" != *"review-tdd (skill)"* ]]
}

@test "find_turn_start_line warns on stderr when no prompt or marker is present in a non-empty transcript" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no user prompt or last-prompt marker in non-empty transcript"* ]]
}

@test "find_turn_start_line is silent (no warning) for a genuinely empty transcript" {
  transcript="$(mktemp "${BATS_TMPDIR:-/tmp}/empty.XXXXXX.jsonl")"
  : > "$transcript"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# --- SIGPIPE: a matcher fed by a pipe must not report "no match" merely
# --- because the reader exited before the writer finished. Under
# --- `set -o pipefail`, `producer | grep -q` takes the reader's early exit
# --- as SIGPIPE (141) on the producer and fails the whole pipeline, so a
# --- long event list silently opens the gate.

@test "code_was_edited detects an Edit at the head of a very long event list" {
  # Shaped events ({name, skill, subagent_type}), as
  # tool_use_events_since_turn_start emits them - not raw transcript lines.
  # seq/awk rather than `yes | head`: the latter's own SIGPIPE would fail the
  # fixture's command substitution under bats' pipefail, masking the result.
  events="$( { printf '%s\n' '{"name":"Edit","skill":null,"subagent_type":null}'
               seq 1 20000 | awk '{print "{\"name\":\"Read\",\"skill\":null,\"subagent_type\":null}"}'
             } )"
  run code_was_edited "$events"
  [ "$status" -eq 0 ]
}
