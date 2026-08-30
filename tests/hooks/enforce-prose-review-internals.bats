#!/usr/bin/env bats
# Unit tests against the internal functions of enforce-prose-review.sh,
# exercised by sourcing the script (its BASH_SOURCE guard means sourcing it
# does not run main / does not read stdin) and calling prose_word_count and
# unreviewed_prose_word_count directly - no stdin JSON payload involved.

load helpers

setup() {
  SCRIPT="${HOOKS_DIR}/enforce-prose-review.sh"
  # shellcheck source=/dev/null
  source "$SCRIPT"
}

# fenced_code_message
#
# A response that is one fenced code block and nothing else - the shape every
# answer takes whose content is a script. It carries no prose at all, yet its
# tokens are words to `wc -w`.
fenced_code_message() {
  cat <<'MSG'
```bash
review_satisfied() {
  local events="$1" skill_name="$2" agent_name="$3"
  printf '%s\n' "$events" \
    | jq -e -s --arg s "$skill_name" --arg a "$agent_name" \
        'any(.[]; .skill == $s or .subagent_type == $a)' >/dev/null 2>&1
}

missing_reviews() {
  local entry
  for entry in "${REQUIRED_REVIEWS[@]}"; do
    review_satisfied "$1" "${entry%%|*}" "${entry##*|}" || echo "${entry}"
  done
}
```
MSG
}

@test "sourcing the script does not execute main or read stdin" {
  # If main() ran, it would call `cat` and block waiting on this test's
  # stdin (a tty/empty pipe here); reaching this assertion at all proves it
  # didn't run.
  [ "$(type -t main)" = "function" ]
}

# --- prose_word_count counts prose, not code -------------------------------
#
# The threshold (MIN_WORDS) is calibrated for prose. Counting code against it
# is a category error: a response that is one 80-token code block has no prose
# in it to review, and demanding a prose review of it teaches the user that
# the gate fires at random.

@test "a response that is one fenced code block has no prose words" {
  # The fixture is well over MIN_WORDS by `wc -w`, which is the whole defect.
  local message
  message="$(fenced_code_message)"
  [ "$(printf '%s' "$message" | wc -w)" -ge "$MIN_WORDS" ]
  [ "$(prose_word_count "$message")" -eq 0 ]
}

@test "a fenced block does not inflate the count of the prose around it" {
  local message
  message="$(printf '%s\n%s\n' 'Here is the fix.' "$(fenced_code_message)")"
  [ "$(prose_word_count "$message")" -eq 4 ]
}

@test "a ~~~ fence is stripped like a backtick fence" {
  local message
  message=$'Here is the fix.\n~~~\nint main(void) { return compute(argc, argv); }\n~~~\n'
  [ "$(prose_word_count "$message")" -eq 4 ]
}

@test "an inline code span does not inflate the count" {
  local message
  message='Call `missing_reviews_for_transcript "$transcript" "$start_line"` first.'
  [ "$(prose_word_count "$message")" -eq 2 ]
}

@test "prose is still counted in full when code sits beside it" {
  local prose message
  prose="$(printf 'word %.0s' $(seq 1 60))"
  message="$(printf '%s\n%s\n' "$prose" "$(fenced_code_message)")"
  [ "$(prose_word_count "$message")" -eq 60 ]
}

@test "an unterminated fence runs to the end of the message" {
  # The harness truncates a long final message mid-block, so the closing fence
  # is routinely absent. Counting the tail of a cut-off block as prose is the
  # same defect.
  local message
  message=$'Here is the fix.\n```bash\nfor entry in "${REQUIRED_REVIEWS[@]}"; do echo "${entry}"; done'
  [ "$(prose_word_count "$message")" -eq 4 ]
}

# --- laws of prose_word_count ----------------------------------------------
#
# The count decides whether the gate applies at all, so it owes the same kind
# of laws the other hooks' decision functions carry.

@test "monotonicity: appending a fenced code block never raises the count" {
  local prose before after
  prose='Here is the fix, and it is a short one.'
  before="$(prose_word_count "$prose")"
  after="$(prose_word_count "$(printf '%s\n%s\n' "$prose" "$(fenced_code_message)")")"
  [ "$after" -le "$before" ]
}

@test "idempotence: a second identical code block changes nothing" {
  local prose one two
  prose='Here is the fix, and it is a short one.'
  one="$(prose_word_count "$(printf '%s\n%s\n' "$prose" "$(fenced_code_message)")")"
  two="$(prose_word_count "$(printf '%s\n%s\n%s\n' "$prose" "$(fenced_code_message)" "$(fenced_code_message)")")"
  [ "$one" -eq "$two" ]
}

@test "code-only responses of any length stay below the threshold" {
  local i message
  message=""
  for i in 1 2 3 4 5 6 7 8; do
    message="${message}$(fenced_code_message)"$'\n'
  done
  [ "$(prose_word_count "$message")" -lt "$MIN_WORDS" ]
}

# --- the composed decision -------------------------------------------------

@test "unreviewed_prose_word_count: a code-only response is not blocked" {
  local transcript
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'show me the script')" \
    "$(tool_use_event Edit)")")"
  run unreviewed_prose_word_count "$(fenced_code_message)" "$transcript"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "unreviewed_prose_word_count: unreviewed prose reports its prose count" {
  local prose transcript
  prose="$(printf 'word %.0s' $(seq 1 60))"
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'please explain this at length')" \
    "$(tool_use_event Edit)")")"
  run unreviewed_prose_word_count "$(printf '%s\n%s\n' "$prose" "$(fenced_code_message)")" "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 60 ]
}

@test "unreviewed_prose_word_count: a reviewed response reports nothing" {
  local prose transcript
  prose="$(printf 'word %.0s' $(seq 1 60))"
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'please explain this at length')" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  run unreviewed_prose_word_count "$prose" "$transcript"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
