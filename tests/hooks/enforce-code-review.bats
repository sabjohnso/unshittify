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
EFF_SKILL="development:review-efficiency"
TDD_AGENT="development:tdd-reviewer"
NST_AGENT="development:nst-reviewer"
PROPTEST_AGENT="development:property-test-reviewer"
EFF_AGENT="development:efficiency-reviewer"

setup() {
  SCRIPT="${HOOKS_DIR}/enforce-code-review.sh"
}

all_reviews_via_skills() {
  printf '%s\n%s\n%s\n%s\n' \
    "$(tool_use_event Skill skill="$TDD_SKILL")" \
    "$(tool_use_event Skill skill="$NST_SKILL")" \
    "$(tool_use_event Skill skill="$PROPTEST_SKILL")" \
    "$(tool_use_event Skill skill="$EFF_SKILL")"
}

all_reviews_via_agents() {
  printf '%s\n%s\n%s\n%s\n' \
    "$(tool_use_event Agent subagent_type="$TDD_AGENT")" \
    "$(tool_use_event Agent subagent_type="$NST_AGENT")" \
    "$(tool_use_event Agent subagent_type="$PROPTEST_AGENT")" \
    "$(tool_use_event Agent subagent_type="$EFF_AGENT")"
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

@test "code changed, no reviews invoked: blocks naming all four" {
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
  [[ "$reason" == *"review-efficiency"* ]]
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
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n%s\n%s' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Write)" \
    "$(tool_use_event Skill skill="$TDD_SKILL")" \
    "$(tool_use_event Agent subagent_type="$NST_AGENT")" \
    "$(tool_use_event Skill skill="$PROPTEST_SKILL")" \
    "$(tool_use_event Agent subagent_type="$EFF_AGENT")")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code changed, only TDD review satisfied: blocks naming the remaining three" {
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
  [[ "$reason" == *"review-efficiency"* ]]
}

# The two tests below are examples, not law-pins. Duplicate-insensitivity and
# order-invariance are properties over every turn, and a single fixed turn
# cannot say a property holds - these two were the whole evidence for two of
# the three laws CLAUDE.md claims are pinned, and one of them permuted only
# the case where nothing was missing. The laws themselves are checked over
# generated turns in enforce-code-review-internals.bats ("law: ..."). What
# these keep is end-to-end coverage of the shapes through the hook's stdin
# interface, which the internals tests do not exercise.

@test "a review skill invoked twice in one turn still leaves it satisfied" {
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

@test "a review invoked before the edit counts the same as one invoked after" {
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
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$(user_prompt_event 'implement and review the feature')" \
    "$(tool_use_event Agent subagent_type="$TDD_AGENT")" \
    "$(tool_use_event Agent subagent_type="$NST_AGENT")" \
    "$(tool_use_event Agent subagent_type="$PROPTEST_AGENT")" \
    "$(tool_use_event Agent subagent_type="$EFF_AGENT")" \
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
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Agent subagent_type=development:tdd-reviewer)" \
    "$(tool_use_event Agent subagent_type=development:nst-reviewer)" \
    "$(tool_use_event Agent subagent_type=development:property-test-reviewer)" \
    "$(tool_use_event Agent subagent_type=development:efficiency-reviewer)")")"
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

# --- the two Stop hooks must agree on one transcript ------------------------
#
# Nothing else in either suite runs both hooks against the same input, which
# is why a deadlock between them shipped: enforce-prose-review.sh MANDATES
# delegating a substantial reply to communication:prose-reviewer, and that
# delegation was itself an unrecognised subagent here, so the turn that
# satisfied one hook was blocked by the other with no move left that
# satisfies both.

# substantial_prose <word-count>
#
# A plain-prose assistant message of the requested length, long enough to
# clear enforce-prose-review.sh's MIN_WORDS threshold.
substantial_prose() {
  local count="$1" i out=""
  for ((i = 0; i < count; i++)); do
    out+="word${i} "
  done
  printf '%s' "$out"
}

@test "a turn whose only delegation is the mandated prose review satisfies both Stop hooks" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(typed_prompt_event 'explain how the turn boundary is computed')" \
    "$(tool_use_event Read)" \
    "$(tool_use_event Agent subagent_type=communication:prose-reviewer)")")"
  stdin="$(stdin_payload transcript_path="$transcript" \
                         last_assistant_message="$(substantial_prose 120)")"

  run_hook "${HOOKS_DIR}/enforce-prose-review.sh" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "prose hook blocked: $output"; return 1; }

  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "code hook blocked a turn that changed no file: $output"; return 1; }
}

# --- unreadable stdin ------------------------------------------------------
#
# A Stop hook reports a block on stdout and exits 0. Any OTHER nonzero exit
# is a non-blocking error to the harness, so a payload that kills the script
# part-way lets the turn end unreviewed - the gate fails OPEN on the one
# input it cannot check at all.

@test "a stdin payload that is not JSON blocks rather than exiting nonzero" {
  run_hook "$SCRIPT" 'not json'
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
}

@test "a stdin payload that is JSON but not an object blocks" {
  run_hook "$SCRIPT" '"just a string"'
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
}

@test "an empty stdin payload blocks" {
  run_hook "$SCRIPT" ''
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
}

@test "a prompt starting with Briefly suppresses the code gate for the turn" {
  transcript="$(write_transcript "$(printf '%s\n%s' \
    "$(user_prompt_event 'Briefly patch the typo in the readme')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a prompt starting with lowercase briefly suppresses the code gate" {
  transcript="$(write_transcript "$(printf '%s\n%s' \
    "$(user_prompt_event 'briefly fix that off-by-one')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "briefly mid-sentence does not suppress the code gate" {
  transcript="$(write_transcript "$(printf '%s\n%s' \
    "$(user_prompt_event 'Fix that off-by-one briefly please')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
}
