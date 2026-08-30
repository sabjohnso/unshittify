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
  '(^|[[:space:];&|(])(awk|sed|perl|ruby)[[:space:]][^;&|]*-i'  # in-place edit
  '(^|[[:space:];&|(])tee([[:space:]]|$)'
  '(^|[[:space:];&|(])(cp|mv|ln|truncate|touch|mkdir|rmdir|rm|shred)([[:space:]]|$)'
  '(^|[[:space:];&|(])(patch|dos2unix|unix2dos)([[:space:]]|$)'
  '(^|[[:space:];&|(])dd[[:space:]][^;&|]*of='
  '(^|[[:space:];&|(])git[[:space:]]+(am|apply|checkout|cherry-pick|clean|merge|pull|rebase|reset|restore|revert|stash|switch)([[:space:]]|$)'
  '(^|[[:space:];&|(])(chmod|chown|chgrp)([[:space:]]|$)'
  '(^|[[:space:];&|(])(python3?|node|ruby|perl)[[:space:]]+-[ce]([^[:alnum:]_-]|$)'
  '(^|[;&|(][[:space:]]*)install([[:space:]]|$)'             # the coreutils tool
  '>>?[[:space:]]*[^&[:space:]]'                             # redirection to a path
)

# Two entries above are anchored differently from the rest, and the
# difference is the whole reason they work:
#
#   git         The alternation covers every subcommand that rewrites tracked
#               files, not only the ones that take a path. `git reset --hard`,
#               `git clean -fdx`, `git merge`, `git rebase` and `git pull` all
#               replace working-tree contents wholesale, and none of them was
#               listed while the list read as though it were about applying
#               patches.
#   install     Anchored to a COMMAND position ([;&|(] or the start), not to
#               any whitespace, because `install` is a coreutils file-copying
#               tool AND the commonest subcommand word in the language: make,
#               npm, pip, apt-get, cargo and go all take it, and none of them
#               touches the tree under review. The cost of the tighter anchor
#               is that `sudo install ...` is missed; that is the direction
#               the file usually refuses, and it is accepted here only
#               because the looser anchor demanded four reviews on every
#               `npm install`.
#
# The interpreter entry exists for the same reason the sed entry does. The
# harness's auto mode tells the model to prefer short scripts, so
# `python3 -c "open('src/x.c','w').write('')"` is a path it is steered
# toward. The option's tail is matched with [^[:alnum:]_-] rather than
# whitespace so that `python3 -c'...'` counts too.
#
# NOT COVERED, stated rather than implied: these patterns are matched against
# the raw command, with no idea of quoting, so `echo 'run cp a b'` counts as
# a write. confirm-git-commit-push.sh's mask_nonexecuting is the repository's
# quote-aware masker, but it removes shell comments and heredoc bodies - it
# leaves a quoted ARGUMENT exactly as it found it, so it would not change
# this case. Closing it needs a quoted-string masker that does not exist yet,
# and a naive one would be worse than the false positive: stripping quotes
# would hide the real write in `bash -c 'sed -i s/a/b/ f'`.

# One path component under a temporary directory: at least one character,
# no "/" and no shell separator, and never "." or "..". Rejecting ".." is
# what stops a traversal from claiming the exemption - /tmp/../home/user/src
# leaves /tmp and names a file in the tree under review. Rejecting a lone "."
# costs a redundant review on /tmp/./x, which nobody writes.
BASH_TEMP_COMPONENT='(\.\.[^/[:space:];&|)]|\.[^./[:space:];&|)]|[^./[:space:];&|)])[^/[:space:];&|)]*'

# An absolute path under /tmp or /var/tmp, and nothing else. It must be
# followed by BASH_WORD_END wherever it is used: without that, /tmp matches
# the head of /tmpfoo/bar.c and exempts a write into the tree.
BASH_TEMP_PATH="/(var/)?tmp(/${BASH_TEMP_COMPONENT})*"

# Where a command word ends, and where a whole command ends.
BASH_WORD_END='([[:space:];&|)]|$)'
BASH_COMMAND_END='[[:space:]]*([;&|)]|$)'

# Text that writes nothing a review could cover, replaced by a space before
# the patterns above are matched against a command. Add a rule here to widen
# the exemption - no other code changes needed. Each rule is a complete sed
# -E script; @ delimits the s/// because the patterns themselves contain | as
# alternation, and a | delimiter would silently truncate them.
#
# A space, not deletion: every write pattern anchors on a separator, so
# leaving one behind means removing an exempt clause can neither join two
# commands into a shape that matches nor split one that should.
#
# Two rules, and what each is for:
#
#   redirection   The redirection pattern is otherwise so broad that a routine
#                 `make >/dev/null` would demand four reviews and teach the
#                 user to route around the gate entirely. Exempt targets are
#                 discards (/dev/null and friends), a duplicated descriptor
#                 (2>&1), and an absolute path under /tmp - a file that is
#                 not in the tree under review and cannot reach it except by
#                 being copied back, which is itself a write this table
#                 detects.
#   scratch dirs  `mkdir -p /tmp/work` and `touch /tmp/x` create nothing a
#                 review could read, yet mkdir and touch are in the write
#                 table because they create files in the tree just as often.
#                 The rule fires only when EVERY path the command names is
#                 temporary and the command ends there: `mkdir /tmp/a src/b`
#                 keeps its mkdir and is still a write.
#
# The redirection exemption covers the REDIRECTION OPERATOR only. `cp secret
# /tmp/x` still counts as a write, because deciding which argument of an
# arbitrary command is its target would mean parsing every command's option
# grammar. Erring toward "this was a write" is the right direction for a gate.
BASH_WRITE_EXEMPTIONS=(
  "s@>>?[[:space:]]*(/dev/(null|stderr|stdout|fd/[0-9]+)|${BASH_TEMP_PATH}|&[0-9-])${BASH_WORD_END}@ @g"
  "s@(^|[[:space:];&|(])(mkdir|touch)([[:space:]]+-[A-Za-z-]+)*([[:space:]]+${BASH_TEMP_PATH})+${BASH_COMMAND_END}@ @g"
)

# Subagents judged not to change the tree under review. Any OTHER
# subagent_type counts as a possible code change, because a delegated agent's
# Edit calls are recorded in the SUBAGENT's transcript - the parent transcript
# this hook is handed shows only that some agent ran, never what it did.
# Erring toward "it might have edited" is the only rule that closes that hole;
# the cost is a redundant review after delegating to an agent not yet listed
# here.
#
# THIS LIST IS A JUDGEMENT ABOUT EACH AGENT'S BODY, NOT A GUARANTEE DERIVED
# FROM ITS `tools:` LINE, and the difference is not academic: every entry
# below holds Bash. BASH_WRITE_PATTERNS above exists precisely because Bash
# writes files, and a subagent's Bash calls go to the subagent's own
# transcript, which no SubagentStop hook reads. So the exemption rests on
# having read each agent's instructions and found that what it is told to do
# is read, search and report - not on any capability the harness enforces.
#
# Adding a name therefore means reading that agent's file and judging its
# whole body, not checking its tools line for Edit. Two consequences of the
# judgement as it stands:
#
#   communication:prose-reviewer   Holds Edit, and is listed anyway. It is
#                                  the one agent another Stop hook MANDATES:
#                                  enforce-prose-review.sh blocks a
#                                  substantial reply until this agent has run
#                                  on it. Treating that mandated delegation
#                                  as a possible code change left the two
#                                  hooks with no move that satisfies both -
#                                  one demanded the review, the other blocked
#                                  the turn for having run it. What it edits
#                                  is the prose it was handed, and reviewing
#                                  that prose is the invocation itself.
#   communication:table-formatter  Holds the same tools and is NOT listed. No
#                                  hook mandates it, so listing it would buy
#                                  no deadlock relief, and its own
#                                  instructions tell it to apply the rewrite
#                                  with Edit when it is given a file path -
#                                  in this repository that file is a Markdown
#                                  skill or agent, which is the product.
READ_ONLY_AGENTS=(
  Explore
  Plan
  claude-code-guide
  communication:prose-reviewer
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
  commands=$(strip_exempt_writes <<<"$commands")
  # One grep over the joined alternation rather than one grep per pattern.
  # This runs on the Stop path, which the user waits on at the end of every
  # turn, so the eight processes the per-pattern loop spawned were eight
  # process spawns of latency on every turn that ran any Bash command.
  grep -qE "$(bash_write_alternation)" <<<"$commands"
}

# strip_exempt_writes
#
# Filter. Replaces every BASH_WRITE_EXEMPTIONS match in its input with a
# space. One sed invocation carrying the whole table, rather than one per
# rule: this runs on the Stop path the user waits on at the end of every turn
# that ran any Bash command.
strip_exempt_writes() {
  local -a sed_args=()
  local rule
  for rule in "${BASH_WRITE_EXEMPTIONS[@]}"; do
    sed_args+=(-e "$rule")
  done
  sed -E "${sed_args[@]}"
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

# stop_hook_active_or_unreadable <input-json>
#
# Reads the flag that stops this hook re-blocking a stop it forced itself,
# which would loop if the model ignored the instruction.
#
# Prints the flag and succeeds, or prints nothing and fails
# when the payload is not a JSON object - the only shape the field readers
# above can be applied to. A bare scalar parses as JSON yet still makes
# `.stop_hook_active` an error, so "parses" is not enough.
#
# The shape check and the first field read share one jq pass. Both run on
# every turn, and validating in a process of its own cost as much again as
# every other jq call this hook makes.
stop_hook_active_or_unreadable() {
  local flag
  flag=$(printf '%s' "$1" | jq -r 'if type == "object" then (.stop_hook_active // false | tostring) else empty end' 2>/dev/null)
  # An empty result is the only unreadable signal available here: jq -e would
  # report a payload whose flag is legitimately false as a failure, since -e
  # keys its exit status on the output value rather than on the parse.
  [ -n "$flag" ] || return 1
  printf '%s' "$flag"
}

# unreadable_input_decision
#
# The block emitted when the stdin payload cannot be read at all. A payload
# this hook cannot parse is a payload it cannot clear: it names the
# transcript, so without it there is no evidence either way about whether the
# turn's reviews ran.
#
# It must be a decision on stdout, not a nonzero exit. The harness reads any
# exit status other than 0 and 2 as a non-blocking error, so letting jq's
# failure propagate under `set -e` (exit 5) ends the turn unreviewed - the
# gate failing open on the one input it cannot check at all.
#
# This cannot loop: the retry payload carrying stop_hook_active is written by
# the harness, not by whatever produced the unreadable one.
unreadable_input_decision() {
  jq -n --arg reason "The code-review Stop hook could not read its own stdin payload, so it cannot tell whether this turn changed code or whether the required reviews ran. Run the four development: reviews against the diff, address any findings, and then stop." \
    '{decision:"block", reason:$reason}'
}

main() {
  local input
  input=$(cat)

  local stop_active
  if ! stop_active=$(stop_hook_active_or_unreadable "$input"); then
    unreadable_input_decision
    return 0
  fi

  if [ "$stop_active" = "true" ]; then
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
