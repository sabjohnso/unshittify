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
