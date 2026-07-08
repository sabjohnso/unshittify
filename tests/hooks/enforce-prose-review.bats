#!/usr/bin/env bats
# Characterization + behavioral tests for enforce-prose-review.sh.

load helpers

setup() {
  SCRIPT="${HOOKS_DIR}/enforce-prose-review.sh"
  LONG_MSG="$(printf 'word %.0s' $(seq 1 60))"
  SHORT_MSG="only a few words here"
}

@test "stop_hook_active=true suppresses the check regardless of content" {
  stdin="$(stdin_payload stop_hook_active=true last_assistant_message="$LONG_MSG")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "short assistant message (< 50 words) never blocks" {
  stdin="$(stdin_payload last_assistant_message="$SHORT_MSG")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing transcript_path never blocks even with a long message" {
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "nonexistent transcript file never blocks" {
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path=/nonexistent/transcript.jsonl)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "long message, transcript with no last-prompt marker never blocks (current behavior)" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "long message, review-prose invoked since last prompt does not block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Skill skill=communication:review-prose)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "long message, review-prose NOT invoked since last prompt blocks" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"review-prose"* ]]
}

@test "review-prose invoked this turn is still detected when a last-prompt marker is appended after it" {
  # Reproduces the real transcript shape: the genuine user prompt, then the
  # turn's own review-prose call, then a last-prompt marker the harness
  # appends *after* the tool call. Anchoring on the marker's line position
  # skips the review and blocks a turn that was in fact reviewed.
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'Do you think that change will work?')" \
    "$(tool_use_event Skill skill=communication:review-prose)" \
    "$(last_prompt_marker)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a tool_result user message after the review is not mistaken for a new prompt boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'Do you think that change will work?')" \
    "$(tool_use_event Skill skill=communication:review-prose)" \
    "$(tool_result_event)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a skill-injected isMeta message after the review is not mistaken for a new prompt boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'Do you think that change will work?')" \
    "$(tool_use_event Skill skill=communication:review-prose)" \
    "$(meta_injection_event)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "genuine user prompt with no review since blocks" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'please explain this at length')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"review-prose"* ]]
}

@test "an array-content genuine prompt is recognized as a boundary (blocks when unreviewed)" {
  # A genuine prompt carrying an attachment arrives as an array of text blocks,
  # not a string. It must still anchor the turn; a string-only classifier would
  # miss it, find no boundary, and wrongly stay silent.
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_array_event 'please explain this at length')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"review-prose"* ]]
}

@test "review before the current prompt does not count for the current turn" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(user_prompt_event 'first turn asks for a review')" \
    "$(tool_use_event Skill skill=communication:review-prose)" \
    "$(user_prompt_event 'second turn is a fresh prose request')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
}
