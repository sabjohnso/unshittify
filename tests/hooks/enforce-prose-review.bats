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

@test "long message, prose-reviewer agent invoked since last prompt does not block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "long message, prose-reviewer agent NOT invoked since last prompt blocks" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "the review-prose skill no longer satisfies the requirement" {
  # The check was deliberately switched from the skill to the agent: invoking
  # only the communication:review-prose skill must now block, not pass.
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Skill skill=communication:review-prose)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "prose-reviewer agent invoked this turn is still detected when a last-prompt marker is appended after it" {
  # Reproduces the real transcript shape: the genuine user prompt, then the
  # turn's own prose-reviewer call, then a last-prompt marker the harness
  # appends *after* the tool call. Anchoring on the marker's line position
  # skips the review and blocks a turn that was in fact reviewed.
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'Do you think that change will work?')" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(last_prompt_marker)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a tool_result user message after the review is not mistaken for a new prompt boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'Do you think that change will work?')" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(tool_result_event)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a skill-injected isMeta message after the review is not mistaken for a new prompt boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'Do you think that change will work?')" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
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
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
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
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "a near-miss agent name containing prose-reviewer as a substring does not satisfy the requirement" {
  # Exact-name match, not substring: an agent merely *containing* "prose-reviewer"
  # (here communication:prose-reviewer-preview) must not count as the review.
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'please explain this at length')" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer-preview)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "a bare, unprefixed agent name does not satisfy the qualified requirement" {
  # The harness records the agent's subagent_type with its plugin prefix
  # (communication:prose-reviewer). A bare prose-reviewer is a prefix-truncated
  # near-miss and must not count - the prefix is load-bearing.
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'please explain this at length')" \
    "$(tool_use_event Task subagent_type=prose-reviewer)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "the exact-name match is case-sensitive: an uppercase variant does not satisfy it" {
  # Agent names are canonically lowercase, so a case variant is a different
  # agent and must not count as the review.
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'please explain this at length')" \
    "$(tool_use_event Task subagent_type=Communication:Prose-Reviewer)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "review before the current prompt does not count for the current turn" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(user_prompt_event 'first turn asks for a review')" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(user_prompt_event 'second turn is a fresh prose request')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
}
