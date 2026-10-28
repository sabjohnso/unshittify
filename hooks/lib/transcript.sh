#!/usr/bin/env bash
# Shared transcript-parsing helpers for the hook scripts. A hook sources this
# file. Nothing executes it on its own. It is the single place that knows the
# raw JSONL transcript schema: where a turn starts, the shape of a tool_use
# event, and what counts as an exact agent-call match.
# enforce-prose-review.sh, enforce-code-review.sh, and
# confirm-git-commit-push.sh all depend on it. Thus the schema is in one
# place, and the turn-boundary rule and the name-match rule cannot drift
# between the hooks. The file also holds one piece of shared Stop-hook
# POLICY, turn_requests_brevity. It is beside the schema helpers for the same
# no-drift reason. See its comment.

# Every scan below reads the transcript RAW, one line at a time, and parses
# each line inside jq. It does not let jq read the file as JSON. Two
# properties follow, and both are necessary:
#
#   partial reads  The harness appends to the transcript while a hook reads
#                  it, so the final line is often half-written. A parse
#                  failure must cost that one line and no more. When jq
#                  aborts after it has emitted events, and those events are
#                  then discarded, enforce-code-review.sh reads that nothing
#                  was edited. That is a fail-open result on the most common
#                  input there is.
#   position       input_line_number is then the line number of the record
#                  itself, so each scan reports the positions it found.
#                  Nothing downstream counts lines a second time, so no
#                  second count can drift from the first. It counts the
#                  newlines consumed, so a final line that the harness has
#                  not finished is numbered one low. That reports a boundary
#                  EARLIER than the record, and that direction costs a
#                  redundant review and not a missed one.
#
# jq can report a skipped line only through its own output. A skipped line
# arrives on stdout as this marker, and drop_malformed_lines converts it to a
# warning. The conversion is mandatory. A caller reads a scan's stdout as
# events, so a diagnostic left there becomes a fabricated event.
MALFORMED_MARKER='MALFORMED'

# jq definitions that the scans share. `record` is null for a line that is
# not JSON and for a line that is the literal `null`. Neither is a transcript
# record, so the callers do not need to tell them apart.
TRANSCRIPT_JQ_PRELUDE='
  def record: [fromjson?] | first;
'

# jq definitions for a user record: its text, whether the harness wrote it,
# and whether it is a genuine prompt. There is one copy. Both
# scan_boundary_candidates and turn_prompt_text use it, so the two can never
# disagree about what counts as a prompt. That disagreement is the defect
# that the validator's read_markdown cures in its own domain. See
# scan_boundary_candidates for the reason behind each harness_authored rule.
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
# Filter. It copies the output of a scan, except for the malformed-line
# markers. It collects those into a single warning on stderr that names the
# skipped lines.
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
# Succeeds when the path names an existing transcript file. When this fails,
# a hook skips its transcript-based check. It does not block on evidence it
# cannot read.
transcript_judgeable() {
  [ -n "$1" ] && [ -f "$1" ]
}

# find_turn_start_line <transcript-file>
#
# Prints the 1-based line number of the last genuine user prompt. A genuine
# prompt is a user message whose content is a string, or an array of blocks
# with no tool_result. It is not an isMeta skill or system injection, and the
# harness did not write it for the user. When the transcript has no such
# prompt, the function falls back to the last last-prompt record. When
# neither is present, it returns 1 and prints nothing. When the transcript
# is not empty and has neither, it warns on stderr. That is a schema anomaly,
# not the ordinary case of a hook that fired before the first prompt.
#
# The anchor is the genuine prompt, not the marker, and that is deliberate.
# The harness appends last-prompt markers out of chronological order,
# sometimes after the tool calls that belong to the turn the marker names. A
# search anchored on the marker can skip a tool call, such as a review, that
# did run.
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
# Prints one line per record that can start a turn: "PROMPT <line>" for a
# genuine user prompt and "MARKER <line>" for a last-prompt record. Each
# record gets exactly one verdict, whatever the record holds. A user message
# can carry several text blocks. A classifier that spoke once per block moved
# every later line number forward and put the boundary after the tool calls
# of the turn.
#
# The function recognizes the last-prompt record by its parsed type, never by
# the text {"type":"last-prompt"} in the line. That text occurs inside any
# record that embeds a transcript. The tests and the hook development in this
# repository produce such records all the time. A match on that text moves
# the boundary FORWARD and hides the events of the turn from the enforce
# hooks.
#
# HARNESS INJECTIONS ARE EXCLUDED. This is the necessary part. The harness
# records several of its OWN messages in the user role with plain string
# content. In structure, they are identical to a message the user typed.
# Each one that counts as a boundary discards the evidence of all that the
# assistant did earlier in the same turn.
#
# The task-notification case broke a real guarantee, not a hypothetical one.
# When the model delegates a subagent asynchronously, the harness writes the
# completion notification AFTER the Agent tool_use that started the subagent.
# A boundary on that notification is after the delegation, so
# enforce-prose-review.sh could never see a review it had just demanded. And
# every review in this harness is delegated that way. Measured on a live
# transcript: lines 198 and 221 of one session were task-notifications that
# qualified as boundaries. Each sat immediately after the
# communication:prose-reviewer call that it reported on.
#
# Two rules, in order of reliability:
#
#   structural   origin.kind names the author of the message. "human" is a
#                genuine prompt. All other values ("task-notification") are
#                the harness. promptSource == "system" says the same thing.
#                Both fields are ABSENT in older transcripts, so their
#                absence must stay permissive. The fallback below covers
#                those transcripts.
#   content      A message that opens with a harness wrapper tag
#                (<task-notification>, <command-name>, <local-command-stdout>,
#                <system-reminder>) is an injection, whatever its metadata
#                says. This rule catches transcripts from before the origin
#                field, and slash-command markers, which carry no origin
#                field even now. The rule trims ALL leading whitespace before
#                it looks for the tag, not one newline. ltrimstr removes its
#                argument exactly once, so a second newline or a leading
#                space left the tag unseen, and the injection then acted as a
#                boundary. That moved the boundary forward, past the
#                delegation, in the one direction this rule must never move
#                it.
#
# Both rules only REJECT a candidate boundary, so they move the turn start
# earlier. That direction is the safe one for the enforce hooks. An earlier
# boundary can only make them see more of the tool calls of the turn, never
# fewer. A wrong judgement costs a redundant review and not a missed one.
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
# line to the end. Each object has the shape {name, skill, subagent_type,
# command, file_path}. Every field but name is null when it does not apply to
# that tool. Consumers filter this shape. They do not derive it from the raw
# transcript again. command carries the command string of a Bash call,
# because the tool NAME alone cannot say whether a Bash call read a file or
# rewrote one. file_path carries the file of an Edit or a Write call, or the
# notebook_path of a NotebookEdit call, for the same reason: the name alone
# cannot say whether the file is in the tree under review. The
# function takes a precomputed boundary, so a caller that already ran
# find_turn_start_line does not pay a second full-transcript scan. A line
# that jq cannot read costs that line alone. The function reports every
# event before and after it.
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
               command: (.input.command // null),
               file_path: (.input.file_path // .input.notebook_path // null)}
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
# its exact subagent_type. The match is on the whole name (grep -Fx). A near
# miss such as "<agent-name>-preview" never counts. A skill call with the
# same name does not count. Only a subagent satisfies this check.
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
# user prompt. Otherwise it prints nothing. A last-prompt marker fallback
# carries no text that the user typed, and a line that jq cannot parse
# carries no evidence at all. The function takes the precomputed boundary,
# as tool_use_events_since_line does. A caller that already ran
# find_turn_start_line pays one single-line read and not a second
# full-transcript scan.
turn_prompt_text() {
  local transcript="$1"
  local start_line="$2"

  # The q makes sed stop at the target line. A bare `Np` reads to the end of
  # the file, and that is the second full scan that the comment above
  # forbids.
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
# "briefly". Leading whitespace is ignored. This is the one-turn opt-out of
# the user from the Stop hooks. It is shared POLICY, not schema, and it is in
# this file for the same reason as the boundary rule. enforce-prose-review.sh
# and enforce-code-review.sh must stand down on exactly the same turns. Two
# private copies of the prefix rule would drift, as the duplicated prose of
# this repository drifts.
#
# Only positive evidence opts out. A marker-based boundary, a missing prompt,
# and an unparseable line all fail this check. Thus a transcript that the
# hooks cannot read keeps the guarantee that each hook made about it. The
# word must END after "briefly". A letter after it ("Brieflyish") makes a
# different word, and a false opt-out removes a gate that the user did not
# ask to remove.
turn_requests_brevity() {
  local transcript="$1"
  local start_line="$2"

  local text
  text=$(turn_prompt_text "$transcript" "$start_line")
  [[ "$text" =~ ^[[:space:]]*[Bb]riefly([^[:alpha:]]|$) ]]
}
