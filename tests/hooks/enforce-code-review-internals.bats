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

@test "find_turn_start_line warns on stderr when no prompt or marker is present in a non-empty transcript" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no user prompt or last-prompt marker in non-empty transcript"* ]]
}

@test "find_turn_start_line is silent (no warning) for a genuinely empty transcript" {
  transcript="$(mktemp "$(fixture_dir)/empty.XXXXXX.jsonl")"
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

# One command per BASH_WRITE_PATTERNS entry, at least. The two tests below
# read this same list from opposite ends: one asserts every command here is
# detected, the other asserts every pattern in the table matches something
# here, and together they say the table has no untested regex.
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

@test "every BASH_WRITE_PATTERNS entry is exercised by the fixtures below" {
  # The neighbouring test asserts that each fixture command is detected,
  # which is a claim about the fixtures, not about the table: a pattern
  # nobody wrote a fixture for passes it silently. This one closes that gap
  # by reading the table itself, so adding a pattern without a fixture fails
  # here rather than shipping untested.
  local pattern
  for pattern in "${BASH_WRITE_PATTERNS[@]}"; do
    printf '%s\n' "${WRITE_FIXTURES[@]}" | grep -qE "$pattern" \
      || { echo "no fixture exercises: $pattern"; return 1; }
  done
}

@test "every BASH_WRITE_PATTERNS shape is detected" {
  local cmd
  for cmd in "${WRITE_FIXTURES[@]}"; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

@test "every READ_ONLY_AGENTS entry is exempt" {
  # Read off the table rather than restated, so a name added there is covered
  # the moment it is added and cannot be exempted without a test.
  local agent
  for agent in "${READ_ONLY_AGENTS[@]}"; do
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

# --- write shapes the table missed -----------------------------------------
#
# Each command below changes a file in the working tree and each was reported
# as no-write by the table. The git ones rewrite tracked files without any of
# the subcommands the alternation named; the interpreter ones matter because
# the harness's auto mode tells the model to prefer short scripts, so a
# one-liner is the path it is actively steered toward, not an evasion.

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
  # The exemption reads "an absolute path under /tmp". /tmp/../home/... is not
  # under /tmp - it names a file in the tree under review, reached through the
  # exemption.
  local cmd
  for cmd in 'printf x > /tmp/../home/sbj/Sandbox/unshittify/src/parser.c' \
             'printf x > /tmp/a/../../home/sbj/src/parser.c' \
             'printf x >> /var/tmp/../../home/sbj/src/parser.c'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

@test "a redirection to a path merely beginning with the temporary prefix requires the reviews" {
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
# None of these changes a file in the repository. Each costs four reviews on
# a turn that produced no diff to review, which is what teaches a user to
# route around the gate.

@test "installing dependencies is not a code change" {
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

@test "install as the command word is still a code change" {
  local cmd
  for cmd in 'install -m 755 x /usr/local/bin/x' \
             'mkdir build && install -m 644 hdr.h include/'; do
    run code_was_edited "$(shaped_event Bash command="$cmd")"
    [ "$status" -eq 0 ] || { echo "undetected write: $cmd"; return 1; }
  done
}

@test "creating a scratch file or directory under a temporary path is not a code change" {
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

@test "creating a file or directory in the working tree is still a code change" {
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
# CLAUDE.md states three laws for this computation and requires laws to be
# verified by property tests rather than examples. Each law was pinned by one
# fixed example, which is weaker than it reads: the monotonicity example
# compared only COUNTS, so dropping nst while adding tdd would have passed
# it, and the duplicate example duplicated a skill and asserted only that the
# result was empty.
#
# bats has no QuickCheck, so the generator below is written in bash. It
# varies the number of code changes, which of the required reviews are
# present, whether each is invoked as a skill or as its agent, how much
# read-only noise surrounds them, and the order of the lot. It is seeded from
# a fixed constant and advanced only through prng_next, so a trial that
# breaks a law is reproduced by rerunning the suite - which $RANDOM could not
# promise.
#
# One dimension is enumerated rather than sampled. Which reviews a turn
# already contains has sixteen values, and the monotonicity law is a
# statement about exactly that dimension, so that test walks all sixteen and
# generates the rest of each turn around them. The other two laws sample it
# along with everything else.

PRNG_SEED=20260829

# How many turns each sampled law generates. Every one of them writes a
# transcript and scans it, and bats runs a test body under a DEBUG trap that
# makes each simple command cost far more than in a plain shell, so these
# three tests already account for roughly a quarter of the suite's runtime
# (measured: 15 s of 53 s). Raise them to search harder - nothing else needs
# changing, and the seed keeps whatever they find reproducible. The
# monotonicity law takes its count from REVIEW_SUBSETS instead, since it
# enumerates that dimension.
TRIALS=8                    # duplicate-insensitivity
ORDER_TRIALS=5              # order-invariance: turns...
PERMUTATIONS_PER_TRIAL=3    # ...and orderings of each

prng_reset() { PRNG_STATE="$PRNG_SEED"; }

# prng_next <n>
#
# Advances a linear congruential generator and leaves its next value, reduced
# to [0, n), in PRNG_VALUE. It assigns to a global rather than printing
# because command substitution runs in a subshell: $(prng_next 4) would throw
# away the state advance and hand back the same number forever. The high bits
# are the ones used; an LCG's low bits have a short period.
prng_next() {
  PRNG_STATE=$(( (PRNG_STATE * 1103515245 + 12345) % 2147483648 ))
  PRNG_VALUE=$(( (PRNG_STATE / 65536) % $1 ))
}

# An event spec is a tool name, optionally followed by "|" and the one
# argument that decides what that tool did: a Bash command, or a subagent
# type. The two tables are the generator's alphabet; event_line below turns
# one spec into the transcript line for it.
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
# Sets up what the three law tests share: SPEC_LINE, every spec's transcript
# line encoded once; PROMPT_LINE, the turn's opening prompt; and
# REVIEW_SUBSETS, how many subsets of the required reviews there are. Each
# encoded line costs a jq process and the trials ask for the same twenty-odd
# specs hundreds of times, so encoding them on demand made these three tests
# the slowest thing in the suite by a wide margin.
#
# All of it belongs in a function rather than at file scope, for two separate
# reasons:
#
#   REQUIRED_REVIEWS  is not in scope until setup() sources the hook, which
#                     happens after the file's top level has run. A count
#                     taken there counts an empty array: REVIEW_SUBSETS came
#                     out as 1, and the generator produced turns containing
#                     no review at all while every test still passed.
#   SPEC_LINE         must be declared -g. bats runs each @test in its own
#                     shell, and a file-scope `declare -A` does not reach it;
#                     the name arrives as an ordinary indexed array, where
#                     SPEC_LINE[Edit] is arithmetic on an unset variable
#                     rather than a string key.
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
# or its matching agent (form 1). Read off REQUIRED_REVIEWS, so adding a
# required review extends the generated space with no change here.
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
# Permutes the global SPECS in place, Fisher-Yates over the same seeded
# generator. In place, and not through a pipeline, because a process
# substitution or command substitution would advance PRNG_STATE in a subshell
# and lose it.
shuffle_specs() {
  local i j tmp
  for ((i = ${#SPECS[@]} - 1; i > 0; i--)); do
    prng_next $((i + 1)); j="$PRNG_VALUE"
    tmp="${SPECS[$i]}"; SPECS[$i]="${SPECS[$j]}"; SPECS[$j]="$tmp"
  done
}

# gen_turn_with_reviews <mask>
#
# Generates one turn into the global SPECS: zero to two code changes, the
# required reviews whose bit is set in <mask> each in a generated form, one
# to three read-only events, shuffled together. Which reviews are present is
# the caller's to choose so that a test can enumerate that dimension instead
# of sampling it; everything else about the turn is generated.
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
# gen_turn_with_reviews over a generated subset, for the laws whose statement
# does not single that dimension out.
gen_turn_specs() {
  prng_next "$REVIEW_SUBSETS"
  gen_turn_with_reviews "$PRNG_VALUE"
}

# insert_spec_repeated <count> <spec>
#
# Inserts <spec> into the global SPECS at <count> generated positions, so the
# repeats are scattered through the turn rather than sitting adjacent.
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
# review per line, sorted - the laws below are about SETS, so every
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
# The newline-separated <set> with <line> removed if it is a member, in the
# same order. Written in bash rather than as a grep -Fxv so an empty set,
# which is the commonest one here, needs no special case and no `|| true`
# around a grep that found nothing.
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
# How missing_reviews names required review <index> when it reports it.
review_line_for() {
  printf '%s (skill) or %s (agent)' \
    "${REQUIRED_REVIEWS[$1]%%|*}" "${REQUIRED_REVIEWS[$1]##*|}"
}

@test "law: appending a satisfying event removes exactly that review from the missing set" {
  prng_reset
  prepare_generator
  # Exhaustive over which reviews the turn already contains - all sixteen
  # subsets - with the rest of each turn generated. That dimension is what
  # the law is about and it is small enough to enumerate, so which review is
  # appended is cycled over it rather than sampled: the subset that contains
  # neither tdd nor nst, with tdd appended, is the case that catches a
  # computation dropping nst as a side effect, and enumerating guarantees it
  # is reached.
  local present idx before after expected
  for ((present = 0; present < REVIEW_SUBSETS; present++)); do
    gen_turn_with_reviews "$present"
    before="$(missing_set "${SPECS[@]}")"

    idx=$(( present % ${#REQUIRED_REVIEWS[@]} ))
    prng_next 2
    after="$(missing_set "${SPECS[@]}" "$(review_spec "$idx" "$PRNG_VALUE")")"

    # The law as CLAUDE.md states it is a subset: missing(T ++ [e]) is
    # contained in missing(T). Asserted here as the exact set instead,
    # because subset alone still admits the failure this test exists to
    # catch - dropping nst while adding tdd shrinks the set and passes.
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

@test "law: the missing set is the same for every ordering of a turn's events" {
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

@test "law: repeating a review event decides the same as invoking it once" {
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
