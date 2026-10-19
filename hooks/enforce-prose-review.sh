#!/usr/bin/env bash
# Stop hook. It blocks the end of the turn when the final assistant message
# is substantial prose and no call to the communication:prose-reviewer agent
# occurred after the last message from the user.
set -euo pipefail

MIN_WORDS=50
# The agent that satisfies this check. The match is on the exact
# subagent_type name, not on a substring. A near miss such as
# "communication:prose-reviewer-preview" does not count. The name carries the
# plugin prefix exactly as the transcript records it. The harness stores an
# agent's subagent_type as communication:prose-reviewer, not as the bare
# prose-reviewer. Keep this value equal to REVIEW_AGENT in
# confirm-git-commit-push.sh. The two hooks apply the same prose-review policy
# at two moments, the end of the turn and the time of the commit. A rename
# must change both.
REVIEW_AGENT="communication:prose-reviewer"

# shellcheck source=lib/transcript.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/transcript.sh"

# stop_hook_active_or_unreadable <input-json>
#
# Prints the stop_hook_active flag and succeeds. When the payload is not a
# JSON object, it prints nothing and fails.
#
# The shape check and the first field read are one jq pass, because both run
# on every turn. The field readers below are bare `jq -r '.field'` calls.
# When the payload is not an object, the assignments that take their output
# abort the script under `set -e`. The hook then exits with a nonzero status
# and prints no decision, so the turn ends with no judgement and only jq's
# parse error as a trace. A check at the start turns that crash into a
# deliberate verdict. Unreadable input is evidence that the hook cannot
# judge. This hook stays silent in that case, as transcript_judgeable does.
# It does not block on evidence it cannot read. A separate jq process for the
# validation costs as much as every other jq call this hook makes.
stop_hook_active_or_unreadable() {
  local flag
  flag=$(printf '%s' "$1" | jq -r 'if type == "object" then (.stop_hook_active // false | tostring) else empty end' 2>/dev/null)
  # An empty result is the only unreadable signal available here. jq -e
  # reports a payload whose flag is legitimately false as a failure, because
  # -e keys its exit status on the output value and not on the parse.
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
# The number of words in the message after the removal of its code. MIN_WORDS
# is calibrated for prose, so the hook must not measure code against it. A
# response that is one fenced block of eighty tokens has no prose to review.
# A count of those tokens demanded a prose review of a diff.
#
# Inline spans go too, for the same reason. An identifier such as
# `missing_reviews_for_transcript "$transcript" "$start_line"` is three words
# of code inside a sentence.
prose_word_count() {
  printf '%s\n' "$1" | strip_code | wc -w
}

# strip_code
#
# Filter. It drops every line between a ``` or ~~~ fence, the fence lines
# themselves, and every inline span on the lines that remain.
#
# An unterminated fence runs to the end of the message. The harness often
# truncates a long final message inside a block, so the closing fence is
# often absent. The tail of a cut-off block is not prose.
#
# One awk, not an awk and a sed. This runs on the Stop path, and the user
# waits on that path at the end of every turn.
strip_code() {
  awk '
    /^[[:space:]]*(```|~~~)/ { inside = !inside; next }
    !inside { gsub(/`[^`]*`/, ""); print }
  '
}

# unreviewed_prose_word_count <message-text> <transcript-file>
#
# Prints the prose word count of the message when the turn must be blocked.
# That is the case when the message is substantial prose and no REVIEW_AGENT
# call appears at or after the start of the turn. Otherwise it prints
# nothing. The whole decision is in this function and not in main. Thus the
# tests can run it directly against synthetic transcript fixtures, not only
# end to end through stdin.
unreviewed_prose_word_count() {
  local message="$1"
  local transcript="$2"
  local word_count start_line

  word_count=$(prose_word_count "$message")
  [ "$word_count" -ge "$MIN_WORDS" ] || return 0
  transcript_judgeable "$transcript" || return 0

  # No genuine user prompt and no fallback marker means that there is no turn
  # to judge. Stay silent. find_turn_start_line holds the turn-boundary rule.
  # The other hooks share it, so it cannot drift. The boundary is computed
  # once and used again for the checks below.
  start_line=$(find_turn_start_line "$transcript") || return 0

  # The brief-turn opt-out. See turn_requests_brevity in lib/transcript.sh.
  if turn_requests_brevity "$transcript" "$start_line"; then
    return 0
  fi

  # agent_invoked_since_line holds the exact-name match rule. The match is on
  # the whole name, so a near miss such as
  # "communication:prose-reviewer-preview" does not satisfy the requirement.
  # confirm-git-commit-push.sh shares the rule.
  if agent_invoked_since_line "$transcript" "$start_line" "$REVIEW_AGENT"; then
    return 0
  fi

  printf '%s\n' "$word_count"
}

# block_decision_json <word-count>
#
# Takes the output of unreviewed_prose_word_count, which can be empty. Prints
# the {"decision":"block", reason:...} JSON object on stdout. Prints nothing
# when there is nothing to block.
block_decision_json() {
  local word_count="$1"
  if [ -z "$word_count" ]; then
    return 0
  fi

  jq -n --arg reason "This response is substantial prose (${word_count} words), and the ${REVIEW_AGENT} agent did not review it this turn. Delegate the draft to the ${REVIEW_AGENT} subagent, apply the confirmed fixes, and send the corrected text." \
    '{decision:"block", reason:$reason}'
}

main() {
  local input
  input=$(cat)

  local stop_active
  if ! stop_active=$(stop_hook_active_or_unreadable "$input"); then
    echo "enforce-prose-review: warning: the stdin payload is not a JSON object. The check is skipped." >&2
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
