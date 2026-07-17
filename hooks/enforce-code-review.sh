#!/usr/bin/env bash
# Stop hook: blocks ending the turn if code was written or edited this turn
# (Edit/Write/NotebookEdit tool calls since the user's last message) but the
# required reviews were not all invoked since that same point. The set of
# required reviews is the REQUIRED_REVIEWS table below - add a line there to
# require a new review, no other code changes needed.
set -euo pipefail

# Fully-qualified skill-name|agent-name pairs; either satisfies the
# requirement. Both carry the plugin prefix exactly as the transcript records
# them - the harness stores an agent's subagent_type as development:tdd-reviewer,
# not the bare tdd-reviewer, so the agent name must be qualified to match.
REQUIRED_REVIEWS=(
  "development:review-tdd|development:tdd-reviewer"
  "development:review-nst|development:nst-reviewer"
  "development:review-property-tests|development:property-test-reviewer"
  "development:review-efficiency|development:efficiency-reviewer"
)

CODE_CHANGE_TOOL_NAMES='^(Edit|Write|NotebookEdit)$'

# shellcheck source=lib/transcript.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/transcript.sh"

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

# The turn boundary and the tool_use event schema live in the shared library
# (find_turn_start_line, tool_use_events_since_turn_start), so this hook and
# enforce-prose-review.sh agree on where a turn begins and how events are
# shaped.

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
      echo "${skill_name} (skill) or ${agent_name} (agent)"
    fi
  done
}

# missing_reviews_for_transcript <transcript-file>
#
# Composes tool_use_events_since_turn_start + code_was_edited +
# missing_reviews against a real transcript file, so this single function is
# what tests exercise directly with synthetic transcript fixtures instead of
# only end-to-end via stdin. Prints nothing if no code was edited since the
# turn start, or if all required reviews were satisfied.
missing_reviews_for_transcript() {
  local transcript="$1"
  local events
  events=$(tool_use_events_since_turn_start "$transcript")
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
