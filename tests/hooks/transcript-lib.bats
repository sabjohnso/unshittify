#!/usr/bin/env bats
# Unit tests for the shared transcript helpers in hooks/lib/transcript.sh,
# exercised by sourcing the library directly (it defines functions only, runs
# nothing) and calling find_turn_start_line / tool_use_events_since_turn_start
# against synthetic transcript fixtures.

load helpers

setup() {
  # shellcheck source=/dev/null
  source "${HOOKS_DIR}/lib/transcript.sh"
}

# --- find_turn_start_line -------------------------------------------------

@test "the last genuine user prompt is the boundary even when a marker follows it" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'do the thing')" \
    "$(tool_use_event Skill skill=communication:review-prose)" \
    "$(last_prompt_marker)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "a tool_result user message is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'do the thing')" \
    "$(tool_result_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "an isMeta injection is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'do the thing')" \
    "$(meta_injection_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "an array-content prompt is a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(tool_use_event Read)" \
    "$(user_prompt_array_event 'do the thing')")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "the most recent genuine prompt wins" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'first prompt')" \
    "$(tool_use_event Edit)" \
    "$(user_prompt_event 'second prompt')")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
}

@test "falls back to the last-prompt marker when no genuine prompt exists" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "an empty transcript returns 1 and is silent" {
  transcript="$(mktemp "$(fixture_dir)/empty.XXXXXX.jsonl")"
  : > "$transcript"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a non-empty transcript with no prompt or marker returns 1 and warns" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no user prompt or last-prompt marker in non-empty transcript"* ]]
}

# --- tool_use_events_since_turn_start -------------------------------------

@test "emits one shaped event per tool_use since the turn start" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(user_prompt_event 'do and review')" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Skill skill=development:review-nst)" \
    "$(tool_use_event Agent subagent_type=nst-reviewer)")")"
  run tool_use_events_since_turn_start "$transcript"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '"name":"Edit"')" -eq 1 ]
  [[ "$output" == *'"skill":"development:review-nst"'* ]]
  [[ "$output" == *'"subagent_type":"nst-reviewer"'* ]]
}

@test "emits nothing on stdout when there is no turn start" {
  transcript="$(write_transcript "$(tool_use_event Edit)")"
  # stderr carries the schema-anomaly warning; stdout must be empty.
  result="$(tool_use_events_since_turn_start "$transcript" 2>/dev/null)"
  [ -z "$result" ]
}

@test "excludes tool_use events that precede the turn boundary" {
  # A review from a previous turn (before the current prompt) must not count.
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(tool_use_event Skill skill=development:review-nst)" \
    "$(user_prompt_event 'now do the work')" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Skill skill=development:review-tdd)")")"
  run tool_use_events_since_turn_start "$transcript"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"skill":"development:review-nst"'* ]]
  [[ "$output" == *'"skill":"development:review-tdd"'* ]]
  [[ "$output" == *'"name":"Edit"'* ]]
}

# A half-written trailing line is the normal case, not an exotic one: the
# harness appends to the transcript while the hook reads it. Losing the events
# already scanned because the last line arrived incomplete tells
# enforce-code-review.sh that nothing was edited, which is fail-open.
@test "a malformed line is skipped and the events around it survive" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(user_prompt_event 'do the work')" \
    "$(tool_use_event Edit)" \
    '{"type":"assistant","message":{"content":[{"type":"tool_' \
    "$(tool_use_event Read)")")"
  result="$(tool_use_events_since_turn_start "$transcript" 2>/dev/null)"
  [[ "$result" == *'"name":"Edit"'* ]]
  [[ "$result" == *'"name":"Read"'* ]]
}

@test "a malformed line after the boundary is still reported on stderr" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'do the work')" \
    "$(tool_use_event Edit)" \
    'this is not json')")"
  run tool_use_events_since_turn_start "$transcript"
  [[ "$output" == *"malformed"* ]]
}

@test "a warning never reaches stdout as an event" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event 'do the work')" \
    "$(tool_use_event Edit)" \
    'this is not json')")"
  result="$(tool_use_events_since_turn_start "$transcript" 2>/dev/null)"
  run bash -c 'printf "%s" "$1" | jq -e -c . >/dev/null' _ "$result"
  [ "$status" -eq 0 ]
}

# --- tool_use_events_since_line --------------------------------------------

@test "tool_use_events_since_line starts at the given line, not the turn boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(tool_use_event Edit)" \
    "$(user_prompt_event 'do the work')" \
    "$(tool_use_event Read)")")"
  run tool_use_events_since_line "$transcript" 3
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"Read"'* ]]
  [[ "$output" != *'"name":"Edit"'* ]]
}

# --- agent_invoked_since_line -----------------------------------------------

@test "agent_invoked_since_line succeeds on an exact subagent_type match" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  run agent_invoked_since_line "$transcript" 1 communication:prose-reviewer
  [ "$status" -eq 0 ]
}

@test "agent_invoked_since_line fails on a near-miss name" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer-preview)")")"
  run agent_invoked_since_line "$transcript" 1 communication:prose-reviewer
  [ "$status" -ne 0 ]
}

@test "agent_invoked_since_line fails when only a skill by the same name ran" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Skill skill=communication:prose-reviewer)")")"
  run agent_invoked_since_line "$transcript" 1 communication:prose-reviewer
  [ "$status" -ne 0 ]
}

@test "agent_invoked_since_line is duplicate-insensitive" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  run agent_invoked_since_line "$transcript" 1 communication:prose-reviewer
  [ "$status" -eq 0 ]
}

@test "agent_invoked_since_line ignores invocations before the start line" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(user_prompt_event)" \
    "$(tool_use_event Edit)")")"
  run agent_invoked_since_line "$transcript" 2 communication:prose-reviewer
  [ "$status" -ne 0 ]
}

# --- transcript_judgeable ---------------------------------------------------

@test "transcript_judgeable fails on an empty path" {
  run transcript_judgeable ""
  [ "$status" -ne 0 ]
}

@test "transcript_judgeable fails on a nonexistent file" {
  run transcript_judgeable /nonexistent/transcript.jsonl
  [ "$status" -ne 0 ]
}

@test "transcript_judgeable succeeds on an existing file" {
  transcript="$(write_transcript "$(user_prompt_event)")"
  run transcript_judgeable "$transcript"
  [ "$status" -eq 0 ]
}

# --- harness injections are not turn boundaries ---------------------------
#
# A boundary must be a message the USER actually sent. The harness records
# several of its own messages in the user role with plain string content;
# each one that is treated as a boundary silently discards the evidence of
# everything the assistant did before it in the same turn.
#
# The task-notification case is the damaging one, and it is not hypothetical:
# it is written after the Agent tool_use that spawned the subagent, so an
# asynchronously delegated review can never be seen by a hook that anchors on
# the last qualifying user message.

@test "a task notification is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(typed_prompt_event 'review this project')" \
    "$(tool_use_event Agent subagent_type=communication:prose-reviewer)" \
    "$(task_notification_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "a delegated review stays visible after its completion notification" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(typed_prompt_event 'review this project')" \
    "$(tool_use_event Agent subagent_type=communication:prose-reviewer)" \
    "$(task_notification_event)")")"
  start_line="$(find_turn_start_line "$transcript")"
  run agent_invoked_since_line "$transcript" "$start_line" communication:prose-reviewer
  [ "$status" -eq 0 ]
}

@test "a slash-command marker is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'do the thing')" \
    "$(slash_command_marker_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

# The content rule is the fallback for transcripts recorded before the origin
# field existed, so it must recognise the wrapper tag wherever the harness put
# it in the leading whitespace. ltrimstr removes its argument exactly once, so
# a second leading newline (or a leading space) left the tag unrecognised and
# the injection acting as a boundary - moving the turn start FORWARD, past the
# delegation, which is the one direction this rule must never move it.

@test "a wrapper tag behind two newlines is not a boundary" {
  injection="$(jq -nc '{type:"user", message:{role:"user",
    content:"\n\n<task-notification>\n<status>completed</status>\n</task-notification>"}}')"
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(typed_prompt_event 'review this project')" \
    "$(tool_use_event Agent subagent_type=communication:prose-reviewer)" \
    "$injection")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "a wrapper tag behind a leading space is not a boundary" {
  injection="$(jq -nc '{type:"user", message:{role:"user",
    content:" <system-reminder>context</system-reminder>"}}')"
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(typed_prompt_event 'review this project')" \
    "$(tool_use_event Agent subagent_type=communication:prose-reviewer)" \
    "$injection")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "local command stdout is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'do the thing')" \
    "$(local_command_stdout_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "a typed prompt after a task notification is still a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(typed_prompt_event 'first prompt')" \
    "$(task_notification_event)" \
    "$(typed_prompt_event 'second prompt')")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
}

@test "a plain string prompt with no origin field is still a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(tool_use_event Read)" \
    "$(user_prompt_event 'an older-format prompt with no origin recorded')")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# --- the boundary rule only ever moves the boundary earlier -----------------
#
# The rejection rules in find_turn_start_line are stated in the code and in
# CLAUDE.md as only ever moving the turn start EARLIER, which is what makes a
# misjudgement cost a redundant review rather than a missed one. A stated
# invariant with no test is exactly the gap this suite exists to close.

@test "rejecting a harness message never moves the boundary later" {
  local injection
  for injection in "$(task_notification_event)" \
                   "$(slash_command_marker_event)" \
                   "$(local_command_stdout_event)"; do
    transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
      "$(typed_prompt_event 'the real prompt')" \
      "$(tool_use_event Agent subagent_type=communication:prose-reviewer)" \
      "$injection")")"
    run find_turn_start_line "$transcript"
    [ "$status" -eq 0 ]
    [ "$output" -le 3 ]
    [ "$output" -eq 1 ]
  done
}

@test "appending harness messages is idempotent for the boundary" {
  local one many
  one="$(write_transcript "$(printf '%s\n%s\n' \
    "$(typed_prompt_event 'the real prompt')" \
    "$(task_notification_event)")")"
  many="$(write_transcript "$(printf '%s\n%s\n%s\n%s\n' \
    "$(typed_prompt_event 'the real prompt')" \
    "$(task_notification_event a1)" \
    "$(task_notification_event a2)" \
    "$(task_notification_event a3)")")"
  [ "$(find_turn_start_line "$one")" -eq "$(find_turn_start_line "$many")" ]
}

# --- one transcript object is one boundary verdict --------------------------
#
# The boundary is a LINE NUMBER, so the classifier's output and the file's
# lines must stay in step. A user message may carry several text blocks; a
# classifier that inspects the blocks rather than the message emits one
# verdict per block, and every line number after it is shifted forward. The
# boundary then lands past the turn's own tool calls, which is fail-open for
# both enforce hooks.

@test "a prompt of several text blocks is one boundary, not one per block" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_multiblock_event 4 'do the work')" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Skill skill=development:review-tdd)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "the events after a multi-block prompt are all still visible" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_multiblock_event 4 'do the work')" \
    "$(tool_use_event Edit)" \
    "$(tool_use_event Skill skill=development:review-tdd)")")"
  run tool_use_events_since_turn_start "$transcript"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"Edit"'* ]]
  [[ "$output" == *'"skill":"development:review-tdd"'* ]]
}

@test "the boundary never points past the end of the transcript" {
  local prompt
  for prompt in "$(user_prompt_event 'a plain string prompt')" \
                "$(typed_prompt_event 'a typed prompt')" \
                "$(user_prompt_array_event 'a one-block prompt')" \
                "$(user_prompt_multiblock_event 2)" \
                "$(user_prompt_multiblock_event 4)" \
                "$(user_prompt_multiblock_event 9)"; do
    transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
      "$prompt" \
      "$(tool_use_event Edit)" \
      "$(tool_use_event Read)")")"
    run find_turn_start_line "$transcript"
    [ "$status" -eq 0 ]
    [ "$output" -le "$(wc -l < "$transcript")" ]
  done
}

# --- the last-prompt fallback matches records, not quoted text --------------

@test "a tool_result embedding the last-prompt marker is not a boundary" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(tool_use_event Edit)" \
    "$(tool_result_embedding_marker_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 1 ]
}

@test "an embedded last-prompt marker never moves the boundary past a real one" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(last_prompt_marker)" \
    "$(tool_use_event Edit)" \
    "$(tool_result_embedding_marker_event)")")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

# --- schema drift in the boundary scan is visible ---------------------------
#
# The boundary classifier is the more load-bearing of the two scans: every
# hook anchors on it. A line it cannot read must be reported, not silently
# treated as "nothing here".

@test "the boundary scan reports a line it could not parse" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event 'do the work')" \
    'this is not json')")"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [[ "$output" == *"malformed"* ]]
}

# --- a partially written final line ----------------------------------------
#
# The harness appends while the hook reads, so the final line is routinely
# incomplete. Whatever the scan makes of it, the boundary must not land after
# the events of the turn it opens.

@test "a prompt on an unterminated final line does not push the boundary past it" {
  transcript="$(mktemp "$(fixture_dir)/partial.XXXXXX.jsonl")"
  printf '%s\n' "$(tool_use_event Edit)" > "$transcript"
  printf '%s' "$(user_prompt_event 'the newest prompt')" >> "$transcript"
  run find_turn_start_line "$transcript"
  [ "$status" -eq 0 ]
  [ "$output" -le 2 ]
}

# --- the boundary invariant, over generated transcripts ---------------------
#
# transcript.sh states the rule as a law: rejecting a harness-authored message
# only ever moves the turn start EARLIER, and an earlier boundary can only let
# a hook see more of the turn, never less. CLAUDE.md repeats it. It was pinned
# by fixed examples - three injection strings against one transcript shape,
# and six prompt shapes always followed by the same two lines - which is what
# let the boundary once run past the end of a three-line file.
#
# The generator below varies what the examples held constant: the transcript's
# length, how many harness messages are appended and in what order, and
# whether malformed lines are interleaved. It reuses the seeded-LCG idiom from
# enforce-code-review-internals.bats so a failing trial reproduces on a rerun.

BOUNDARY_SEED=20260830
BOUNDARY_TRIALS=12

boundary_prng_reset() { BOUNDARY_STATE="$BOUNDARY_SEED"; }

boundary_prng_next() {
  BOUNDARY_STATE=$(( (BOUNDARY_STATE * 1103515245 + 12345) % 2147483648 ))
  BOUNDARY_VALUE=$(( (BOUNDARY_STATE / 65536) % $1 ))
}

# One harness-authored line of each kind the boundary rule must reject, plus
# the two shapes that previously fooled it: a tool_result quoting the marker
# text, and a prompt carrying several text blocks.
harness_line() {
  case "$1" in
    0) task_notification_event ;;
    1) slash_command_marker_event ;;
    2) local_command_stdout_event ;;
    3) meta_injection_event ;;
    4) tool_result_embedding_marker_event ;;
    *) tool_result_event ;;
  esac
}

@test "law: the boundary never points past the end of the transcript" {
  boundary_prng_reset
  for _ in $(seq "$BOUNDARY_TRIALS"); do
    boundary_prng_next 4
    local blocks=$(( BOUNDARY_VALUE + 1 ))
    boundary_prng_next 5
    local injections="$BOUNDARY_VALUE"
    boundary_prng_next 3
    local trailing=$(( BOUNDARY_VALUE + 1 ))

    local lines
    lines="$(user_prompt_multiblock_event "$blocks")"
    for _ in $(seq 0 "$injections"); do
      boundary_prng_next 6
      lines="$(printf '%s\n%s' "$lines" "$(harness_line "$BOUNDARY_VALUE")")"
    done
    for _ in $(seq "$trailing"); do
      lines="$(printf '%s\n%s' "$lines" "$(tool_use_event Edit)")"
    done

    local transcript total start
    transcript="$(write_transcript "$lines")"
    total="$(wc -l < "$transcript")"
    start="$(find_turn_start_line "$transcript")"

    [ -n "$start" ] || {
      echo "no boundary (seed $BOUNDARY_SEED, blocks=$blocks injections=$injections)" >&2
      return 1
    }
    [ "$start" -ge 1 ] || {
      echo "boundary $start below 1 (seed $BOUNDARY_SEED)" >&2
      return 1
    }
    [ "$start" -le "$total" ] || {
      echo "boundary $start past EOF $total (seed $BOUNDARY_SEED, blocks=$blocks injections=$injections trailing=$trailing)" >&2
      return 1
    }
  done
}

@test "law: appending a harness message never moves the boundary later" {
  boundary_prng_reset
  for _ in $(seq "$BOUNDARY_TRIALS"); do
    boundary_prng_next 4
    local blocks=$(( BOUNDARY_VALUE + 1 ))

    local base
    base="$(printf '%s\n%s' \
      "$(user_prompt_multiblock_event "$blocks")" \
      "$(tool_use_event Edit)")"

    local before after grown
    before="$(find_turn_start_line "$(write_transcript "$base")")"

    grown="$base"
    boundary_prng_next 4
    local extra=$(( BOUNDARY_VALUE + 1 ))
    for _ in $(seq "$extra"); do
      boundary_prng_next 6
      grown="$(printf '%s\n%s' "$grown" "$(harness_line "$BOUNDARY_VALUE")")"
    done
    after="$(find_turn_start_line "$(write_transcript "$grown")")"

    [ "$after" -le "$before" ] || {
      echo "boundary moved later: $before -> $after (seed $BOUNDARY_SEED, blocks=$blocks extra=$extra)" >&2
      return 1
    }
  done
}
