#!/usr/bin/env bats
# Tests of hooks/report-dead-jobs.sh, the backup reader of the job registry.
# It runs on Stop and on UserPromptSubmit. Each fixture is a job that the
# registry library writes into a throwaway registry.

load helpers

setup() {
  HOOK="${HOOKS_DIR}/report-dead-jobs.sh"
  # shellcheck source=../../hooks/lib/job-registry.sh disable=SC1091
  source "${HOOKS_DIR}/lib/job-registry.sh"
  export CLAUDE_JOB_REGISTRY; CLAUDE_JOB_REGISTRY="$(fixture_dir)/registry"
  NOW="$(registry_now)"
}

# make_job <name> <start-time> <interval> [exit-status] [cwd]
make_job() {
  local dir="${CLAUDE_JOB_REGISTRY}/$1"
  mkdir -p "$dir"
  registry_write_start "$dir" 1 "$3" "$2" "cmd $1" "${5:-/work}"
  [ -z "${4:-}" ] || registry_write_exit "$dir" "$2" "$4"
}

stop_payload() { stdin_payload hook_event_name=Stop cwd=/work; }
prompt_payload() { stdin_payload hook_event_name=UserPromptSubmit cwd=/work; }

# fails <command ...>
#
# Succeeds when the command fails. A line that starts with "!" does not stop
# a bats test, so a test uses this function for a decision that must fail.
fails() {
  ! "$@"
}

# odd_directory <seed>
#
# Prints a path of one to three components. A component holds one to four
# characters from an alphabet with a space, a backslash, a tab, "+", "[",
# and "*". A reader that changes one of these loses the directory.
odd_directory() {
  local alphabet=(a b ' ' $'\\' $'\t' '+' '[' '*') depth length i j out=""
  RANDOM=$1
  depth=$((RANDOM % 3 + 1))
  for ((i = 0; i < depth; i++)); do
    out+="/"
    length=$((RANDOM % 4 + 1))
    for ((j = 0; j < length; j++)); do out+="${alphabet[RANDOM % ${#alphabet[@]}]}"; done
  done
  printf '%s' "$out"
}

@test "Stop: a job that ended blocks the end of the turn with its report" {
  make_job a "$NOW" 30 2
  run_hook "$HOOK" "$(stop_payload)"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"cmd a"* ]]
  [[ "$(reason_field "$output")" == *"ended 2"* ]]
}

@test "Stop: a stale job blocks the end of the turn" {
  make_job a "$((NOW - 1000))" 1
  run_hook "$HOOK" "$(stop_payload)"
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"stale"* ]]
}

@test "Stop: a job that is alive gives no output and gets no marker" {
  make_job a "$NOW" 30
  run_hook "$HOOK" "$(stop_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  fails registry_is_reported "${CLAUDE_JOB_REGISTRY}/a"
}

@test "Stop: no registry gives no output" {
  run_hook "$HOOK" "$(stop_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "UserPromptSubmit: a dead job gives the report as plain text" {
  make_job a "$NOW" 30 2
  run_hook "$HOOK" "$(prompt_payload)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd a"* ]]
  [[ "$output" == *"ended 2"* ]]
  run jq -e . <<< "$output"
  [ "$status" -ne 0 ]
}

@test "law: a job that the hook reported is not reported again" {
  make_job a "$NOW" 30 2
  run_hook "$HOOK" "$(stop_payload)"
  registry_is_reported "${CLAUDE_JOB_REGISTRY}/a"
  run_hook "$HOOK" "$(stop_payload)"
  [ -z "$output" ]
  run_hook "$HOOK" "$(prompt_payload)"
  [ -z "$output" ]
}

@test "a job that the hook reported as stale is reported one more time when it gets an exit record" {
  make_job a "$((NOW - 1000))" 1
  run_hook "$HOOK" "$(stop_payload)"
  [[ "$(reason_field "$output")" == *"class: stale"* ]]
  run_hook "$HOOK" "$(stop_payload)"
  [ -z "$output" ]
  registry_write_exit "${CLAUDE_JOB_REGISTRY}/a" "$NOW" 4
  run_hook "$HOOK" "$(stop_payload)"
  [[ "$(reason_field "$output")" == *"class: ended 4"* ]]
  [ "$(registry_reported_class "${CLAUDE_JOB_REGISTRY}/a")" = "ended" ]
  run_hook "$HOOK" "$(stop_payload)"
  [ -z "$output" ]
  run_hook "$HOOK" "$(prompt_payload)"
  [ -z "$output" ]
}

@test "law: a stale job is reported one time, also with an exit file that holds no number as the status" {
  local value dir="${CLAUDE_JOB_REGISTRY}/a"
  for value in false true '""' '"x"' null '[1]'; do
    rm -rf "$CLAUDE_JOB_REGISTRY"
    make_job a "$((NOW - 1000))" 1
    printf '{"record":"exit","time":5,"status":%s}\n' "$value" > "$dir/exit"
    run_hook "$HOOK" "$(stop_payload)"
    [[ "$(reason_field "$output")" == *"class: stale"* ]] || { echo "status ${value}: ${output}"; return 1; }
    [ "$(registry_reported_class "$dir")" = "stale" ] || { echo "status ${value}: the marker"; return 1; }
    run_hook "$HOOK" "$(stop_payload)"
    [ -z "$output" ] || { echo "status ${value}: a second report"; return 1; }
  done
}

@test "a start record with a directory that is not text does not hide the job of the session" {
  # The name "good" sorts after "bad", so the hook reads the bad record first.
  make_job good "$NOW" 30 2
  mkdir -p "${CLAUDE_JOB_REGISTRY}/bad"
  printf '{"record":"start","cwd":7,"time":1,"interval":30}\n' > "${CLAUDE_JOB_REGISTRY}/bad/start"
  run_hook "$HOOK" "$(stop_payload)"
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"cmd good"* ]]
}

@test "the marker holds the class that the hook reported" {
  make_job a "$NOW" 30 0
  make_job b "$((NOW - 1000))" 1
  run_hook "$HOOK" "$(stop_payload)"
  [ "$(registry_reported_class "${CLAUDE_JOB_REGISTRY}/a")" = "ended" ]
  [ "$(registry_reported_class "${CLAUDE_JOB_REGISTRY}/b")" = "stale" ]
}

@test "a job that started above the directory of the session is reported" {
  make_job a "$NOW" 30 2 /
  make_job b "$NOW" 30 3 /work
  run_hook "$HOOK" "$(stdin_payload hook_event_name=Stop cwd=/work/tests)"
  [[ "$(reason_field "$output")" == *"cmd a"* ]]
  [[ "$(reason_field "$output")" == *"cmd b"* ]]
}

@test "a job of a directory whose name only starts with the name of the session directory is not reported" {
  make_job a "$NOW" 30 2 /workshop
  run_hook "$HOOK" "$(stop_payload)"
  [ -z "$output" ]
}

@test "each dead job is in one report" {
  make_job a "$NOW" 30 0
  make_job b "$((NOW - 1000))" 1
  run_hook "$HOOK" "$(stop_payload)"
  [[ "$(reason_field "$output")" == *"cmd a"* ]]
  [[ "$(reason_field "$output")" == *"cmd b"* ]]
}

@test "a job of a different directory is not reported" {
  make_job a "$NOW" 30 2 /elsewhere
  run_hook "$HOOK" "$(stop_payload)"
  [ -z "$output" ]
  fails registry_is_reported "${CLAUDE_JOB_REGISTRY}/a"
}

@test "a session directory with a backslash gets its own job" {
  make_job a "$NOW" 30 2 '/w/a\b'
  run_hook "$HOOK" "$(stdin_payload hook_event_name=Stop 'cwd=/w/a\b')"
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"cmd a"* ]]
}

@test "law: a session directory with a space, a backslash, a tab, or a pattern character gets its own job" {
  local seed directory
  for seed in $(seq 1 20); do
    directory="$(odd_directory "$seed"; printf 'x')"; directory="${directory%x}"
    rm -rf "$CLAUDE_JOB_REGISTRY"
    make_job a "$NOW" 30 2 "$directory"
    run_hook "$HOOK" "$(stdin_payload hook_event_name=Stop "cwd=${directory}")"
    [[ "$(reason_field "$output")" == *"cmd a"* ]] || { echo "seed ${seed}: '${directory}'"; return 1; }
  done
}

@test "a payload with no directory uses the directory of the hook process" {
  make_job a "$NOW" 30 2 "$PWD"
  run_hook "$HOOK" "$(stdin_payload hook_event_name=Stop)"
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"cmd a"* ]]
}

@test "law: the hook reports exactly the jobs that are not alive, one time" {
  local seed i count expected name
  for seed in 1 2 3 5 8; do
    RANDOM=$seed
    rm -rf "$CLAUDE_JOB_REGISTRY"; expected=()
    count=$((RANDOM % 5 + 1))
    for ((i = 0; i < count; i++)); do
      case $((RANDOM % 3)) in
        0) make_job "s${seed}j${i}" "$NOW" 30 ;;
        1) make_job "s${seed}j${i}" "$((NOW - 1000))" 1; expected+=("s${seed}j${i}") ;;
        2) make_job "s${seed}j${i}" "$NOW" 30 $((RANDOM % 256)); expected+=("s${seed}j${i}") ;;
      esac
    done
    run_hook "$HOOK" "$(prompt_payload)"
    for ((i = 0; i < count; i++)); do
      name="s${seed}j${i}"
      if [[ " ${expected[*]} " == *" ${name} "* ]]; then
        [[ "$output" == *"cmd ${name}"$'\n'* ]] || { echo "seed ${seed}: ${name} is absent"; return 1; }
      else
        [[ "$output" != *"cmd ${name}"$'\n'* ]] || { echo "seed ${seed}: ${name} is alive"; return 1; }
      fi
    done
    run_hook "$HOOK" "$(prompt_payload)"
    [ -z "$output" ] || { echo "seed ${seed}: a second report"; return 1; }
  done
}

# jq_with_no_stop_output
#
# Makes a stand-in for jq and prints the directory that holds it. The
# stand-in fails for the call that prints the decision of a Stop, which is
# the only call with the argument "reason". It runs the real jq for each
# other call.
jq_with_no_stop_output() {
  local bin; bin="$(fixture_dir)/bin"
  mkdir -p "$bin"
  # shellcheck disable=SC2016 # The stand-in expands the "$" names, not this shell.
  printf '#!/bin/sh\nfor a in "$@"; do [ "$a" != reason ] || exit 5; done\nexec "%s" "$@"\n' \
    "$(command -v jq)" > "$bin/jq"
  chmod +x "$bin/jq"
  printf '%s' "$bin"
}

@test "Stop: a print that fails gives the status 1, no output, and no marker" {
  make_job a "$NOW" 30 2
  make_job b "$((NOW - 1000))" 1
  local bin; bin="$(jq_with_no_stop_output)"
  PATH="${bin}:${PATH}" run_hook "$HOOK" "$(stop_payload)"
  # The harness reads the status 2 as a block, so the status must be 1.
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  fails registry_is_reported "${CLAUDE_JOB_REGISTRY}/a"
  fails registry_is_reported "${CLAUDE_JOB_REGISTRY}/b"
  run_hook "$HOOK" "$(stop_payload)"
  [ "$(decision_field "$output")" = "block" ]
  [[ "$(reason_field "$output")" == *"cmd a"* ]]
}

@test "UserPromptSubmit: a print that fails gives the status 1 and no marker" {
  make_job a "$NOW" 30 2
  run bash -c 'printf "%s" "$1" | "$2" >&-' _ "$(prompt_payload)" "$HOOK"
  [ "$status" -eq 1 ]
  fails registry_is_reported "${CLAUDE_JOB_REGISTRY}/a"
}

@test "the hook finds its libraries when its path holds no slash" {
  make_job a "$NOW" 30 2
  cd "$HOOKS_DIR"
  run bash -c 'printf "%s" "$1" | bash report-dead-jobs.sh' _ "$(stop_payload)"
  [ "$status" -eq 0 ]
  [ "$(decision_field "$output")" = "block" ]
}

@test "a payload that the hook cannot parse gives no output and no error" {
  make_job a "$NOW" 30 2
  run_hook "$HOOK" "not json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
