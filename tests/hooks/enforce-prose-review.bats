#!/usr/bin/env bats
# Characterization tests and behavior tests for enforce-prose-review.sh.

load helpers

setup() {
  SCRIPT="${HOOKS_DIR}/enforce-prose-review.sh"
  LONG_MSG="$(printf 'word %.0s' $(seq 1 60))"
  SHORT_MSG="only a few words here"
}

@test "stop_hook_active=true stops the check, whatever the content" {
  stdin="$(stdin_payload stop_hook_active=true last_assistant_message="$LONG_MSG")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a short assistant message (under 50 words) never blocks" {
  stdin="$(stdin_payload last_assistant_message="$SHORT_MSG")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a missing transcript_path never blocks, also with a long message" {
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a transcript file that does not exist never blocks" {
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path=/nonexistent/transcript.jsonl)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a long message with a transcript that has no last-prompt marker never blocks (current behavior)" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a long message does not block when the prose-reviewer agent ran after the last prompt" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a long message blocks when the prose-reviewer agent did NOT run after the last prompt" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "the review-prose skill does not satisfy the requirement" {
  # The check moved from the skill to the agent on purpose. A call to only
  # the communication:review-prose skill must block, not pass.
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Skill skill=communication:review-prose)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "the hook still finds a prose-reviewer call of this turn when a last-prompt marker follows it" {
  # This is the real transcript shape: the genuine user prompt, then the
  # prose-reviewer call of the turn, then a last-prompt marker that the
  # harness appends *after* the tool call. An anchor on the line of the
  # marker skips the review and blocks a turn that was reviewed.
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'Do you think that change will work?')" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(last_prompt_marker)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a tool_result user message after the review is not a new prompt boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'Do you think that change will work?')" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(tool_result_event)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an isMeta message from a skill after the review is not a new prompt boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'Do you think that change will work?')" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(meta_injection_event)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a genuine user prompt with no review after it blocks" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'please explain this at length')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "a genuine prompt with array content is a boundary (it blocks when no review ran)" {
  # A genuine prompt with an attachment arrives as an array of text blocks,
  # not as a string. It must anchor the turn. A classifier for strings only
  # misses it, finds no boundary, and stays silent in error.
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_array_event 'please explain this at length')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "a near-miss agent name that holds prose-reviewer as a substring does not satisfy the requirement" {
  # The match is on the exact name, not on a substring. An agent that only
  # *holds* "prose-reviewer" (here communication:prose-reviewer-preview) must
  # not count as the review.
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'please explain this at length')" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer-preview)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "a bare agent name with no prefix does not satisfy the qualified requirement" {
  # The harness records the subagent_type of the agent with its plugin
  # prefix (communication:prose-reviewer). A bare prose-reviewer is a near
  # miss with the prefix cut off, and it must not count. The prefix is
  # necessary.
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'please explain this at length')" \
    "$(tool_use_event Task subagent_type=prose-reviewer)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "the exact-name match is case-sensitive, so an uppercase variant does not satisfy it" {
  # Agent names are lowercase by convention, so a case variant is a
  # different agent and must not count as the review.
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'please explain this at length')" \
    "$(tool_use_event Task subagent_type=Communication:Prose-Reviewer)")")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"prose-reviewer"* ]]
}

@test "a review before the current prompt does not count for the current turn" {
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

# --- a response that is code, not prose ------------------------------------
#
# MIN_WORDS is calibrated for prose. A response whose whole content is one
# fenced code block has no prose to review. A count of its tokens as words
# demands a prose review of a diff.

# fenced_code_message
#
# A response that is one fenced code block and nothing else. By `wc -w`, it
# is well over MIN_WORDS.
fenced_code_message() {
  cat <<'MSG'
```bash
review_satisfied() {
  local events="$1" skill_name="$2" agent_name="$3"
  printf '%s\n' "$events" \
    | jq -e -s --arg s "$skill_name" --arg a "$agent_name" \
        'any(.[]; .skill == $s or .subagent_type == $a)' >/dev/null 2>&1
}

missing_reviews() {
  local entry
  for entry in "${REQUIRED_REVIEWS[@]}"; do
    review_satisfied "$1" "${entry%%|*}" "${entry##*|}" || echo "${entry}"
  done
}
```
MSG
}

@test "a response that is one fenced code block never blocks" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'show me the script')" \
    "$(tool_use_event Edit)")")"
  stdin="$(stdin_payload last_assistant_message="$(fenced_code_message)" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "substantial prose before a code block still blocks, and the count holds only the prose" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'please explain this at length')" \
    "$(tool_use_event Edit)")")"
  message="$(printf '%s\n%s\n' "$LONG_MSG" "$(fenced_code_message)")"
  stdin="$(stdin_payload last_assistant_message="$message" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"(60 words)"* ]]
}

# --- malformed stdin --------------------------------------------------------
#
# The hook reads the payload with bare `jq -r '.field'` assignments under
# `set -e`. A payload that is not a JSON object makes each of those abort the
# script. The hook exits with a nonzero status and no decision, so the turn
# ends with no judgement and only the parse error of jq as a trace. Whether
# the harness ever sends one or not, a Stop hook must reach a deliberate
# verdict on its own input. It must not crash into one.

@test "stdin that is not JSON exits with status 0 and no decision" {
  run_hook "$SCRIPT" 'not json at all'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stdin that is JSON but not an object exits with status 0 and no decision" {
  run_hook "$SCRIPT" '"just a string"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a truncated JSON payload exits with status 0 and no decision" {
  run_hook "$SCRIPT" '{"last_assistant_message": "half a pay'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a prompt that starts with Briefly stops the prose gate for the turn" {
  transcript="$(write_transcript "$(user_prompt_event 'Briefly, what changed here?')")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a prompt that starts with lowercase briefly stops the prose gate" {
  transcript="$(write_transcript "$(user_prompt_event 'briefly summarize the diff')")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "briefly in the middle of a sentence does not stop the prose gate" {
  transcript="$(write_transcript "$(user_prompt_event 'Explain briefly what changed')")"
  stdin="$(stdin_payload last_assistant_message="$LONG_MSG" transcript_path="$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
}
