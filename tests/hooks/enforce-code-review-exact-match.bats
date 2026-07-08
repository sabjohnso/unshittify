#!/usr/bin/env bats
# Regression test for the exact-match bug fix in enforce-code-review.sh.
#
# The required-review checks must match skill/agent names exactly, not by
# unanchored substring. Names are fully qualified with the plugin prefix, as
# the transcript records them. A skill named "development:review-tdd-summary"
# (a near-miss that merely *contains* "development:review-tdd") must NOT
# satisfy the "development:review-tdd" requirement; likewise an agent named
# "development:nst-reviewer-v2" must NOT satisfy "development:nst-reviewer",
# and the bare, unprefixed "nst-reviewer" must NOT satisfy it either.
#
# These tests are expected to FAIL against the original substring-grep
# implementation and PASS once exact-name matching is in place.

load helpers

setup() {
  SCRIPT="${HOOKS_DIR}/enforce-code-review.sh"
}

@test "a near-miss skill name does not satisfy the review-tdd requirement" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Skill skill=development:review-tdd-summary)" \
    "$(tool_use_event Skill skill=development:review-nst)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  reason="$(reason_field "$output")"
  [[ "$reason" == *"development:review-tdd (skill)"* ]]
}

@test "a suffix near-miss agent name does not satisfy the nst-reviewer requirement" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Agent subagent_type=development:nst-reviewer-v2)" \
    "$(tool_use_event Skill skill=development:review-tdd)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  reason="$(reason_field "$output")"
  [[ "$reason" == *"development:nst-reviewer (agent)"* ]]
}

@test "a bare, unprefixed agent name does not satisfy the qualified nst-reviewer requirement" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Agent subagent_type=nst-reviewer)" \
    "$(tool_use_event Skill skill=development:review-tdd)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  reason="$(reason_field "$output")"
  [[ "$reason" == *"development:nst-reviewer (agent)"* ]]
}
