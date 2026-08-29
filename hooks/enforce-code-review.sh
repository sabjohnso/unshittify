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

# Bash commands that modify a file. The tool name alone cannot answer this:
# Bash both reads and writes, and the harness's auto mode instructs the model
# to prefer sed and heredocs over the Edit tool outright, so a gate that
# watches only Edit/Write/NotebookEdit misses the path the model is actively
# told to take. Add a pattern here to widen detection - no other code changes
# needed.
#
# THIS LIST FAILS CLOSED, in the opposite direction to a permission check: a
# pattern that fires too eagerly costs one redundant review, while a write
# shape that is missing here costs the gate's whole guarantee. Where the two
# conflict, add the pattern.
BASH_WRITE_PATTERNS=(
  '(^|[[:space:];&|(])(sed|perl|ruby)[[:space:]][^;&|]*-i'   # in-place edit
  '(^|[[:space:];&|(])tee([[:space:]]|$)'
  '(^|[[:space:];&|(])(cp|mv|ln|install|truncate|touch|mkdir|rmdir|rm|shred)([[:space:]]|$)'
  '(^|[[:space:];&|(])(patch|dos2unix|unix2dos)([[:space:]]|$)'
  '(^|[[:space:];&|(])dd[[:space:]][^;&|]*of='
  '(^|[[:space:];&|(])git[[:space:]]+(apply|restore|checkout|revert|stash)([[:space:]]|$)'
  '(^|[[:space:];&|(])(chmod|chown|chgrp)([[:space:]]|$)'
  '>>?[[:space:]]*[^&[:space:]]'                             # redirection to a path
)

# Redirection targets that write nothing a review could cover, stripped from
# a command before the patterns above are matched against it. The redirection
# pattern is otherwise so broad that a routine `make >/dev/null` would demand
# four reviews and teach the user to route around the gate entirely.
#
# Two kinds are exempt:
#
#   discards      /dev/null and friends, and a duplicated descriptor (2>&1).
#                 Nothing is written at all.
#   temporaries   An absolute path under /tmp or /var/tmp. Such a file is not
#                 in the tree under review, and cannot reach it except by
#                 being copied back - which is itself a write this table
#                 detects. Scratch work (drafting a commit message, staging
#                 notes) otherwise trips the gate on a turn that changed no
#                 code.
#
# The exemption covers the REDIRECTION OPERATOR only. `cp secret /tmp/x` still
# counts as a write, because deciding which argument of an arbitrary command
# is its target would mean parsing every command's option grammar. Erring
# toward "this was a write" is the right direction for a gate.
BASH_WRITE_EXEMPT='>>?[[:space:]]*(/dev/(null|stderr|stdout|fd/[0-9]+)|/(var/)?tmp/[^[:space:];&|)]*|&[0-9-])'

# Subagents known to hold no file-writing tool. Any OTHER subagent_type
# counts as a possible code change, because a delegated agent's Edit calls
# are recorded in the SUBAGENT's transcript - the parent transcript this hook
# is handed shows only that some agent ran, never what it did. Erring toward
# "it might have edited" is the only rule that closes that hole; the cost is
# a redundant review after delegating to an agent not yet listed here.
#
# An agent belongs on this list only when its own `tools:` line grants it
# neither Edit, Write, nor NotebookEdit. Check the file before adding a name.
READ_ONLY_AGENTS=(
  Explore
  Plan
  claude-code-guide
  cxx:clang-query-runner
  development:efficiency-reviewer
  development:nst-reviewer
  development:property-test-reviewer
  development:tdd-reviewer
  git:commit-writer
  git:git-explorer
  global:settings-doctor
  local:settings-doctor
)

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

# Each of the three predicates below answers one question about the turn's
# events, and code_was_edited is their disjunction. They are separate so a
# new way of changing a file can be recognised by adding one predicate rather
# than by extending a single grep, and so each can be tested on its own.
#
# All three capture their input into a variable rather than piping it
# straight into grep. Piping would fail open on a long turn: grep -q exits at
# the first match, jq upstream is killed by SIGPIPE (141), and
# `set -o pipefail` turns that into a failing pipeline - reporting "no code
# was edited" for a turn that did edit code, which silently opens the gate.

# edit_tool_used <events-jsonl>
#
# True if any event's tool name is Edit/Write/NotebookEdit.
edit_tool_used() {
  local events="$1" names
  names=$(printf '%s\n' "$events" | jq -r '.name // empty')
  grep -qE "$CODE_CHANGE_TOOL_NAMES" <<<"$names"
}

# bash_wrote_a_file <events-jsonl>
#
# True if any Bash event's command matches a BASH_WRITE_PATTERNS entry, once
# the exempt redirection targets have been removed from it. Stripping the
# exemptions first, rather than testing them as a separate condition, is what
# lets a single command that both writes a file and discards stderr
# (`sed -i s/a/b/ f 2>/dev/null`) still count as a write.
bash_wrote_a_file() {
  local events="$1" commands
  commands=$(printf '%s\n' "$events" | jq -r 'select(.name == "Bash") | .command // empty')
  [ -n "$commands" ] || return 1
  # @ delimits the s/// because BASH_WRITE_EXEMPT itself contains | as
  # alternation; a | delimiter here silently truncates the pattern.
  commands=$(sed -E "s@${BASH_WRITE_EXEMPT}@@g" <<<"$commands")
  # One grep over the joined alternation rather than one grep per pattern.
  # This runs on the Stop path, which the user waits on at the end of every
  # turn, so the eight processes the per-pattern loop spawned were eight
  # process spawns of latency on every turn that ran any Bash command.
  grep -qE "$(bash_write_alternation)" <<<"$commands"
}

# bash_write_alternation
#
# The BASH_WRITE_PATTERNS table joined into one extended regex. Kept as a
# function over the table, rather than a second hand-maintained constant, so
# adding a pattern is still a one-line change to the table alone.
bash_write_alternation() {
  local joined
  joined=$(printf '|%s' "${BASH_WRITE_PATTERNS[@]}")
  printf '%s' "${joined:1}"
}

# agent_may_have_edited <events-jsonl>
#
# True if the turn delegated to any subagent not named in READ_ONLY_AGENTS.
# See that table for why an unrecognised agent counts as a possible edit.
agent_may_have_edited() {
  local events="$1" agents unrecognised
  agents=$(printf '%s\n' "$events" | jq -r '.subagent_type // empty')
  [ -n "$agents" ] || return 1
  # One grep against the whole exempt list rather than one grep per entry.
  # Same reason as bash_write_alternation: this is Stop-path latency, paid on
  # every turn that delegated to anything.
  unrecognised=$(grep -Fxv -f <(printf '%s\n' "${READ_ONLY_AGENTS[@]}") <<<"$agents") || true
  [ -n "$unrecognised" ]
}

# code_was_edited <events-jsonl>
#
# True if the turn changed a file by any of the three routes above.
code_was_edited() {
  local events="$1"
  edit_tool_used "$events" || bash_wrote_a_file "$events" || agent_may_have_edited "$events"
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
  transcript_judgeable "$transcript" || exit 0

  block_decision_json "$(missing_reviews_for_transcript "$transcript")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
