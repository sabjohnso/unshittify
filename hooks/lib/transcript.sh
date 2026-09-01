#!/usr/bin/env bash
# Shared transcript-parsing helpers for the hook scripts. This file is
# sourced, never executed on its own. It is the single place that knows the
# raw JSONL transcript schema: where a turn begins, how tool_use events are
# shaped, and what counts as an exact agent-invocation match.
# enforce-prose-review.sh, enforce-code-review.sh, and
# confirm-git-commit-push.sh all depend on it so the schema lives in one
# place and the turn-boundary and name-matching rules cannot drift between
# them. It also carries one piece of shared Stop-hook POLICY,
# turn_requests_brevity, kept beside the schema helpers for the same
# no-drift reason - see its docstring.

# Every scan below reads the transcript RAW, one line at a time, and parses
# each line inside jq instead of letting jq read the file as JSON. Two
# properties follow, and both are load-bearing:
#
#   partial reads  The harness appends to the transcript while a hook reads
#                  it, so the final line is routinely half-written. A parse
#                  failure must cost that one line and no more: jq aborting
#                  after it has already emitted events, with those events
#                  then discarded, tells enforce-code-review.sh that nothing
#                  was edited - fail-open, on the commonest input there is.
#   position       input_line_number is then the line number of the record
#                  itself, so each scan reports the positions it found.
#                  Nothing downstream counts lines a second time, so no
#                  second count can drift out of step with the first. It
#                  counts newlines consumed, so a final line the harness has
#                  not finished writing is numbered one low - which reports
#                  a boundary EARLIER than the record sits, the direction
#                  that costs a redundant review rather than a missed one.
#
# jq has no way to report a line it skipped except through its own output, so
# a skipped line arrives on stdout as this marker and drop_malformed_lines
# converts it to a warning. The conversion cannot be skipped: a scan's stdout
# is read by its caller as events, so a diagnostic left there becomes a
# fabricated event.
MALFORMED_MARKER='MALFORMED'

# jq definitions shared by the scans. `record` is null both for a line that
# is not JSON and for a line that is the literal `null`; neither is a
# transcript record, so the callers need not tell them apart.
TRANSCRIPT_JQ_PRELUDE='
  def record: [fromjson?] | first;
'

# jq definitions for reading a user record: its text, whether the harness
# authored it, and whether it is a genuine prompt. One copy, used by both
# scan_boundary_candidates and turn_prompt_text, so the two can never
# disagree about what counts as a prompt - the disease the validator's
# read_markdown exists to cure in its own domain. See
# scan_boundary_candidates for why each harness_authored rule exists.
TRANSCRIPT_JQ_PROMPT_DEFS='
  def content_text:
    if (.message.content | type) == "string" then .message.content
    else [.message.content[]? | select(.type? == "text") | .text] | join("\n")
    end;
  def harness_authored:
    ((.origin.kind? // "human") != "human")
    or ((.promptSource? // "") == "system")
    or (content_text | sub("^[[:space:]]+"; "")
        | startswith("<task-notification>")
          or startswith("<command-name>")
          or startswith("<local-command-stdout>")
          or startswith("<system-reminder>"));
  def genuine_prompt:
    .type == "user"
    and ((.isMeta // false) != true)
    and (harness_authored | not)
    and (((.message.content | type) == "string")
         or ((.message.content | type) == "array"
             and (all(.message.content[]?; (.type? // "") != "tool_result"))));
'

# drop_malformed_lines <what-the-scan-was-doing>
#
# Filter. Copies a scan's output through, except for the malformed-line
# markers, which are collected into a single warning on stderr naming the
# lines that were skipped.
drop_malformed_lines() {
  local context="$1"
  local line
  local skipped=()

  while IFS= read -r line; do
    case "$line" in
      "${MALFORMED_MARKER} "*) skipped+=("${line#* }") ;;
      *) printf '%s\n' "$line" ;;
    esac
  done

  if [ "${#skipped[@]}" -gt 0 ]; then
    echo "transcript: warning: ${context}: skipped ${#skipped[@]} malformed line(s) at ${skipped[*]}" >&2
  fi
}

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
# last-prompt record for transcripts with no recognizable prompt. Returns 1
# (printing nothing) when neither is present; warns on stderr when the
# transcript is non-empty but has neither, since that is a schema anomaly
# rather than the ordinary "hook fired before any prompt was recorded" case.
#
# Anchoring on the genuine prompt rather than the marker is deliberate: the
# harness appends last-prompt markers out of chronological order, sometimes
# after the very tool calls that belong to the turn the marker names, so a
# marker-anchored search can skip a tool call (such as a review) that did run.
find_turn_start_line() {
  local transcript="$1"
  local candidates line

  candidates=$(scan_boundary_candidates "$transcript")

  line=$(printf '%s\n' "$candidates" | grep '^PROMPT ' | tail -1 | cut -d' ' -f2)
  if [ -z "$line" ]; then
    line=$(printf '%s\n' "$candidates" | grep '^MARKER ' | tail -1 | cut -d' ' -f2)
  fi

  if [ -z "$line" ]; then
    if [ -s "$transcript" ]; then
      echo "transcript: warning: no user prompt or last-prompt marker in non-empty transcript: ${transcript}" >&2
    fi
    return 1
  fi
  printf '%s\n' "$line"
}

# scan_boundary_candidates <transcript-file>
#
# Prints one line per record that could start a turn: "PROMPT <line>" for a
# genuine user prompt and "MARKER <line>" for a last-prompt record. Exactly
# one verdict per record, whatever the record contains - a user message may
# carry several text blocks, and a classifier that spoke once per block would
# shift every line number after it forward, landing the boundary past the
# turn's own tool calls.
#
# The last-prompt record is recognised by its parsed type, never by the text
# {"type":"last-prompt"} appearing in the line. That text occurs inside any
# record that embeds a transcript - which this repository's own tests and
# hook development produce constantly - and matching one would move the
# boundary FORWARD, hiding the turn's events from the enforce hooks.
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
#                origin field even now. ALL leading whitespace is trimmed
#                before the tag is looked for, not one newline: ltrimstr
#                removes its argument exactly once, so a second newline or a
#                leading space left the tag unseen and the injection acting
#                as a boundary - forward, past the delegation, the one
#                direction this rule must never move the boundary.
#
# Both rules only ever REJECT a candidate boundary, moving the turn start
# earlier. That direction is the safe one for the enforce hooks: an earlier
# boundary can only make them see more of the turn's tool calls, never
# fewer, so a misjudgement costs a redundant review rather than a missed one.
scan_boundary_candidates() {
  local transcript="$1"

  jq -R -r --arg malformed "$MALFORMED_MARKER" "${TRANSCRIPT_JQ_PRELUDE}${TRANSCRIPT_JQ_PROMPT_DEFS}"'
      record as $line
      | if ($line | type) != "object" then "\($malformed) \(input_line_number)"
        elif ($line | genuine_prompt) then "PROMPT \(input_line_number)"
        elif ($line | .type == "last-prompt") then "MARKER \(input_line_number)"
        else empty
        end' "$transcript" \
    | drop_malformed_lines "classifying the turn boundary in ${transcript}"
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
# full-transcript scan. A line jq cannot read costs that line alone; every
# event found before and after it is still reported.
tool_use_events_since_line() {
  local transcript="$1"
  local start_line="$2"

  local scanned jq_status=0
  scanned=$(tail -n +"$start_line" "$transcript" \
    | jq -R -r --arg malformed "$MALFORMED_MARKER" \
               --argjson offset "$((start_line - 1))" "${TRANSCRIPT_JQ_PRELUDE}"'
        record as $line
        | if ($line | type) != "object" then "\($malformed) \($offset + input_line_number)"
          else $line
            | select(.type == "assistant")
            | .message.content[]?
            | select(.type == "tool_use")
            | {name, skill: (.input.skill // null),
               subagent_type: (.input.subagent_type // null),
               command: (.input.command // null)}
            | tojson
          end') || jq_status=$?

  if [ "$jq_status" -ne 0 ]; then
    echo "transcript: warning: failed to parse tool_use events (jq exit ${jq_status})" >&2
  fi

  printf '%s\n' "$scanned" | drop_malformed_lines "reading tool_use events from ${transcript}"
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

# turn_prompt_text <transcript-file> <start-line>
#
# Prints the text of the record at start-line when that record is a genuine
# user prompt, and nothing otherwise: a last-prompt marker fallback carries
# no text the user typed, and a line jq cannot parse carries no evidence at
# all. Takes the precomputed boundary, like tool_use_events_since_line, so a
# caller that already ran find_turn_start_line pays one single-line read
# rather than a second full-transcript scan.
turn_prompt_text() {
  local transcript="$1"
  local start_line="$2"

  # The q makes sed stop at the target line; a bare `Np` would keep reading
  # to EOF and turn this into the second full scan the docstring rules out.
  sed -n "${start_line}{p;q}" "$transcript" \
    | jq -R -r "${TRANSCRIPT_JQ_PRELUDE}${TRANSCRIPT_JQ_PROMPT_DEFS}"'
        record as $line
        | if ($line | type) == "object" and ($line | genuine_prompt)
          then ($line | content_text)
          else empty
          end'
}

# turn_requests_brevity <transcript-file> <start-line>
#
# Succeeds when the genuine user prompt at start-line opens with "Briefly" or
# "briefly" (leading whitespace ignored) - the user's one-turn opt-out from
# the Stop hooks. This is shared POLICY rather than schema, and it lives here
# for the same reason the boundary rule does: enforce-prose-review.sh and
# enforce-code-review.sh must stand down on exactly the same turns, and two
# private copies of the prefix rule would drift the way this repository's
# duplicated prose keeps drifting.
#
# Only positive evidence opts out. A marker-based boundary, a missing prompt,
# or an unparseable line all fail this check, so a transcript the hooks
# cannot read keeps whatever guarantee each hook already made about it. The
# word must END after "briefly" - a following letter ("Brieflyish") is some
# other word, and a false opt-out here removes a gate the user never asked
# to remove.
turn_requests_brevity() {
  local transcript="$1"
  local start_line="$2"

  local text
  text=$(turn_prompt_text "$transcript" "$start_line")
  [[ "$text" =~ ^[[:space:]]*[Bb]riefly([^[:alpha:]]|$) ]]
}
