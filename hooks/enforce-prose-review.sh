#!/usr/bin/env bash
# Stop hook: blocks ending the turn if the final assistant message looks like
# substantial prose and communication:review-prose was never invoked since
# the user's last message.
set -euo pipefail

MIN_WORDS=50
# The skill that satisfies this check, matched by exact name (not substring):
# a near-miss like "communication:review-prose-preview" must not count.
REVIEW_SKILL="communication:review-prose"

# shellcheck source=lib/transcript.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/transcript.sh"

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

# No genuine user prompt (and no fallback marker) means there is no turn to
# judge - stay silent. find_turn_start_line encapsulates the turn-boundary
# rule, shared with enforce-code-review.sh so the two cannot drift.
find_turn_start_line "$transcript" >/dev/null || exit 0

# Count exact-name invocations of the review skill among this turn's tool_use
# events. grep -Fxc is a whole-line match, so a near-miss like
# "communication:review-prose-preview" does not satisfy the requirement.
reviewed=$(tool_use_events_since_turn_start "$transcript" \
  | jq -r 'select(.name=="Skill") | .skill // empty' 2>/dev/null \
  | grep -Fxc "$REVIEW_SKILL" || true)

if [ "$reviewed" -eq 0 ]; then
  jq -n --arg reason "This response is substantial prose (${word_count} words) and ${REVIEW_SKILL} has not been invoked on it this turn. Run the ${REVIEW_SKILL} skill against the draft, fix any flagged issues, and send the corrected text instead." \
    '{decision:"block", reason:$reason}'
fi
