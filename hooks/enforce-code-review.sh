#!/usr/bin/env bash
# Stop hook. It blocks the end of the turn when code was written or edited
# this turn (Edit, Write, or NotebookEdit tool calls after the last message
# from the user) and not all of the required reviews ran after that same
# point. The REQUIRED_REVIEWS table below is the set of required reviews. To
# require a new review, add a line there. No other code change is necessary.
set -euo pipefail

# Fully qualified skill-name|agent-name pairs. Either one satisfies the
# requirement. Both carry the plugin prefix exactly as the transcript records
# them. The harness stores an agent's subagent_type as
# development:tdd-reviewer, not as the bare tdd-reviewer, so the agent name
# must be qualified to match.
REQUIRED_REVIEWS=(
  "development:review-tdd|development:tdd-reviewer"
  "development:review-nst|development:nst-reviewer"
  "development:review-property-tests|development:property-test-reviewer"
  "development:review-efficiency|development:efficiency-reviewer"
)

CODE_CHANGE_TOOL_NAMES='^(Edit|Write|NotebookEdit)$'

# Bash commands that change a file. The tool name alone cannot answer this
# question. Bash reads and writes, and the auto mode of the harness tells the
# model to prefer sed and heredocs over the Edit tool. A gate that watches
# only Edit, Write, and NotebookEdit misses the path that the model is told
# to take. To widen the detection, add a pattern here. No other code change
# is necessary.
#
# THIS LIST FAILS CLOSED, in the opposite direction to a permission check. A
# pattern that fires too often costs one redundant review. A write shape
# that is missing here costs the whole guarantee of the gate. When the two
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

# Two entries above have a different anchor from the rest. The difference is
# the reason they work:
#
#   git         The alternation covers every subcommand that rewrites tracked
#               files, not only the ones that take a path. `git reset --hard`,
#               `git clean -fdx`, `git merge`, `git rebase`, and `git pull`
#               all replace the contents of the working tree. None of them
#               was in the list while the list read as a list of patch
#               commands.
#   install     The anchor is a COMMAND position ([;&|(] or the start), not
#               any whitespace. `install` is a coreutils file-copy tool AND
#               the most common subcommand word in the language. make, npm,
#               pip, apt-get, cargo, and go all take it, and none of them
#               touches the tree under review. The cost of the tighter anchor
#               is a miss on `sudo install ...`. That is the direction this
#               file usually refuses. It is accepted here only because the
#               looser anchor demanded four reviews on every `npm install`.
#
# The interpreter entry exists for the same reason as the sed entry. The auto
# mode of the harness tells the model to prefer short scripts, so
# `python3 -c "open('src/x.c','w').write('')"` is a path the model is pushed
# toward. The tail of the option is matched with [^[:alnum:]_-] and not with
# whitespace, so that `python3 -c'...'` counts too.
#
# NOT COVERED, stated and not implied: these patterns are matched against
# the raw command, with no knowledge of quotes, so `echo 'run cp a b'` counts
# as a write. mask_nonexecuting in confirm-git-commit-push.sh is the
# quote-aware masker of this repository, but it removes shell comments and
# heredoc bodies. It leaves a quoted ARGUMENT as it found it, so it does not
# change this case. A fix needs a quoted-string masker that does not exist
# yet. A naive one is worse than the false positive. A removal of the quotes
# hides the real write in `bash -c 'sed -i s/a/b/ f'`.

# One path component under a temporary directory: at least one character, no
# "/", no shell separator, and never "." or "..". The rejection of ".." stops
# a traversal from a claim on the exemption. /tmp/../home/user/src leaves
# /tmp and names a file in the tree under review. The rejection of a lone "."
# costs a redundant review on /tmp/./x, which nobody writes.
BASH_TEMP_COMPONENT='(\.\.[^/[:space:];&|)]|\.[^./[:space:];&|)]|[^./[:space:];&|)])[^/[:space:];&|)]*'

# An absolute path under /tmp or /var/tmp, and nothing else. BASH_WORD_END
# must follow it at each use. Without that, /tmp matches the head of
# /tmpfoo/bar.c and exempts a write into the tree.
BASH_TEMP_PATH="/(var/)?tmp(/${BASH_TEMP_COMPONENT})*"

# Where a command word ends, and where a whole command ends.
BASH_WORD_END='([[:space:];&|)]|$)'
BASH_COMMAND_END='[[:space:]]*([;&|)]|$)'

# Text that writes nothing a review can cover. A space replaces it before the
# patterns above are matched against a command. To widen the exemption, add
# a rule here. No other code change is necessary. Each rule is a complete
# sed -E script. The @ delimits the s/// because the patterns themselves hold
# | as alternation, and a | delimiter would truncate them with no error.
#
# A space, not a deletion: every write pattern anchors on a separator. A
# space left behind means that the removal of an exempt clause can neither
# join two commands into a shape that matches nor split one that must match.
#
# Two rules, and the purpose of each:
#
#   redirection   The redirection pattern is otherwise so broad that a
#                 routine `make >/dev/null` demands four reviews and teaches
#                 the user to go around the gate. Exempt targets are discards
#                 (/dev/null and the like), a duplicated descriptor (2>&1),
#                 and an absolute path under /tmp. A file under /tmp is not
#                 in the tree under review. It can reach the tree only
#                 through a copy back, and this table detects that copy as a
#                 write.
#   scratch dirs  `mkdir -p /tmp/work` and `touch /tmp/x` create nothing a
#                 review can read. But mkdir and touch are in the write table
#                 because they create files in the tree as often. The rule
#                 fires only when EVERY path the command names is temporary
#                 and the command ends there. `mkdir /tmp/a src/b` keeps its
#                 mkdir and is a write.
#
# The redirection exemption covers the REDIRECTION OPERATOR only. `cp secret
# /tmp/x` counts as a write. To find which argument of an arbitrary command
# is its target, the hook would have to parse the option grammar of every
# command. For a gate, the error "this was a write" is the correct
# direction.
BASH_WRITE_EXEMPTIONS=(
  "s@>>?[[:space:]]*(/dev/(null|stderr|stdout|fd/[0-9]+)|${BASH_TEMP_PATH}|&[0-9-])${BASH_WORD_END}@ @g"
  "s@(^|[[:space:];&|(])(mkdir|touch)([[:space:]]+-[A-Za-z-]+)*([[:space:]]+${BASH_TEMP_PATH})+${BASH_COMMAND_END}@ @g"
)

# Subagents that the judgement below says do not change the tree under
# review. Every OTHER subagent_type counts as a possible code change. The
# Edit calls of a delegated agent are recorded in the transcript of the
# SUBAGENT. The parent transcript that this hook reads shows only that some
# agent ran, never what it did. The error "it possibly edited" is the only
# rule that closes that hole. The cost is a redundant review after a
# delegation to an agent that is not yet in this list.
#
# THIS LIST IS A JUDGEMENT ABOUT THE BODY OF EACH AGENT, NOT A GUARANTEE FROM
# ITS `tools:` LINE. The difference is practical: every entry below holds
# Bash. BASH_WRITE_PATTERNS above exists because Bash writes files, and the
# Bash calls of a subagent go to the transcript of the subagent, which no
# SubagentStop hook reads. So the exemption rests on a read of the
# instructions of each agent, with the finding that the agent is told to
# read, search, and report. It does not rest on a capability that the
# harness enforces.
#
# To add a name, read the file of that agent and judge its whole body. Do not
# only check its tools line for Edit. Two consequences of the judgement as it
# stands:
#
#   communication:prose-reviewer   Holds Edit, and is in the list. It is the
#                                  one agent that another Stop hook MANDATES.
#                                  enforce-prose-review.sh blocks a
#                                  substantial reply until this agent has run
#                                  on it. When that mandated delegation
#                                  counted as a possible code change, the two
#                                  hooks had no move that satisfied both. One
#                                  demanded the review, and the other blocked
#                                  the turn for the review. What this agent
#                                  edits is the prose it was given, and the
#                                  review of that prose is the call itself.
#   communication:table-formatter  Holds the same tools and is NOT in the
#                                  list. No hook mandates it, so an entry
#                                  removes no deadlock. Its own instructions
#                                  tell it to apply the rewrite with Edit
#                                  when it is given a file path. In this
#                                  repository, that file is a Markdown skill
#                                  or agent, which is the product.
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

# The turn boundary, the tool_use event schema, and the brief-turn opt-out
# are in the shared library (find_turn_start_line,
# tool_use_events_since_line, turn_requests_brevity). Thus this hook and
# enforce-prose-review.sh agree on where a turn starts, on the shape of an
# event, and on which turns are exempt.

# Each of the three predicates below answers one question about the events
# of the turn, and code_was_edited is their disjunction. They are separate
# for two reasons. A new way to change a file gets one new predicate, not an
# extension of one grep. And each predicate can be tested on its own.
#
# All three capture their input into a variable. They do not pipe it into
# grep. A pipe fails open on a long turn: grep -q exits at the first match,
# SIGPIPE (141) kills the jq upstream, and `set -o pipefail` turns that into
# a failed pipeline. The result reports "no code was edited" for a turn that
# did edit code, and that opens the gate with no error.

# edit_tool_used <events-jsonl>
#
# True when the tool name of an event is Edit, Write, or NotebookEdit.
edit_tool_used() {
  local events="$1" names
  names=$(printf '%s\n' "$events" | jq -r '.name // empty')
  grep -qE "$CODE_CHANGE_TOOL_NAMES" <<<"$names"
}

# bash_wrote_a_file <events-jsonl>
#
# True when the command of a Bash event matches a BASH_WRITE_PATTERNS entry
# after the removal of the exempt redirection targets. The exemptions are
# removed first. They are not a separate condition. Thus a single command
# that writes a file and discards stderr (`sed -i s/a/b/ f 2>/dev/null`)
# counts as a write.
bash_wrote_a_file() {
  local events="$1" commands
  commands=$(printf '%s\n' "$events" | jq -r 'select(.name == "Bash") | .command // empty')
  [ -n "$commands" ] || return 1
  commands=$(strip_exempt_writes <<<"$commands")
  # One grep over the joined alternation, not one grep per pattern. This runs
  # on the Stop path, and the user waits on that path at the end of every
  # turn. The eight processes of the per-pattern loop were eight process
  # spawns of latency on every turn that ran a Bash command.
  grep -qE "$(bash_write_alternation)" <<<"$commands"
}

# strip_exempt_writes
#
# Filter. It replaces every BASH_WRITE_EXEMPTIONS match in its input with a
# space. One sed call carries the whole table. There is not one call per
# rule, because this runs on the Stop path, and the user waits on that path
# at the end of every turn that ran a Bash command.
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
# The BASH_WRITE_PATTERNS table joined into one extended regex. It is a
# function over the table and not a second hand-maintained constant. Thus a
# new pattern is a one-line change to the table alone.
bash_write_alternation() {
  local joined
  joined=$(printf '|%s' "${BASH_WRITE_PATTERNS[@]}")
  printf '%s' "${joined:1}"
}

# agent_may_have_edited <events-jsonl>
#
# True when the turn delegated to a subagent that is not in READ_ONLY_AGENTS.
# See that table for the reason an unknown agent counts as a possible edit.
agent_may_have_edited() {
  local events="$1" agents unrecognised
  agents=$(printf '%s\n' "$events" | jq -r '.subagent_type // empty')
  [ -n "$agents" ] || return 1
  # One grep against the whole exempt list, not one grep per entry. The
  # reason is the same as for bash_write_alternation. This is Stop-path
  # latency, paid on every turn that delegated to an agent.
  unrecognised=$(grep -Fxv -f <(printf '%s\n' "${READ_ONLY_AGENTS[@]}") <<<"$agents") || true
  [ -n "$unrecognised" ]
}

# code_was_edited <events-jsonl>
#
# True when the turn changed a file by one of the three routes above.
code_was_edited() {
  local events="$1"
  edit_tool_used "$events" || bash_wrote_a_file "$events" || agent_may_have_edited "$events"
}

# review_satisfied <events-jsonl> <skill-name> <agent-name>
#
# True (exit 0) when the skill of some event equals skill-name exactly, or
# the subagent_type of some event equals agent-name exactly. The match is on
# the exact name, not on a substring. A skill named
# "development:review-tdd-summary" must not satisfy a
# "development:review-tdd" requirement.
#
# The function slurps the events into one JSON array (-s) and evaluates a
# single any(...) expression. Thus the -e exit status of jq reflects the
# match across the whole event list. Without -s, jq computes the -e status
# per input line of the JSONL stream, and that gives the wrong answer with no
# error as soon as there is more than one event.
review_satisfied() {
  local events="$1" skill_name="$2" agent_name="$3"
  printf '%s\n' "$events" \
    | jq -e -s --arg s "$skill_name" --arg a "$agent_name" \
        'any(.[]; .skill == $s or .subagent_type == $a)' >/dev/null 2>&1
}

# missing_reviews <events-jsonl>
#
# Prints one line per required review (from REQUIRED_REVIEWS) that the given
# events do not satisfy, in the form "<skill> (skill) or <agent> (agent)".
# Prints nothing when the events satisfy all required reviews.
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
# Composes find_turn_start_line, tool_use_events_since_line,
# code_was_edited, turn_requests_brevity, and missing_reviews against a real
# transcript file. Thus the tests run this single function directly with
# synthetic transcript fixtures, not only end to end through stdin. Prints
# nothing when there is no turn to judge, when no code was edited after the
# start of the turn, when the prompt of the turn opted out, or when all
# required reviews ran.
missing_reviews_for_transcript() {
  local transcript="$1"
  local start_line events
  start_line=$(find_turn_start_line "$transcript") || return 0

  events=$(tool_use_events_since_line "$transcript" "$start_line")
  code_was_edited "$events" || return 0

  # The brief-turn opt-out. See turn_requests_brevity in lib/transcript.sh.
  # It is checked only after an edit is known. Most turns edit nothing. On
  # those turns, its answer cannot change the verdict, so they must not pay
  # its process spawns.
  if turn_requests_brevity "$transcript" "$start_line"; then
    return 0
  fi

  missing_reviews "$events"
}

# block_decision_json <missing-lines>
#
# Takes the newline-separated output of missing_reviews, which can be empty.
# Prints the {"decision":"block", reason:...} JSON object on stdout. Prints
# nothing when nothing is missing.
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

  jq -n --arg reason "Code was written or edited this turn, but these required review skills did not run: ${joined}. Run them against the diff, correct the findings, and then stop." \
    '{decision:"block", reason:$reason}'
}

# stop_hook_active_or_unreadable <input-json>
#
# Reads the flag that stops this hook from a second block of a stop that it
# forced itself. Without the flag, the hook loops when the model ignores the
# instruction.
#
# Prints the flag and succeeds. When the payload is not a JSON object, it
# prints nothing and fails. An object is the only shape that the field
# readers above accept. A bare scalar parses as JSON, but `.stop_hook_active`
# on it is an error, so "it parses" is not enough.
#
# The shape check and the first field read share one jq pass. Both run on
# every turn, and a separate process for the validation costs as much as
# every other jq call this hook makes.
stop_hook_active_or_unreadable() {
  local flag
  flag=$(printf '%s' "$1" | jq -r 'if type == "object" then (.stop_hook_active // false | tostring) else empty end' 2>/dev/null)
  # An empty result is the only unreadable signal available here. jq -e
  # reports a payload whose flag is legitimately false as a failure, because
  # -e keys its exit status on the output value and not on the parse.
  [ -n "$flag" ] || return 1
  printf '%s' "$flag"
}

# unreadable_input_decision
#
# The block that the hook emits when it cannot read the stdin payload at all.
# A payload that this hook cannot parse is a payload that it cannot clear.
# The payload names the transcript. Without it, there is no evidence either
# way about the reviews of the turn.
#
# It must be a decision on stdout, not a nonzero exit. The harness reads an
# exit status other than 0 and 2 as a non-blocking error. When the failure of
# jq propagates under `set -e` (exit 5), the turn ends with no review. The
# gate then fails open on the one input it cannot check at all.
#
# This cannot loop. The harness writes the retry payload that carries
# stop_hook_active. The source of the unreadable payload does not write it.
unreadable_input_decision() {
  jq -n --arg reason "The code-review Stop hook could not read its own stdin payload, so it cannot tell whether this turn changed code or whether the required reviews ran. Run the four development: reviews against the diff, correct the findings, and then stop." \
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
