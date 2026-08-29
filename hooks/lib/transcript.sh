#!/usr/bin/env bash
# Shared transcript-parsing helpers for the hook scripts. This file is
# sourced, never executed on its own. It is the single place that knows the
# raw JSONL transcript schema: where a turn begins, how tool_use events are
# shaped, and what counts as an exact agent-invocation match.
# enforce-prose-review.sh, enforce-code-review.sh, and
# confirm-git-commit-push.sh all depend on it so the schema lives in one
# place and the turn-boundary and name-matching rules cannot drift between
# them.

# transcript_judgeable <transcript-path>
#
# Succeeds when the path names an existing transcript file that can be judged
# at all. Hooks degrade (skip their transcript-based check) when this fails,
# rather than blocking on evidence they cannot read.
transcript_judgeable() {
  [ -n "$1" ] && [ -f "$1" ]
}

# find_turn_start_line <transcript-file>
#
# Prints the 1-based line number of the last genuine user prompt: a user
# message whose content is a string, or an array of blocks none of which is a
# tool_result, which is not an isMeta skill/system injection, and which the
# harness did not write on the user's behalf. Falls back to the last
# "type":"last-prompt" marker for transcripts with no recognizable prompt.
# Returns 1 (printing nothing) when neither is present; warns on stderr when
# the transcript is non-empty but has neither, since that is a schema anomaly
# rather than the ordinary "hook fired before any prompt was recorded" case.
#
# Anchoring on the genuine prompt rather than the marker is deliberate: the
# harness appends last-prompt markers out of chronological order, sometimes
# after the very tool calls that belong to the turn the marker names, so a
# marker-anchored search can skip a tool call (such as a review) that did run.
# jq emits one line per input object, so grep -n recovers the file line.
#
# HARNESS INJECTIONS ARE EXCLUDED, and this is the load-bearing part. The
# harness records several of its OWN messages in the user role with plain
# string content, structurally identical to something the user typed. Every
# one of them that counts as a boundary discards the evidence of everything
# the assistant did earlier in the same turn.
#
# The task-notification case is the one that broke a real guarantee rather
# than a hypothetical one. When a subagent is delegated asynchronously, the
# harness writes its completion notification AFTER the Agent tool_use that
# spawned it. A boundary placed on that notification therefore lands after
# the delegation, so enforce-prose-review.sh could never see a review it had
# just demanded - and every review in this harness is delegated that way.
# Measured on a live transcript: lines 198 and 221 of one session were
# task-notifications that qualified as boundaries, sitting immediately after
# the communication:prose-reviewer invocations they were reporting on.
#
# Two rules, in order of reliability:
#
#   structural   origin.kind names who authored the message. "human" is a
#                genuine prompt; anything else ("task-notification") is the
#                harness. promptSource == "system" says the same thing.
#                Both fields are ABSENT in older transcripts, so their
#                absence must stay permissive - the fallback below is what
#                covers those.
#   content      A message opening with a harness wrapper tag
#                (<task-notification>, <command-name>, <local-command-stdout>,
#                <system-reminder>) is an injection whatever its metadata
#                says. This is the rule that catches transcripts predating
#                the origin field, and slash-command markers, which carry no
#                origin field even now.
#
# Both rules only ever REJECT a candidate boundary, moving the turn start
# earlier. That direction is the safe one for the enforce hooks: an earlier
# boundary can only make them see more of the turn's tool calls, never
# fewer, so a misjudgement costs a redundant review rather than a missed one.
find_turn_start_line() {
  local transcript="$1"
  local line
  line=$(jq -r '
      def content_text:
        if (.message.content | type) == "string" then .message.content
        else ((.message.content[]? | select(.type? == "text") | .text) // "")
        end;
      def harness_authored:
        ((.origin.kind? // "human") != "human")
        or ((.promptSource? // "") == "system")
        or (content_text | ltrimstr("\n")
            | startswith("<task-notification>")
              or startswith("<command-name>")
              or startswith("<local-command-stdout>")
              or startswith("<system-reminder>"));
      if (.type == "user"
          and ((.isMeta // false) != true)
          and (harness_authored | not)
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

# tool_use_events_since_line <transcript-file> <start-line>
#
# Prints one compact JSON object per tool_use event from the given 1-based
# line onward, each shaped {name, skill, subagent_type, command} (every field
# but name null when not applicable to that tool). Consumers filter this
# shape instead of re-deriving it from the raw transcript. command carries a
# Bash call's command string, since the tool NAME alone cannot say whether a
# Bash call read a file or rewrote one. Takes a precomputed boundary so
# a caller that already ran find_turn_start_line does not pay a second
# full-transcript scan. On a jq parse failure, warns on stderr instead of
# silently reporting zero events.
tool_use_events_since_line() {
  local transcript="$1"
  local start_line="$2"

  local events jq_status=0
  events=$(tail -n +"$start_line" "$transcript" \
    | jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") |
        {name, skill: (.input.skill // null), subagent_type: (.input.subagent_type // null),
         command: (.input.command // null)}' \
        2>&1) || jq_status=$?

  if [ "$jq_status" -ne 0 ]; then
    echo "transcript: warning: failed to parse tool_use events (jq exit ${jq_status}): ${events}" >&2
    return 0
  fi

  printf '%s\n' "$events"
}

# tool_use_events_since_turn_start <transcript-file>
#
# tool_use_events_since_line anchored at the turn start. Prints nothing when
# no turn start is found.
tool_use_events_since_turn_start() {
  local transcript="$1"
  local start_line
  start_line=$(find_turn_start_line "$transcript") || return 0
  tool_use_events_since_line "$transcript" "$start_line"
}

# agent_invoked_since_line <transcript-file> <start-line> <agent-name>
#
# Succeeds when a tool_use event at or after start-line names <agent-name> as
# its exact subagent_type. Whole-name equality (grep -Fx): a near-miss like
# "<agent-name>-preview" never counts, and neither does a skill invocation
# carrying the same name - only a subagent satisfies this.
agent_invoked_since_line() {
  local transcript="$1"
  local start_line="$2"
  local agent="$3"

  local count
  count=$(tool_use_events_since_line "$transcript" "$start_line" \
    | jq -r '.subagent_type // empty' \
    | grep -Fxc "$agent") || true
  [ "${count:-0}" -gt 0 ]
}
