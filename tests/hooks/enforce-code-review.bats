#!/usr/bin/env bats
# Characterization tests and behavior tests for enforce-code-review.sh.
#
# This suite covers the behavior that the old implementation (substring
# match) and the fixed implementation (exact match) share. The difference
# between a substring match and an exact match is in
# enforce-code-review-exact-match.bats, because that is the one behavior
# that the migration changes on purpose.

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

@test "stop_hook_active=true stops the check, whatever the content" {
  stdin="$(stdin_payload stop_hook_active=true)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a missing transcript_path never blocks" {
  stdin="$(stdin_payload)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a transcript file that does not exist never blocks" {
  stdin="$(stdin_payload transcript_path=/nonexistent/transcript.jsonl)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a transcript with no last-prompt marker never blocks (current behavior)" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no code change after the last prompt: the hook is silent and does not block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Read)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code changed and no review ran: the hook blocks and names all four" {
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

@test "code changed and all reviews ran as skills: no block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(all_reviews_via_skills)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code changed and all reviews ran as agents: no block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(all_reviews_via_agents)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code changed and the reviews ran as a mix of skills and agents: no block" {
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

@test "code changed and only the TDD review ran: the hook blocks and names the other three" {
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

# The two tests below are examples. They do not pin a law. Duplicate
# insensitivity and order invariance are properties over every turn,
# and a single fixed turn cannot show that a property holds. These two tests
# were the whole evidence for two of the three laws that CLAUDE.md says are
# pinned, and one of them permuted only the case where nothing was missing.
# The "law: ..." tests in enforce-code-review-internals.bats check the laws
# themselves over generated turns. These two tests keep the end-to-end
# coverage of the shapes through the stdin interface of the hook, which the
# internals tests do not use.

@test "a review skill that ran twice in one turn is satisfied" {
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

@test "a review that ran before the edit counts the same as one that ran after" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s' \
    "$(last_prompt_marker)" \
    "$(all_reviews_via_skills)" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the hook still finds the reviews of this turn when a last-prompt marker follows them" {
  # The genuine prompt, the reviews of this turn, then a last-prompt marker
  # that the harness appends out of order (after the reviews), then a later
  # edit. An anchor on the marker sees the edit but not the reviews, and it
  # blocks a fully reviewed turn in error.
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

@test "an agent call recorded with its plugin prefix satisfies the requirement" {
  # A real transcript records subagent_type with the plugin prefix
  # (development:tdd-reviewer), not with the bare name. All four, with the
  # prefix and after a code edit, must satisfy the requirement.
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

@test "the stop_hook_active guard stops a second block" {
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
# Nothing else in either suite runs both hooks against the same input.
# That is why a deadlock between them shipped. enforce-prose-review.sh
# MANDATES a delegation of a substantial reply to
# communication:prose-reviewer, and that delegation was an unknown subagent
# here. So the turn that satisfied one hook was blocked by the other, with
# no move left that satisfied both.

# substantial_prose <word-count>
#
# A plain-prose assistant message of the requested length. It is long
# enough to pass the MIN_WORDS threshold of enforce-prose-review.sh.
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
# A Stop hook reports a block on stdout and exits 0. Every OTHER nonzero
# exit is a non-blocking error to the harness. A payload that kills the
# script part of the way through lets the turn end with no review. The gate
# fails OPEN on the one input it cannot check at all.

@test "a stdin payload that is not JSON blocks and does not exit nonzero" {
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

@test "a prompt that starts with Briefly stops the code gate for the turn" {
  transcript="$(write_transcript "$(printf '%s\n%s' \
    "$(user_prompt_event 'Briefly patch the typo in the readme')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a prompt that starts with lowercase briefly stops the code gate" {
  transcript="$(write_transcript "$(printf '%s\n%s' \
    "$(user_prompt_event 'briefly fix that off-by-one')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "briefly in the middle of a sentence does not stop the code gate" {
  transcript="$(write_transcript "$(printf '%s\n%s' \
    "$(user_prompt_event 'Fix that off-by-one briefly please')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
}
