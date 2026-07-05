#!/usr/bin/env bash
# Stop hook: blocks ending the turn if the final assistant message looks like
# substantial prose and communication:review-prose was never invoked since
# the user's last message.
set -euo pipefail

MIN_WORDS=50

input=$(cat)

# Don't re-block a stop that was itself forced by this hook - avoids an
# infinite loop if the model ignores the instruction.
stop_hook_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
if [ "$stop_hook_active" = "true" ]; then
  exit 0
fi

last_msg=$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

word_count=$(printf '%s' "$last_msg" | wc -w)

if [ "$word_count" -lt "$MIN_WORDS" ] || [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
  exit 0
fi

last_prompt_line=$(grep -n '"type":"last-prompt"' "$transcript" | tail -1 | cut -d: -f1 || true)
if [ -z "$last_prompt_line" ]; then
  exit 0
fi

reviewed=$(tail -n +"$last_prompt_line" "$transcript" \
  | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill // empty' 2>/dev/null \
  | grep -ci 'review-prose' || true)

if [ "$reviewed" -eq 0 ]; then
  jq -n --arg reason "This response is substantial prose (${word_count} words) and communication:review-prose has not been invoked on it this turn. Run the review-prose skill against the draft, fix any flagged issues, and send the corrected text instead." \
    '{decision:"block", reason:$reason}'
fi
