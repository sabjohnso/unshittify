#!/usr/bin/env bats
# Characterization + behavioral tests for enforce-code-review.sh.
#
# This suite covers behavior common to both the as-is (substring-matching)
# implementation and the fixed (exact-match) implementation. The
# substring-vs-exact-match distinction is covered separately in
# enforce-code-review-exact-match.bats, since that is the one behavior
# this migration is intentionally changing.

load helpers

TDD_SKILL="development:review-tdd"
NST_SKILL="development:review-nst"
PROPTEST_SKILL="development:review-property-tests"
TDD_AGENT="development:tdd-reviewer"
NST_AGENT="development:nst-reviewer"
PROPTEST_AGENT="development:property-test-reviewer"

setup() {
  SCRIPT="${HOOKS_DIR}/enforce-code-review.sh"
}

all_reviews_via_skills() {
  printf '%s\n%s\n%s\n' \
    "$(tool_use_event Skill skill="$TDD_SKILL")" \
    "$(tool_use_event Skill skill="$NST_SKILL")" \
    "$(tool_use_event Skill skill="$PROPTEST_SKILL")"
}

all_reviews_via_agents() {
  printf '%s\n%s\n%s\n' \
    "$(tool_use_event Agent subagent_type="$TDD_AGENT")" \
    "$(tool_use_event Agent subagent_type="$NST_AGENT")" \
    "$(tool_use_event Agent subagent_type="$PROPTEST_AGENT")"
}

@test "stop_hook_active=true suppresses the check regardless of content" {
  stdin="$(stdin_payload stop_hook_active=true)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing transcript_path never blocks" {
  stdin="$(stdin_payload)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "nonexistent transcript file never blocks" {
  stdin="$(stdin_payload transcript_path=/nonexistent/transcript.jsonl)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "transcript with no last-prompt marker never blocks (current behavior)" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no code change since last prompt: silent, no block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Read)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code changed, no reviews invoked: blocks naming all three" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  reason="$(reason_field "$output")"
  [[ "$reason" == *"review-tdd"* ]]
  [[ "$reason" == *"review-nst"* ]]
  [[ "$reason" == *"review-property-tests"* ]]
}

@test "code changed, all reviews satisfied via skills: no block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(all_reviews_via_skills)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code changed, all reviews satisfied via agents: no block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(all_reviews_via_agents)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code changed, reviews satisfied via a mix of skill and agent: no block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n%s' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Write)" \
    "$(tool_use_event Skill skill="$TDD_SKILL")" \
    "$(tool_use_event Agent subagent_type="$NST_AGENT")" \
    "$(tool_use_event Skill skill="$PROPTEST_SKILL")")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code changed, only TDD review satisfied: blocks naming the remaining two" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s' \
    "$(last_prompt_marker)" \
    "$(tool_use_event NotebookEdit)" \
    "$(tool_use_event Skill skill="$TDD_SKILL")")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  reason="$(reason_field "$output")"
  [[ "$reason" != *"review-tdd"* ]]
  [[ "$reason" == *"review-nst"* ]]
  [[ "$reason" == *"review-property-tests"* ]]
}

@test "duplicate-insensitivity: invoking the same review skill twice still leaves it satisfied once" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n%s\n%s' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Skill skill="$TDD_SKILL")" \
    "$(tool_use_event Skill skill="$TDD_SKILL")" \
    "$(all_reviews_via_skills)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "order-invariance: review invoked before the edit counts the same as after" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s' \
    "$(last_prompt_marker)" \
    "$(all_reviews_via_skills)" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reviews invoked this turn are still detected when a last-prompt marker is appended after them" {
  # The genuine prompt, this turn's reviews, then a last-prompt marker the
  # harness appends out of order (after the reviews), then a later edit.
  # Anchoring on the marker sees the edit but not the reviews and wrongly
  # blocks a turn that was in fact fully reviewed.
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$(user_prompt_event 'implement and review the feature')" \
    "$(tool_use_event Agent subagent_type="$TDD_AGENT")" \
    "$(tool_use_event Agent subagent_type="$NST_AGENT")" \
    "$(tool_use_event Agent subagent_type="$PROPTEST_AGENT")" \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an agent invocation recorded with its plugin prefix satisfies the requirement" {
  # Real transcripts record subagent_type with the plugin prefix
  # (development:tdd-reviewer), not the bare name. All three, prefixed and
  # after a code edit, must satisfy the requirement.
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Agent subagent_type=development:tdd-reviewer)" \
    "$(tool_use_event Agent subagent_type=development:nst-reviewer)" \
    "$(tool_use_event Agent subagent_type=development:property-test-reviewer)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stop_hook_active guard suppresses a would-be second block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript" stop_hook_active=true)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
