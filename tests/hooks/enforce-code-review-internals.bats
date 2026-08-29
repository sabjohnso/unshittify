#!/usr/bin/env bats
# Unit tests against the internal functions of enforce-code-review.sh,
# exercised by sourcing the script (its BASH_SOURCE guard means sourcing it
# does not run main / does not read stdin) and calling
# missing_reviews_for_transcript directly against synthetic transcript
# fixtures - no stdin JSON payload involved.

load helpers

setup() {
  SCRIPT="${HOOKS_DIR}/enforce-code-review.sh"
  # shellcheck source=/dev/null
  source "$SCRIPT"
}

@test "sourcing the script does not execute main or read stdin" {
  # If main() ran, it would call `cat` and block waiting on this test's
  # stdin (a tty/empty pipe here); reaching this assertion at all proves it
  # didn't run.
  [ "$(type -t main)" = "function" ]
}

@test "missing_reviews_for_transcript: no code change yields empty missing set" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' "$(last_prompt_marker)" "$(tool_use_event Read)")")"
  result="$(missing_reviews_for_transcript "$transcript")"
  [ -z "$result" ]
}

@test "missing_reviews_for_transcript: code change with nothing invoked yields all four" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' "$(last_prompt_marker)" "$(tool_use_event Edit)")")"
  result="$(missing_reviews_for_transcript "$transcript")"
  [ "$(printf '%s\n' "$result" | wc -l)" -eq 4 ]
}

@test "monotonicity: appending a satisfying event shrinks the missing set, never grows it" {
  before_transcript="$(write_transcript "$(printf '%s\n%s\n' "$(last_prompt_marker)" "$(tool_use_event Edit)")")"
  before_missing="$(missing_reviews_for_transcript "$before_transcript")"
  before_count="$(printf '%s\n' "$before_missing" | grep -c . || true)"

  after_transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Skill skill=development:review-tdd)")")"
  after_missing="$(missing_reviews_for_transcript "$after_transcript")"
  after_count="$(printf '%s\n' "$after_missing" | grep -c . || true)"

  [ "$after_count" -le "$before_count" ]
  [[ "$after_missing" != *"review-tdd (skill)"* ]]
}

@test "find_turn_start_line warns on stderr when no prompt or marker is present in a non-empty transcript" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no user prompt or last-prompt marker in non-empty transcript"* ]]
}

@test "find_turn_start_line is silent (no warning) for a genuinely empty transcript" {
  transcript="$(mktemp "${BATS_TMPDIR:-/tmp}/empty.XXXXXX.jsonl")"
  : > "$transcript"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# --- SIGPIPE: a matcher fed by a pipe must not report "no match" merely
# --- because the reader exited before the writer finished. Under
# --- `set -o pipefail`, `producer | grep -q` takes the reader's early exit
# --- as SIGPIPE (141) on the producer and fails the whole pipeline, so a
# --- long event list silently opens the gate.

@test "code_was_edited detects an Edit at the head of a very long event list" {
  # Shaped events ({name, skill, subagent_type}), as
  # tool_use_events_since_turn_start emits them - not raw transcript lines.
  # seq/awk rather than `yes | head`: the latter's own SIGPIPE would fail the
  # fixture's command substitution under bats' pipefail, masking the result.
  events="$( { printf '%s\n' '{"name":"Edit","skill":null,"subagent_type":null}'
               seq 1 20000 | awk '{print "{\"name\":\"Read\",\"skill\":null,\"subagent_type\":null}"}'
             } )"
  run code_was_edited "$events"
  [ "$status" -eq 0 ]
}

# --- code changed outside the Edit/Write tools -----------------------------
#
# The gate's promise is "code changed this turn implies the reviews ran". A
# tool-name whitelist keeps that promise only for the one path the harness
# happens to name Edit. Two other paths change files just as effectively and
# are in routine use:
#
#   Bash        The harness's auto mode instructs the model to prefer sed,
#               heredocs and short scripts over the Edit tool outright, so
#               this is not an exotic evasion - it is the documented default
#               under one of the harness's own modes.
#   Agent       A delegated subagent's Edit calls are written to the
#               SUBAGENT's transcript. The parent transcript, which is all
#               this hook is given, records only the Agent call itself.
#               development:change-preparer exists specifically to edit code
#               this way.
#
# Both are asserted below against the real script.

@test "a file edited through Bash sed -i requires the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'fix the parser')" \
    "$(bash_command_event "sed -i 's/a/b/' src/parser.c")")")"
  run missing_reviews_for_transcript "$transcript"
  [ -n "$output" ]
}

@test "a file written through a Bash redirection requires the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'add a header')" \
    "$(bash_command_event 'printf "#pragma once\n" > src/parser.h')")")"
  run missing_reviews_for_transcript "$transcript"
  [ -n "$output" ]
}

@test "a file written through a Bash heredoc requires the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'add a module')" \
    "$(bash_command_event 'cat > src/new.c <<EOF
int main(void) { return 0; }
EOF')")")"
  run missing_reviews_for_transcript "$transcript"
  [ -n "$output" ]
}

@test "an edit delegated to a code-editing subagent requires the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'fix the parser')" \
    "$(tool_use_event Agent subagent_type=development:change-preparer)")")"
  run missing_reviews_for_transcript "$transcript"
  [ -n "$output" ]
}

@test "an edit delegated to an unrecognised subagent requires the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'fix the parser')" \
    "$(tool_use_event Agent subagent_type=some-third-party:unknown-agent)")")"
  run missing_reviews_for_transcript "$transcript"
  [ -n "$output" ]
}

# --- and the corresponding false positives, which must NOT fire ------------
#
# A gate that fires on every turn is a gate the user learns to route around,
# so each read-only shape below is pinned as explicitly as the write shapes
# above.

@test "a read-only Bash command does not require the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'what does the parser do')" \
    "$(bash_command_event 'grep -rn parse src/ | head -20')")")"
  run missing_reviews_for_transcript "$transcript"
  [ -z "$output" ]
}

@test "a Bash command redirecting only to /dev/null does not require the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'does it build')" \
    "$(bash_command_event 'make 2>&1 >/dev/null || echo failed')")")"
  run missing_reviews_for_transcript "$transcript"
  [ -z "$output" ]
}

@test "delegation to a read-only subagent does not require the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'when did this line change')" \
    "$(tool_use_event Agent subagent_type=git:git-explorer)")")"
  run missing_reviews_for_transcript "$transcript"
  [ -z "$output" ]
}

@test "a Bash edit with every required review present does not block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n%s\n' \
    "$(typed_prompt_event 'fix the parser')" \
    "$(bash_command_event "sed -i 's/a/b/' src/parser.c")" \
    "$(tool_use_event Skill skill=development:review-tdd)" \
    "$(tool_use_event Skill skill=development:review-nst)" \
    "$(printf '%s\n%s' "$(tool_use_event Skill skill=development:review-property-tests)" \
                       "$(tool_use_event Skill skill=development:review-efficiency)")")")"
  run missing_reviews_for_transcript "$transcript"
  [ -z "$output" ]
}

# --- laws of code_was_edited ------------------------------------------------
#
# The pre-existing suite pins monotonicity, order-invariance and
# duplicate-insensitivity for missing_reviews. code_was_edited is now a
# three-way disjunction over the same event list and owes the same laws: it
# decides whether the gate applies at all, so a law broken here silently
# disables every review requirement rather than merely miscounting one.

@test "monotonicity: appending any event never un-detects an edit" {
  local base after
  base="$(printf '%s\n' "$(shaped_event Edit)")"
  for after in "$(shaped_event Read)" \
               "$(shaped_event Bash command='grep -rn x .')" \
               "$(shaped_event Skill skill=development:review-tdd)" \
               "$(shaped_event Agent subagent_type=git:git-explorer)"; do
    run code_was_edited "$(printf '%s\n%s\n' "$base" "$after")"
    [ "$status" -eq 0 ]
  done
}

@test "order-invariance: an edit is detected wherever it sits in the list" {
  local edit read_ev
  edit="$(shaped_event Bash command="sed -i 's/a/b/' src/parser.c")"
  read_ev="$(shaped_event Read)"
  run code_was_edited "$(printf '%s\n%s\n' "$edit" "$read_ev")"
  [ "$status" -eq 0 ]
  run code_was_edited "$(printf '%s\n%s\n' "$read_ev" "$edit")"
  [ "$status" -eq 0 ]
}

@test "duplicate-insensitivity: repeating an event decides the same" {
  local edit
  edit="$(shaped_event Bash command="sed -i 's/a/b/' src/parser.c")"
  run code_was_edited "$edit"
  [ "$status" -eq 0 ]
  run code_was_edited "$(printf '%s\n%s\n%s\n' "$edit" "$edit" "$edit")"
  [ "$status" -eq 0 ]
}

@test "a turn of purely read-only events is not an edit, however many" {
  local events=""
  local i
  for i in 1 2 3 4 5 6 7 8; do
    events="${events}$(shaped_event Read)"$'\n'
    events="${events}$(shaped_event Bash command='grep -rn parse src/')"$'\n'
    events="${events}$(shaped_event Agent subagent_type=Explore)"$'\n'
  done
  run code_was_edited "$events"
  [ "$status" -ne 0 ]
}

# --- every table entry is exercised ----------------------------------------
#
# BASH_WRITE_PATTERNS and READ_ONLY_AGENTS are the two tables the gate's
# guarantee rests on. An untested regex in the first is a hole; an untested
# name in the second is a false alarm on every turn that delegates to it.

@test "every BASH_WRITE_PATTERNS shape is detected" {
  local cmd
  for cmd in "sed -i 's/a/b/' f.c" \
             "perl -i -pe 's/a/b/' f.c" \
             "cat f | tee out.txt" \
             "cp a.c b.c" \
             "mv a.c b.c" \
             "rm stale.o" \
             "install -m 755 x /usr/local/bin/x" \
             "patch -p1 < fix.diff" \
             "dd if=/dev/zero of=disk.img bs=1M count=1" \
             "git apply fix.diff" \
             "git restore src/parser.c" \
             "chmod +x run.sh" \
             "printf 'x' > out.txt" \
             "printf 'x' >> out.txt"; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

@test "every READ_ONLY_AGENTS entry is exempt" {
  local agent
  for agent in Explore Plan claude-code-guide cxx:clang-query-runner \
               development:efficiency-reviewer development:nst-reviewer \
               development:property-test-reviewer development:tdd-reviewer \
               git:commit-writer git:git-explorer \
               global:settings-doctor local:settings-doctor; do
    run code_was_edited "$(shaped_event Agent subagent_type="$agent")"
    [ "$status" -ne 0 ] || { echo "falsely flagged: $agent"; return 1; }
  done
}

# --- a write outside the working tree is not a code change ------------------
#
# The gate exists to make code changes reviewable. A redirection into a
# temporary directory cannot change the repository under review: to reach it,
# the file would have to be copied back, and that copy is itself a detected
# write. Without this exemption the gate fires on scratch work - drafting a
# commit message, staging notes - and a gate that fires on turns that changed
# nothing is one people learn to route around.

@test "a redirection into a temporary directory is not a code change" {
  local cmd
  for cmd in 'cat > /tmp/draft.txt <<EOF
notes
EOF' \
             'printf "notes" > /tmp/scratch/notes.md' \
             'printf "notes" >> /var/tmp/notes.md'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -ne 0 ] || { echo "falsely flagged: $cmd"; return 1; }
  done
}

@test "a redirection into the working tree is still a code change" {
  local cmd
  for cmd in 'printf "x" > src/parser.h' \
             'printf "x" > ./notes.md' \
             'printf "x" > /home/user/project/src/parser.h'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

@test "a temp redirection alongside a real edit is still a code change" {
  run code_was_edited "$(shaped_event Bash command="sed -i 's/a/b/' src/parser.c > /tmp/log.txt")"
  [ "$status" -eq 0 ]
}

# --- laws of the exemption strip -------------------------------------------
#
# The exemption is a mask applied before the write patterns are matched, and
# confirm-git-commit-push.sh pins the same laws for its own masker. A mask
# that is not idempotent, or that can swallow a real write, silently opens
# the gate rather than merely reporting the wrong thing.

@test "every exempt redirection target is exempt" {
  # /dev/stderr, /dev/stdout and /dev/fd/N were alternatives in the pattern
  # that no test reached.
  local target
  for target in /dev/null /dev/stderr /dev/stdout /dev/fd/3 /tmp/x /var/tmp/x; do
    run code_was_edited "$(shaped_event Bash command="make > ${target}")"
    [ "$status" -ne 0 ] || { echo "falsely flagged: > ${target}"; return 1; }
  done
  run code_was_edited "$(shaped_event Bash command='make 2>&1')"
  [ "$status" -ne 0 ]
}

@test "idempotence: an exempt redirection decides as if it were absent" {
  local target base
  base='grep -rn parse src/'
  for target in /dev/null /dev/stderr /tmp/log.txt /var/tmp/log.txt; do
    run code_was_edited "$(shaped_event Bash command="$base")"
    local without="$status"
    run code_was_edited "$(shaped_event Bash command="${base} > ${target}")"
    [ "$status" -eq "$without" ] || { echo "differs for ${target}"; return 1; }
  done
}

@test "an exempt redirection never masks a real write" {
  local target write
  for write in "sed -i 's/a/b/' src/parser.c" "cp a.c b.c" "printf x > src/out.h"; do
    for target in /dev/null /tmp/log.txt /var/tmp/log.txt; do
      run code_was_edited "$(shaped_event Bash command="${write} > ${target}")"
      [ "$status" -eq 0 ] || { echo "masked: ${write} > ${target}"; return 1; }
    done
  done
}

@test "repeated exempt redirections decide the same as one" {
  run code_was_edited "$(shaped_event Bash command='make >/dev/null 2>/dev/null >/tmp/a >/tmp/b')"
  [ "$status" -ne 0 ]
  run code_was_edited "$(shaped_event Bash command="sed -i 's/a/b/' f.c >/dev/null >/tmp/a >/tmp/b")"
  [ "$status" -eq 0 ]
}
