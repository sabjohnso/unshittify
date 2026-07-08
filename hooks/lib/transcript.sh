#!/usr/bin/env bash
# Shared transcript-parsing helpers for the Stop hooks. This file is sourced,
# never executed on its own. It is the single place that knows the raw JSONL
# transcript schema: where a turn begins and how tool_use events are shaped.
# Both enforce-prose-review.sh and enforce-code-review.sh depend on it so the
# schema lives in one place and the turn-boundary rule cannot drift between
# them.

# find_turn_start_line <transcript-file>
#
# Prints the 1-based line number of the last genuine user prompt: a user
# message whose content is a string, or an array of blocks none of which is a
# tool_result, and which is not an isMeta skill/system injection. Falls back
# to the last "type":"last-prompt" marker for transcripts with no recognizable
# prompt. Returns 1 (printing nothing) when neither is present; warns on
# stderr when the transcript is non-empty but has neither, since that is a
# schema anomaly rather than the ordinary "hook fired before any prompt was
# recorded" case.
#
# Anchoring on the genuine prompt rather than the marker is deliberate: the
# harness appends last-prompt markers out of chronological order, sometimes
# after the very tool calls that belong to the turn the marker names, so a
# marker-anchored search can skip a tool call (such as a review) that did run.
# jq emits one line per input object, so grep -n recovers the file line.
find_turn_start_line() {
  local transcript="$1"
  local line
  line=$(jq -r '
      if (.type == "user"
          and ((.isMeta // false) != true)
          and (((.message.content | type) == "string")
               or ((.message.content | type) == "array"
                   and (all(.message.content[]?; (.type? // "") != "tool_result")))))
      then "PROMPT" else "." end' "$transcript" 2>/dev/null \
    | grep -n '^PROMPT$' | tail -1 | cut -d: -f1)

  if [ -z "$line" ]; then
    line=$(grep -n '"type":"last-prompt"' "$transcript" | tail -1 | cut -d: -f1)
  fi

  if [ -z "$line" ]; then
    if [ -s "$transcript" ]; then
      echo "transcript: warning: no user prompt or last-prompt marker in non-empty transcript: ${transcript}" >&2
    fi
    return 1
  fi
  printf '%s\n' "$line"
}

# tool_use_events_since_turn_start <transcript-file>
#
# Prints one compact JSON object per tool_use event from the turn start
# onward, each shaped {name, skill, subagent_type} (skill/subagent_type null
# when not applicable to that tool). Consumers filter this shape instead of
# re-deriving it from the raw transcript. Prints nothing (and, on a genuine
# jq parse failure, warns on stderr instead of silently reporting zero events)
# when no turn start is found.
tool_use_events_since_turn_start() {
  local transcript="$1"
  local start_line
  start_line=$(find_turn_start_line "$transcript") || return 0

  local events jq_status=0
  events=$(tail -n +"$start_line" "$transcript" \
    | jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") |
        {name, skill: (.input.skill // null), subagent_type: (.input.subagent_type // null)}' \
        2>&1) || jq_status=$?

  if [ "$jq_status" -ne 0 ]; then
    echo "transcript: warning: failed to parse tool_use events (jq exit ${jq_status}): ${events}" >&2
    return 0
  fi

  printf '%s\n' "$events"
}
