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

# stop_hook_active_or_unreadable <input-json>
#
# Prints the stop_hook_active flag and succeeds, or prints nothing and fails
# when the payload is not a JSON object.
#
# The shape check and the first field read are one jq pass because both run on
# every turn. The field readers below are bare `jq -r '.field'` calls, and the
# assignments that take their output ABORT the script under `set -e` when the
# payload is not an object - the hook then exits nonzero having printed no
# decision, so the turn ends unjudged with jq's parse error as its only trace.
# Checking up front turns that crash into a deliberate verdict: unreadable
# input is evidence the hook cannot judge, and this hook (like
# transcript_judgeable) stays silent rather than block on evidence it cannot
# read. Validating in a jq process of its own cost as much again as every
# other jq call this hook makes.
stop_hook_active_or_unreadable() {
  local flag
  flag=$(printf '%s' "$1" | jq -r 'if type == "object" then (.stop_hook_active // false | tostring) else empty end' 2>/dev/null)
  # An empty result is the only unreadable signal available here: jq -e would
  # report a payload whose flag is legitimately false as a failure, since -e
  # keys its exit status on the output value rather than on the parse.
  [ -n "$flag" ] || return 1
  printf '%s' "$flag"
}

transcript_path_from() {
  printf '%s' "$1" | jq -r '.transcript_path // empty'
}

last_assistant_message_from() {
  printf '%s' "$1" | jq -r '.last_assistant_message // empty'
}

# prose_word_count <message-text>
#
# The number of words in the message once its code has been removed. MIN_WORDS
# is calibrated for prose, so code must not be measured against it: a response
# that is one fenced block of eighty tokens carries no prose to review, and
# counting those tokens demanded a prose review of a diff.
#
# Inline spans go too, and for the same reason - an identifier like
# `missing_reviews_for_transcript "$transcript" "$start_line"` is three words
# of code sitting in a sentence.
prose_word_count() {
  printf '%s\n' "$1" | strip_code | wc -w
}

# strip_code
#
# Filter. Drops every line between a ``` or ~~~ fence, the fence lines
# themselves, and every inline span on the lines that remain.
#
# An unterminated fence runs to the end of the message: the harness truncates
# a long final message mid-block often enough that the closing fence is
# routinely absent, and the tail of a cut-off block is no more prose than the
# rest of it.
#
# One awk rather than an awk and a sed. This runs on the Stop path, which the
# user waits on at the end of every turn.
strip_code() {
  awk '
    /^[[:space:]]*(```|~~~)/ { inside = !inside; next }
    !inside { gsub(/`[^`]*`/, ""); print }
  '
}

# unreviewed_prose_word_count <message-text> <transcript-file>
#
# Prints the message's prose word count when the turn must be blocked - the
# message is substantial prose and no REVIEW_AGENT invocation appears at or
# after the turn start - and prints nothing otherwise. Composing the whole
# decision here, rather than in main, is what lets the tests exercise it
# directly against synthetic transcript fixtures instead of only end-to-end
# through stdin.
unreviewed_prose_word_count() {
  local message="$1"
  local transcript="$2"
  local word_count start_line

  word_count=$(prose_word_count "$message")
  [ "$word_count" -ge "$MIN_WORDS" ] || return 0
  transcript_judgeable "$transcript" || return 0

  # No genuine user prompt (and no fallback marker) means there is no turn to
  # judge - stay silent. find_turn_start_line encapsulates the turn-boundary
  # rule, shared with the other hooks so it cannot drift; the boundary is
  # computed once and reused for the checks below.
  start_line=$(find_turn_start_line "$transcript") || return 0

  # The brief-turn opt-out; see turn_requests_brevity in lib/transcript.sh.
  if turn_requests_brevity "$transcript" "$start_line"; then
    return 0
  fi

  # agent_invoked_since_line encapsulates the exact-name match rule (whole-name
  # equality, so a near-miss like "communication:prose-reviewer-preview" does
  # not satisfy the requirement), shared with confirm-git-commit-push.sh.
  if agent_invoked_since_line "$transcript" "$start_line" "$REVIEW_AGENT"; then
    return 0
  fi

  printf '%s\n' "$word_count"
}

# block_decision_json <word-count>
#
# Given the (possibly empty) output of unreviewed_prose_word_count, prints the
# {"decision":"block", reason:...} JSON object on stdout, or prints nothing if
# there is nothing to block.
block_decision_json() {
  local word_count="$1"
  if [ -z "$word_count" ]; then
    return 0
  fi

  jq -n --arg reason "This response is substantial prose (${word_count} words) and the ${REVIEW_AGENT} agent has not been invoked on it this turn. Delegate the draft to the ${REVIEW_AGENT} subagent, fix any flagged issues, and send the corrected text instead." \
    '{decision:"block", reason:$reason}'
}

main() {
  local input
  input=$(cat)

  local stop_active
  if ! stop_active=$(stop_hook_active_or_unreadable "$input"); then
    echo "enforce-prose-review: warning: stdin payload is not a JSON object; skipping the check" >&2
    exit 0
  fi

  if [ "$stop_active" = "true" ]; then
    exit 0
  fi

  local last_msg transcript
  last_msg=$(last_assistant_message_from "$input")
  transcript=$(transcript_path_from "$input")

  block_decision_json "$(unreviewed_prose_word_count "$last_msg" "$transcript")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
