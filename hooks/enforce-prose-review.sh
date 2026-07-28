#!/usr/bin/env bash
# Stop hook: blocks ending the turn if the final assistant message looks like
# substantial prose and the communication:prose-reviewer agent was never
# invoked since the user's last message.
set -euo pipefail

MIN_WORDS=50
# The agent that satisfies this check, matched by exact subagent_type name
# (not substring): a near-miss like "communication:prose-reviewer-preview"
# must not count. The name carries the plugin prefix exactly as the transcript
# records it - the harness stores an agent's subagent_type as
# communication:prose-reviewer, not the bare prose-reviewer. Kept in lockstep
# with confirm-git-commit-push.sh's REVIEW_AGENT - the two hooks enforce the
# same prose-review policy at different moments (turn end vs commit time), so
# a rename must change both.
REVIEW_AGENT="communication:prose-reviewer"

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

if [ "$word_count" -lt "$MIN_WORDS" ] || ! transcript_judgeable "$transcript"; then
  exit 0
fi

# No genuine user prompt (and no fallback marker) means there is no turn to
# judge - stay silent. find_turn_start_line encapsulates the turn-boundary
# rule, shared with the other hooks so it cannot drift; the boundary is
# computed once and reused for the invocation check below.
start_line=$(find_turn_start_line "$transcript") || exit 0

# agent_invoked_since_line encapsulates the exact-name match rule (whole-name
# equality, so a near-miss like "communication:prose-reviewer-preview" does
# not satisfy the requirement), shared with confirm-git-commit-push.sh.
if ! agent_invoked_since_line "$transcript" "$start_line" "$REVIEW_AGENT"; then
  jq -n --arg reason "This response is substantial prose (${word_count} words) and the ${REVIEW_AGENT} agent has not been invoked on it this turn. Delegate the draft to the ${REVIEW_AGENT} subagent, fix any flagged issues, and send the corrected text instead." \
    '{decision:"block", reason:$reason}'
fi
