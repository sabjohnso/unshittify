#!/usr/bin/env bash
# Stop hook: blocks ending the turn if code was written or edited this turn
# (Edit/Write/NotebookEdit tool calls since the user's last message) but the
# required reviews were not all invoked since that same point. The set of
# required reviews is the REQUIRED_REVIEWS table below - add a line there to
# require a new review, no other code changes needed.
set -euo pipefail

# skill-name|agent-name pairs. Either satisfies the requirement.
REQUIRED_REVIEWS=(
  "development:review-tdd|tdd-reviewer"
  "development:review-nst|nst-reviewer"
  "development:review-property-tests|property-test-reviewer"
)

CODE_CHANGE_TOOL_NAMES='^(Edit|Write|NotebookEdit)$'

# stop_hook_active_from <input-json>
#
# Don't re-block a stop that was itself forced by this hook - avoids an
# infinite loop if the model ignores the instruction.
stop_hook_active_from() {
  printf '%s' "$1" | jq -r '.stop_hook_active // false'
}

transcript_path_from() {
  printf '%s' "$1" | jq -r '.transcript_path // empty'
}

# find_last_prompt_line <transcript-file>
#
# Prints the 1-based line number of the last "type":"last-prompt" marker in
# the transcript. Returns 1 (nothing printed) if no marker is present. Emits
# a stderr note when the transcript is non-empty but no marker was found,
# since that's a schema anomaly, not the ordinary "hook fired before any
# prompt was ever recorded" case - the two used to be silently identical.
find_last_prompt_line() {
  local transcript="$1"
  local line
  line=$(grep -n '"type":"last-prompt"' "$transcript" | tail -1 | cut -d: -f1)
  if [ -z "$line" ]; then
    if [ -s "$transcript" ]; then
      echo "enforce-code-review: warning: no last-prompt marker found in non-empty transcript: ${transcript}" >&2
    fi
    return 1
  fi
  printf '%s\n' "$line"
}

# tool_use_events_since_last_prompt <transcript-file>
#
# The single place that knows the raw JSONL transcript schema. Prints one
# compact JSON object per tool_use event found from the last "last-prompt"
# marker onward, each shaped as {name, skill, subagent_type} (skill/
# subagent_type are null when not applicable to that tool). Every other
# function in this script consumes this shape instead of re-deriving it
# from the raw transcript.
#
# Prints nothing (and, on a genuine parse failure, warns on stderr instead
# of silently reporting zero events) if no last-prompt marker is found.
tool_use_events_since_last_prompt() {
  local transcript="$1"
  local start_line
  start_line=$(find_last_prompt_line "$transcript") || return 0

  local events jq_status=0
  events=$(tail -n +"$start_line" "$transcript" \
    | jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") |
        {name, skill: (.input.skill // null), subagent_type: (.input.subagent_type // null)}' \
        2>&1) || jq_status=$?

  if [ "$jq_status" -ne 0 ]; then
    echo "enforce-code-review: warning: failed to parse transcript tool_use events (jq exit ${jq_status}): ${events}" >&2
    return 0
  fi

  printf '%s\n' "$events"
}

# code_was_edited <events-jsonl>
#
# True (exit 0) if any event's tool name is Edit/Write/NotebookEdit.
code_was_edited() {
  local events="$1"
  printf '%s\n' "$events" \
    | jq -r '.name // empty' \
    | grep -qE "$CODE_CHANGE_TOOL_NAMES"
}

# review_satisfied <events-jsonl> <skill-name> <agent-name>
#
# True (exit 0) if some event's skill exactly equals skill-name, or some
# event's subagent_type exactly equals agent-name. Exact-name equality, not
# substring matching: a skill merely named "development:review-tdd-summary"
# must not satisfy a "development:review-tdd" requirement.
#
# Slurps the events into one JSON array (-s) and evaluates a single
# any(...) expression so jq's -e exit-status reflects the match across the
# whole event list; without -s, jq's -e status is computed per input line
# in the JSONL stream, which silently gives the wrong answer once more than
# one event is present.
review_satisfied() {
  local events="$1" skill_name="$2" agent_name="$3"
  printf '%s\n' "$events" \
    | jq -e -s --arg s "$skill_name" --arg a "$agent_name" \
        'any(.[]; .skill == $s or .subagent_type == $a)' >/dev/null 2>&1
}

# missing_reviews <events-jsonl>
#
# Prints one line per required review (from REQUIRED_REVIEWS) that was not
# satisfied by the given events, in "<skill> (skill) or <agent> (agent)"
# form. Prints nothing if all required reviews were satisfied.
missing_reviews() {
  local events="$1"
  local entry skill_name agent_name
  for entry in "${REQUIRED_REVIEWS[@]}"; do
    skill_name="${entry%%|*}"
    agent_name="${entry##*|}"
    if ! review_satisfied "$events" "$skill_name" "$agent_name"; then
      echo "${skill_name} (skill) or development:${agent_name} (agent)"
    fi
  done
}

# missing_reviews_for_transcript <transcript-file>
#
# Composes find_last_prompt_line + tool_use_events_since_last_prompt +
# code_was_edited + missing_reviews against a real transcript file, so this
# single function is what tests exercise directly with synthetic transcript
# fixtures instead of only end-to-end via stdin. Prints nothing if no code
# was edited since the last prompt, or if all required reviews were
# satisfied.
missing_reviews_for_transcript() {
  local transcript="$1"
  local events
  events=$(tool_use_events_since_last_prompt "$transcript")
  code_was_edited "$events" || return 0
  missing_reviews "$events"
}

# block_decision_json <missing-lines>
#
# Given the (possibly empty) newline-separated output of missing_reviews,
# prints the {"decision":"block", reason:...} JSON object on stdout, or
# prints nothing if there is nothing missing.
block_decision_json() {
  local missing_lines="$1"
  if [ -z "$missing_lines" ]; then
    return 0
  fi

  local -a missing_array
  mapfile -t missing_array <<< "$missing_lines"

  local joined
  joined=$(printf ', %s' "${missing_array[@]}")
  joined=${joined:2}

  jq -n --arg reason "Code was written or edited this turn but the following required review skill(s) were not invoked: ${joined}. Run them against the diff, address any findings, and then stop." \
    '{decision:"block", reason:$reason}'
}

main() {
  local input
  input=$(cat)

  if [ "$(stop_hook_active_from "$input")" = "true" ]; then
    exit 0
  fi

  local transcript
  transcript=$(transcript_path_from "$input")
  if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
    exit 0
  fi

  block_decision_json "$(missing_reviews_for_transcript "$transcript")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
