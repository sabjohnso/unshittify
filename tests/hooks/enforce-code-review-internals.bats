#!/usr/bin/env bats
# Unit tests for the internal functions of enforce-code-review.sh. Each
# test sources the script and calls missing_reviews_for_transcript directly
# against synthetic transcript fixtures. The BASH_SOURCE guard of the script
# means that a source does not run main and does not read stdin. No stdin
# JSON payload is involved.

load helpers

setup() {
  SCRIPT="${HOOKS_DIR}/enforce-code-review.sh"
  # shellcheck source=/dev/null
  source "$SCRIPT"
}

@test "a source of the script does not run main and does not read stdin" {
  # If main() ran, it would call `cat` and wait on the stdin of this test
  # (a tty or an empty pipe here). This assertion runs, so main() did not
  # run.
  [ "$(type -t main)" = "function" ]
}

@test "missing_reviews_for_transcript: no code change gives an empty missing set" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' "$(last_prompt_marker)" "$(tool_use_event Read)")")"
  result="$(missing_reviews_for_transcript "$transcript")"
  [ -z "$result" ]
}

@test "missing_reviews_for_transcript: a code change with no review gives all four" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' "$(last_prompt_marker)" "$(tool_use_event Edit)")")"
  result="$(missing_reviews_for_transcript "$transcript")"
  [ "$(printf '%s\n' "$result" | wc -l)" -eq 4 ]
}

@test "find_turn_start_line warns on stderr when a transcript that is not empty has no prompt and no marker" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no user prompt or last-prompt marker in non-empty transcript"* ]]
}

@test "find_turn_start_line is silent (no warning) for an empty transcript" {
  transcript="$(mktemp "$(fixture_dir)/empty.XXXXXX.jsonl")"
  : > "$transcript"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# --- SIGPIPE: a matcher that reads from a pipe must not report "no match"
# --- only because the reader exited before the writer finished. Under
# --- `set -o pipefail`, `producer | grep -q` turns the early exit of the
# --- reader into SIGPIPE (141) on the producer and fails the whole pipeline.
# --- So a long event list opens the gate with no error.

@test "code_was_edited finds an Edit at the head of a very long event list" {
  # Shaped events ({name, skill, subagent_type}), as
  # tool_use_events_since_line emits them. They are not raw transcript
  # lines. The fixture uses seq and awk, not `yes | head`. The SIGPIPE of
  # `yes | head` fails the command substitution of the fixture under the
  # pipefail of bats and hides the result.
  events="$( { printf '%s\n' '{"name":"Edit","skill":null,"subagent_type":null}'
               seq 1 20000 | awk '{print "{\"name\":\"Read\",\"skill\":null,\"subagent_type\":null}"}'
             } )"
  run code_was_edited "$events"
  [ "$status" -eq 0 ]
}

# --- code changed outside the Edit/Write tools -----------------------------
#
# The promise of the gate is "code changed this turn, so the reviews ran".
# A list of tool names keeps that promise only for the one path that the
# harness names Edit. Two other paths change files as well, and both are in
# routine use:
#
#   Bash        The auto mode of the harness tells the model to prefer sed,
#               heredocs, and short scripts over the Edit tool. So this is
#               not a rare evasion. It is the documented default under one
#               of the modes of the harness.
#   Agent       The Edit calls of a delegated subagent go to the transcript
#               of the SUBAGENT. The parent transcript, which is all that
#               this hook gets, records only the Agent call itself.
#               development:change-preparer exists to edit code this way.
#
# The tests below assert both against the real script.

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

@test "an edit delegated to an unknown subagent requires the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'fix the parser')" \
    "$(tool_use_event Agent subagent_type=some-third-party:unknown-agent)")")"
  run missing_reviews_for_transcript "$transcript"
  [ -n "$output" ]
}

# --- and the corresponding false positives, which must NOT fire ------------
#
# A gate that fires on every turn is a gate that the user learns to go
# around. So each read-only shape below is pinned as explicitly as the write
# shapes above.

@test "a read-only Bash command does not require the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'what does the parser do')" \
    "$(bash_command_event 'grep -rn parse src/ | head -20')")")"
  run missing_reviews_for_transcript "$transcript"
  [ -z "$output" ]
}

@test "a Bash command that redirects only to /dev/null does not require the reviews" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'does it build')" \
    "$(bash_command_event 'make 2>&1 >/dev/null || echo failed')")")"
  run missing_reviews_for_transcript "$transcript"
  [ -z "$output" ]
}

@test "a delegation to a read-only subagent does not require the reviews" {
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
# The earlier suite pins monotonicity, order invariance, and
# duplicate insensitivity for missing_reviews. code_was_edited is now a
# three-way disjunction over the same event list, and it must obey the same
# laws. It decides whether the gate applies at all. A broken law here
# disables every review requirement with no error. It does not only
# miscount one.

@test "monotonicity: an event added at the end never hides an edit" {
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

@test "order invariance: the function finds an edit at every position in the list" {
  local edit read_ev
  edit="$(shaped_event Bash command="sed -i 's/a/b/' src/parser.c")"
  read_ev="$(shaped_event Read)"
  run code_was_edited "$(printf '%s\n%s\n' "$edit" "$read_ev")"
  [ "$status" -eq 0 ]
  run code_was_edited "$(printf '%s\n%s\n' "$read_ev" "$edit")"
  [ "$status" -eq 0 ]
}

@test "duplicate insensitivity: a repeated event gives the same decision" {
  local edit
  edit="$(shaped_event Bash command="sed -i 's/a/b/' src/parser.c")"
  run code_was_edited "$edit"
  [ "$status" -eq 0 ]
  run code_was_edited "$(printf '%s\n%s\n%s\n' "$edit" "$edit" "$edit")"
  [ "$status" -eq 0 ]
}

@test "a turn of only read-only events is not an edit, whatever their number" {
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
# BASH_WRITE_PATTERNS and READ_ONLY_AGENTS are the two tables that the
# guarantee of the gate rests on. An untested regex in the first is a hole.
# An untested name in the second is a false alarm on every turn that
# delegates to it.

# At least one command per BASH_WRITE_PATTERNS entry. The two tests below
# read this list from opposite ends. One asserts that the hook finds every
# command here. The other asserts that every pattern in the table matches
# something here. Together they say that the table has no untested regex.
WRITE_FIXTURES=(
  "sed -i 's/a/b/' f.c"
  "perl -i -pe 's/a/b/' f.c"
  "awk -i inplace '{print}' src/x.c"
  "cat f | tee out.txt"
  "cp a.c b.c"
  "mv a.c b.c"
  "rm stale.o"
  "install -m 755 x /usr/local/bin/x"
  "patch -p1 < fix.diff"
  "dd if=/dev/zero of=disk.img bs=1M count=1"
  "git apply fix.diff"
  "git restore src/parser.c"
  "git reset --hard"
  "chmod +x run.sh"
  "python3 -c \"open('src/x.c','w').write('')\""
  "printf 'x' > out.txt"
  "printf 'x' >> out.txt"
)

@test "the fixtures below cover every BASH_WRITE_PATTERNS entry" {
  # The test beside this one asserts that the hook finds each fixture
  # command. That is a claim about the fixtures, not about the table. A
  # pattern with no fixture passes it with no error. This test closes that
  # gap. It reads the table itself, so a new pattern with no fixture fails
  # here and does not ship untested.
  local pattern
  for pattern in "${BASH_WRITE_PATTERNS[@]}"; do
    printf '%s\n' "${WRITE_FIXTURES[@]}" | grep -qE "$pattern" \
      || { echo "no fixture exercises: $pattern"; return 1; }
  done
}

@test "the hook finds every BASH_WRITE_PATTERNS shape" {
  local cmd
  for cmd in "${WRITE_FIXTURES[@]}"; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

@test "every READ_ONLY_AGENTS entry is exempt" {
  # The test reads the table. It does not repeat it. So a new name there is
  # covered as soon as it is added, and no name is exempt without a test.
  local agent
  for agent in "${READ_ONLY_AGENTS[@]}"; do
    run code_was_edited "$(shaped_event Agent subagent_type="$agent")"
    [ "$status" -ne 0 ] || { echo "falsely flagged: $agent"; return 1; }
  done
}

# --- a write outside the working tree is not a code change ------------------
#
# The gate exists to make code changes reviewable. A redirection into a
# temporary directory cannot change the repository under review. To reach
# the repository, the file has to be copied back, and the hook finds that
# copy as a write. Without this exemption, the gate fires on scratch work,
# such as a draft of a commit message or some notes. A gate that fires on a
# turn that changed nothing is one that people learn to go around.

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

@test "a temporary redirection beside a real edit is a code change" {
  run code_was_edited "$(shaped_event Bash command="sed -i 's/a/b/' src/parser.c > /tmp/log.txt")"
  [ "$status" -eq 0 ]
}

# --- laws of the exemption strip -------------------------------------------
#
# The exemption is a mask that the hook applies before it matches the
# write patterns. confirm-git-commit-push.sh pins the same laws for its own
# masker. A mask that is not idempotent, or that can hide a real write,
# opens the gate with no error. It does not only report the wrong thing.

@test "every exempt redirection target is exempt" {
  # /dev/stderr, /dev/stdout, and /dev/fd/N were alternatives in the
  # pattern that no test reached.
  local target
  for target in /dev/null /dev/stderr /dev/stdout /dev/fd/3 /tmp/x /var/tmp/x; do
    run code_was_edited "$(shaped_event Bash command="make > ${target}")"
    [ "$status" -ne 0 ] || { echo "falsely flagged: > ${target}"; return 1; }
  done
  run code_was_edited "$(shaped_event Bash command='make 2>&1')"
  [ "$status" -ne 0 ]
}

@test "idempotence: the decision with an exempt redirection is the decision without it" {
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

@test "repeated exempt redirections give the same decision as one" {
  run code_was_edited "$(shaped_event Bash command='make >/dev/null 2>/dev/null >/tmp/a >/tmp/b')"
  [ "$status" -ne 0 ]
  run code_was_edited "$(shaped_event Bash command="sed -i 's/a/b/' f.c >/dev/null >/tmp/a >/tmp/b")"
  [ "$status" -eq 0 ]
}

# --- write shapes the table missed -----------------------------------------
#
# Each command below changes a file in the working tree, and the table
# reported each one as no write. The git commands rewrite tracked files
# with none of the subcommands that the alternation named. The interpreter
# commands matter because the auto mode of the harness tells the model to
# prefer short scripts. A one-line script is the path the model is pushed
# toward, not an evasion.

@test "a git subcommand that rewrites the working tree requires the reviews" {
  local cmd
  for cmd in 'git reset --hard' \
             'git clean -fdx' \
             'git merge feature' \
             'git rebase main' \
             'git pull' \
             'git switch other' \
             'git am patch.mbox' \
             'git cherry-pick abc123'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

@test "a file rewritten from an interpreter one-liner requires the reviews" {
  local cmd
  for cmd in 'python3 -c "open('"'"'src/x.c'"'"','"'"'w'"'"').write('"'"''"'"')"' \
             'python -c "import pathlib"' \
             'node -e "require('"'"'fs'"'"').writeFileSync('"'"'src/x.js'"'"','"'"''"'"')"' \
             'ruby -e "File.write %q(src/x.rb), %q()"' \
             'perl -e "open F, q(>src/x.pl)"'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

@test "an awk in-place rewrite requires the reviews" {
  run code_was_edited "$(shaped_event Bash command="awk -i inplace '{print}' src/x.c")"
  [ "$status" -eq 0 ]
}

@test "a redirection that traverses out of the temporary directory requires the reviews" {
  # The exemption reads "an absolute path under /tmp". /tmp/../home/... is
  # not under /tmp. It names a file in the tree under review, reached
  # through the exemption.
  local cmd
  for cmd in 'printf x > /tmp/../home/sbj/Sandbox/unshittify/src/parser.c' \
             'printf x > /tmp/a/../../home/sbj/src/parser.c' \
             'printf x >> /var/tmp/../../home/sbj/src/parser.c'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

@test "a redirection to a path that only starts with the temporary prefix requires the reviews" {
  local cmd
  for cmd in 'printf x > /tmpfoo/bar.c' \
             'printf x > /tmpfile' \
             'printf x > /var/tmpfoo/bar.c'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

# --- and shapes the table wrongly called writes -----------------------------
#
# None of these commands changes a file in the repository. Each one costs
# four reviews on a turn with no diff to review, and that teaches a user to
# go around the gate.

@test "an install of dependencies is not a code change" {
  local cmd
  for cmd in 'make install' \
             'npm install' \
             'npm install --save-dev bats' \
             'pip install -r requirements.txt' \
             'apt-get install -y jq' \
             'cargo install ripgrep' \
             'go install ./...'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -ne 0 ] || { echo "falsely flagged: $cmd"; return 1; }
  done
}

@test "install as the command word is a code change" {
  local cmd
  for cmd in 'install -m 755 x /usr/local/bin/x' \
             'mkdir build && install -m 644 hdr.h include/'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

@test "a new scratch file or directory under a temporary path is not a code change" {
  local cmd
  for cmd in 'mkdir -p /tmp/work' \
             'mkdir /tmp/work /tmp/other' \
             'touch /tmp/x' \
             'touch -a /var/tmp/x' \
             'mkdir -p /tmp/work && grep -rn parse src/'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -ne 0 ] || { echo "falsely flagged: $cmd"; return 1; }
  done
}

@test "a new file or directory in the working tree is a code change" {
  local cmd
  for cmd in 'mkdir -p src/parser' \
             'touch src/parser.c' \
             'mkdir -p /tmp/work src/parser' \
             'touch /tmp/x src/parser.c' \
             'mkdir -p /tmp/../home/sbj/src'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

# --- laws of the missing-review computation, over generated input -----------
#
# CLAUDE.md states three laws for this computation, and it requires a
# property test for each law, not an example. One fixed example pinned each
# law, and that is weaker than it reads. The monotonicity example compared
# only COUNTS, so a result that dropped nst and added tdd passed it. The
# duplicate example duplicated a skill and asserted only that the result was
# empty.
#
# bats has no QuickCheck, so the generator below is bash. It varies the
# number of code changes, the set of required reviews that are present,
# whether each one runs as a skill or as its agent, the quantity of
# read-only noise around them, and the order of all of it. A fixed constant
# seeds it, and only prng_next advances it. So a trial that breaks a law
# occurs again on a rerun of the suite. $RANDOM cannot promise that.
#
# One dimension is enumerated, not sampled. The set of reviews that a turn
# already holds has sixteen values, and the monotonicity law is a statement
# about exactly that dimension. So that test walks all sixteen and generates
# the rest of each turn around them. The other two laws sample it with all
# the rest.

PRNG_SEED=20260829

# The number of turns that each sampled law generates. Every turn writes a
# transcript and scans it. bats runs a test body under a DEBUG trap, which
# makes each simple command cost far more than in a plain shell. So these
# three tests are about a quarter of the run time of the suite (measured:
# 15 s of 53 s). Raise the counts for a harder search. Nothing else needs a
# change, and the seed keeps each finding reproducible. The monotonicity
# law takes its count from REVIEW_SUBSETS, because it enumerates that
# dimension.
TRIALS=8                    # duplicate-insensitivity
ORDER_TRIALS=5              # order-invariance: turns...
PERMUTATIONS_PER_TRIAL=3    # ...and orderings of each

prng_reset() { PRNG_STATE="$PRNG_SEED"; }

# prng_next <n>
#
# Advances a linear congruential generator and puts its next value, reduced
# to [0, n), in PRNG_VALUE. It sets a global and does not print, because a
# command substitution runs in a subshell. $(prng_next 4) would discard the
# state advance and give the same number forever. The function uses the high
# bits, because the low bits of an LCG have a short period.
prng_next() {
  PRNG_STATE=$(( (PRNG_STATE * 1103515245 + 12345) % 2147483648 ))
  PRNG_VALUE=$(( (PRNG_STATE / 65536) % $1 ))
}

# An event spec is a tool name, with an optional "|" and the one argument
# that decides what that tool did: a Bash command, or a subagent type. The
# two tables are the alphabet of the generator. event_line below turns one
# spec into the transcript line for it.
CODE_CHANGE_SPECS=(
  "Edit"
  "Write"
  "NotebookEdit"
  "Bash|sed -i 's/a/b/' src/parser.c"
  "Bash|printf 'x' > src/parser.h"
  "Agent|development:change-preparer"
)

NOISE_SPECS=(
  "Read"
  "Grep"
  "Glob"
  "Bash|grep -rn parse src/"
  "Bash|make > /dev/null"
  "Agent|Explore"
  "Agent|git:git-explorer"
)

event_line() {
  local name="${1%%|*}" arg="${1#*|}"
  case "$name" in
    Bash)  bash_command_event "$arg" ;;
    Agent) tool_use_event Agent subagent_type="$arg" ;;
    Skill) tool_use_event Skill skill="$arg" ;;
    *)     tool_use_event "$name" ;;
  esac
}

# prepare_generator
#
# Prepares what the three law tests share: SPEC_LINE, the transcript line
# of every spec, encoded once; PROMPT_LINE, the prompt that opens the turn;
# and REVIEW_SUBSETS, the number of subsets of the required reviews. Each
# encoded line costs a jq process, and the trials ask for the same twenty or
# so specs hundreds of times. An encode on demand made these three tests the
# slowest part of the suite by a wide margin.
#
# All of it is in a function and not at file scope, for two separate
# reasons:
#
#   REQUIRED_REVIEWS  is not in scope until setup() sources the hook, and
#                     that occurs after the top level of the file has run. A
#                     count at the top level counts an empty array.
#                     REVIEW_SUBSETS came out as 1, the generator produced
#                     turns with no review at all, and every test passed.
#   SPEC_LINE         must be declared with -g. bats runs each @test in its
#                     own shell, and a `declare -A` at file scope does not
#                     reach it. The name arrives as an ordinary indexed
#                     array, where SPEC_LINE[Edit] is arithmetic on an unset
#                     variable and not a string key.
prepare_generator() {
  declare -gA SPEC_LINE=()
  declare -g PROMPT_LINE
  declare -g REVIEW_SUBSETS=$(( 1 << ${#REQUIRED_REVIEWS[@]} ))
  local spec i form
  PROMPT_LINE="$(typed_prompt_event 'a generated turn')"
  for spec in "${CODE_CHANGE_SPECS[@]}" "${NOISE_SPECS[@]}"; do
    SPEC_LINE["$spec"]="$(event_line "$spec")"
  done
  for ((i = 0; i < ${#REQUIRED_REVIEWS[@]}; i++)); do
    for form in 0 1; do
      spec="$(review_spec "$i" "$form")"
      SPEC_LINE["$spec"]="$(event_line "$spec")"
    done
  done
}

# review_spec <index> <form>
#
# The event spec that satisfies required review <index>: its skill (form 0)
# or its agent (form 1). It reads REQUIRED_REVIEWS, so a new required review
# extends the generated space with no change here.
review_spec() {
  local entry="${REQUIRED_REVIEWS[$1]}"
  if [ "$2" -eq 0 ]; then
    printf 'Skill|%s' "${entry%%|*}"
  else
    printf 'Agent|%s' "${entry##*|}"
  fi
}

# shuffle_specs
#
# Permutes the global SPECS in place, with Fisher-Yates over the same
# seeded generator. It works in place and not through a pipeline, because a
# process substitution or a command substitution advances PRNG_STATE in a
# subshell and loses it.
shuffle_specs() {
  local i j tmp
  for ((i = ${#SPECS[@]} - 1; i > 0; i--)); do
    prng_next $((i + 1)); j="$PRNG_VALUE"
    tmp="${SPECS[$i]}"; SPECS[$i]="${SPECS[$j]}"; SPECS[$j]="$tmp"
  done
}

# gen_turn_with_reviews <mask>
#
# Generates one turn into the global SPECS: zero to two code changes, each
# required review whose bit is set in <mask> in a generated form, and one to
# three read-only events, all shuffled together. The caller chooses the set
# of reviews, so a test can enumerate that dimension and not sample it. All
# the rest of the turn is generated.
gen_turn_with_reviews() {
  local mask="$1" i n
  SPECS=()

  prng_next 3; n="$PRNG_VALUE"
  for ((i = 0; i < n; i++)); do
    prng_next "${#CODE_CHANGE_SPECS[@]}"
    SPECS+=("${CODE_CHANGE_SPECS[$PRNG_VALUE]}")
  done

  for ((i = 0; i < ${#REQUIRED_REVIEWS[@]}; i++)); do
    if (( (mask >> i) & 1 )); then
      prng_next 2
      SPECS+=("$(review_spec "$i" "$PRNG_VALUE")")
    fi
  done

  prng_next 3; n=$((PRNG_VALUE + 1))
  for ((i = 0; i < n; i++)); do
    prng_next "${#NOISE_SPECS[@]}"
    SPECS+=("${NOISE_SPECS[$PRNG_VALUE]}")
  done

  shuffle_specs
}

# gen_turn_specs
#
# gen_turn_with_reviews over a generated subset, for the laws whose
# statement does not single out that dimension.
gen_turn_specs() {
  prng_next "$REVIEW_SUBSETS"
  gen_turn_with_reviews "$PRNG_VALUE"
}

# insert_spec_repeated <count> <spec>
#
# Inserts <spec> into the global SPECS at <count> generated positions. So
# the repeats are spread through the turn and are not adjacent.
insert_spec_repeated() {
  local count="$1" spec="$2" i pos
  for ((i = 0; i < count; i++)); do
    prng_next $(( ${#SPECS[@]} + 1 )); pos="$PRNG_VALUE"
    SPECS=("${SPECS[@]:0:pos}" "$spec" "${SPECS[@]:pos}")
  done
}

# missing_set <spec...>
#
# The missing-review set for a transcript built from the given specs, one
# review per line, sorted. The laws below are about SETS, so every
# comparison is between sorted output and never between counts.
missing_set() {
  local lines="$PROMPT_LINE" spec
  for spec in "$@"; do
    lines+=$'\n'"${SPEC_LINE[$spec]}"
  done
  local transcript
  transcript="$(write_transcript "$lines")"
  missing_reviews_for_transcript "$transcript" | sort
}

# without_line <set> <line>
#
# The newline-separated <set> without <line> if it is a member, in the same
# order. It is bash and not a grep -Fxv. So an empty set, the most common
# one here, needs no special case and no `|| true` around a grep that found
# nothing.
without_line() {
  local out="" candidate
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    [ "$candidate" = "$2" ] && continue
    out+="${candidate}"$'\n'
  done <<< "$1"
  printf '%s' "${out%$'\n'}"
}

# review_line_for <index>
#
# The name that missing_reviews gives required review <index> in a report.
review_line_for() {
  printf '%s (skill) or %s (agent)' \
    "${REQUIRED_REVIEWS[$1]%%|*}" "${REQUIRED_REVIEWS[$1]##*|}"
}

@test "law: a satisfying event added at the end removes exactly that review from the missing set" {
  prng_reset
  prepare_generator
  # Exhaustive over the set of reviews that the turn already holds, all
  # sixteen subsets, with the rest of each turn generated. The law is about
  # that dimension, and it is small enough to enumerate. So the review that
  # the test adds cycles over it and is not sampled. The subset with neither
  # tdd nor nst, with tdd added, is the case that catches a computation that
  # drops nst as a side effect, and the enumeration guarantees that the test
  # reaches it.
  local present idx before after expected
  for ((present = 0; present < REVIEW_SUBSETS; present++)); do
    gen_turn_with_reviews "$present"
    before="$(missing_set "${SPECS[@]}")"

    idx=$(( present % ${#REQUIRED_REVIEWS[@]} ))
    prng_next 2
    after="$(missing_set "${SPECS[@]}" "$(review_spec "$idx" "$PRNG_VALUE")")"

    # CLAUDE.md states the law as a subset: missing(T ++ [e]) is a subset
    # of missing(T). This test asserts the exact set instead. A subset alone
    # still admits the failure that this test catches. A result that drops
    # nst and adds tdd makes the set smaller and passes.
    expected="$(without_line "$before" "$(review_line_for "$idx")")"
    [ "$after" = "$expected" ] || {
      echo "subset ${present} (seed ${PRNG_SEED}): appending a review changed more than that review"
      echo "before:   [${before}]"
      echo "expected: [${expected}]"
      echo "after:    [${after}]"
      return 1
    }
  done
}

@test "law: the missing set is the same for every order of the events of a turn" {
  prng_reset
  prepare_generator
  local trial permutation baseline permuted
  for ((trial = 1; trial <= ORDER_TRIALS; trial++)); do
    gen_turn_specs
    baseline="$(missing_set "${SPECS[@]}")"
    for ((permutation = 1; permutation <= PERMUTATIONS_PER_TRIAL; permutation++)); do
      shuffle_specs
      permuted="$(missing_set "${SPECS[@]}")"
      [ "$permuted" = "$baseline" ] || {
        echo "trial ${trial}, permutation ${permutation} (seed ${PRNG_SEED}): order changed the result"
        echo "one ordering:     [${baseline}]"
        echo "another ordering: [${permuted}]"
        return 1
      }
    done
  done
}

@test "law: a repeated review event gives the same decision as one call" {
  prng_reset
  prepare_generator
  local trial once repeated spec idx form extra
  for ((trial = 1; trial <= TRIALS; trial++)); do
    gen_turn_specs

    prng_next "${#REQUIRED_REVIEWS[@]}"; idx="$PRNG_VALUE"
    prng_next 2; form="$PRNG_VALUE"
    spec="$(review_spec "$idx" "$form")"

    insert_spec_repeated 1 "$spec"
    once="$(missing_set "${SPECS[@]}")"

    prng_next 3; extra=$((PRNG_VALUE + 1))
    insert_spec_repeated "$extra" "$spec"
    repeated="$(missing_set "${SPECS[@]}")"

    [ "$repeated" = "$once" ] || {
      echo "trial ${trial} (seed ${PRNG_SEED}): $((extra + 1)) invocations differed from 1"
      echo "once:     [${once}]"
      echo "repeated: [${repeated}]"
      return 1
    }
  done
}
