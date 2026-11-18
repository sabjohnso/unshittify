#!/usr/bin/env bats
# Tests of scripts/background-watch.sh, the watcher that exits when a job
# ends or a heartbeat is stale. Each fixture is a job that the registry
# library writes into a throwaway registry. No test starts a real wrapper.

load helpers

setup() {
  WATCHER="${SCRIPTS_DIR}/background-watch.sh"
  # shellcheck source=../../hooks/lib/job-registry.sh disable=SC1091
  source "${SCRIPTS_DIR}/../hooks/lib/job-registry.sh"
  export CLAUDE_JOB_REGISTRY; CLAUDE_JOB_REGISTRY="$(fixture_root)"
  WORK="$(fixture_root)"
  cd "$WORK" || return
  NOW="$(registry_now)"
  # The watcher waits for one interval when it finds no job. One second
  # keeps that wait short.
  export CLAUDE_JOB_INTERVAL=1
}

# make_job <name> <start-time> <interval> [exit-status] [cwd]
make_job() {
  local dir="${CLAUDE_JOB_REGISTRY}/$1"
  mkdir -p "$dir"
  registry_write_start "$dir" 1 "$3" "$2" "cmd $1" "${5:-$WORK}"
  [ -z "${4:-}" ] || registry_write_exit "$dir" "$2" "$4"
}

# fails <command ...>
#
# Succeeds when the command fails. A line that starts with "!" does not stop
# a bats test, so a test uses this function for a decision that must fail.
fails() {
  ! "$@"
}

@test "with no job, the watcher waits for one interval, then says so and exits" {
  local before=$SECONDS
  run "$WATCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No background job"* ]]
  [ $((SECONDS - before)) -ge 1 ]
}

# A wait of one second can show as two seconds on a clock of full seconds.
# Thus the interval is 3, and a fixed wait of one second fails this test.
@test "the wait for a job is as long as the interval, not a fixed time" {
  local before=$SECONDS
  CLAUDE_JOB_INTERVAL=3 run "$WATCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No background job"* ]]
  [ $((SECONDS - before)) -ge 3 ]
}

@test "the watcher watches a job that starts in the wait" {
  ( sleep 0.3; make_job a "$NOW" 30 2 ) &
  run "$WATCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd a"* ]]
  [[ "$output" == *"ended 2"* ]]
  [[ "$output" != *"No background job"* ]]
}

@test "an interval that is not valid makes the watcher exit with the status 2 before it waits" {
  local before=$SECONDS
  CLAUDE_JOB_INTERVAL=30s run "$WATCHER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"CLAUDE_JOB_INTERVAL"* ]]
  [[ "$output" != *"No background job"* ]]
  [ $((SECONDS - before)) -le 1 ]
  make_job a "$NOW" 30 2
  CLAUDE_JOB_INTERVAL=0 run "$WATCHER"
  [ "$status" -eq 2 ]
  fails registry_is_reported "${CLAUDE_JOB_REGISTRY}/a"
}

@test "a job that the watcher reported as stale is reported one more time when it gets an exit record" {
  make_job a "$((NOW - 1000))" 1
  run "$WATCHER"
  [[ "$output" == *"class: stale"* ]]
  [ "$(registry_reported_class "${CLAUDE_JOB_REGISTRY}/a")" = "stale" ]
  run "$WATCHER"
  [[ "$output" == *"No background job"* ]]
  registry_write_exit "${CLAUDE_JOB_REGISTRY}/a" "$NOW" 4
  run "$WATCHER"
  [[ "$output" == *"class: ended 4"* ]]
  [ "$(registry_reported_class "${CLAUDE_JOB_REGISTRY}/a")" = "ended" ]
  run "$WATCHER"
  [[ "$output" == *"No background job"* ]]
}

@test "a job that started above the current directory is watched" {
  make_job a "$NOW" 30 2
  mkdir -p "$WORK/tests/deep"
  cd "$WORK/tests/deep" || return
  run "$WATCHER"
  [[ "$output" == *"cmd a"* ]]
  [[ "$output" == *"ended 2"* ]]
}

@test "a job that ended is reported with its status and then marked" {
  make_job a "$NOW" 30 2
  run "$WATCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd a"* ]]
  [[ "$output" == *"ended 2"* ]]
  registry_is_reported "${CLAUDE_JOB_REGISTRY}/a"
}

@test "a print that fails gives the status 2 and no marker, and the next watcher reports the job" {
  make_job a "$NOW" 30 2
  run bash -c '"$1" >&-' _ "$WATCHER"
  [ "$status" -eq 2 ]
  fails registry_is_reported "${CLAUDE_JOB_REGISTRY}/a"
  run "$WATCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ended 2"* ]]
}

@test "the watcher finds its libraries when its path holds no slash" {
  make_job a "$NOW" 30 2
  cd "$SCRIPTS_DIR"
  run bash background-watch.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"No background job"* ]]
  fails registry_is_reported "${CLAUDE_JOB_REGISTRY}/a"
}

@test "a job with a stale heartbeat is reported" {
  make_job a "$((NOW - 1000))" 1
  run "$WATCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale"* ]]
}

@test "each dead job is in one report" {
  make_job a "$NOW" 30 0
  make_job b "$((NOW - 1000))" 1
  run "$WATCHER"
  [[ "$output" == *"cmd a"* ]]
  [[ "$output" == *"cmd b"* ]]
}

@test "the watcher waits for a job that is alive and exits when the job ends" {
  make_job a "$NOW" 1
  ( sleep 1.5; registry_write_exit "${CLAUDE_JOB_REGISTRY}/a" "$(registry_now)" 9 ) &
  local before=$SECONDS
  run "$WATCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ended 9"* ]]
  [ $((SECONDS - before)) -ge 1 ]
}

@test "between two reads, the watcher sleeps for the interval of the job, not for a fixed time" {
  # The stand-in records the argument of each sleep and then sleeps for a
  # short time. Thus the test does not wait for the 7 seconds of the job.
  local bin log real_sleep
  bin="$(fixture_root)"; log="${bin}/sleeps"; real_sleep="$(command -v sleep)"
  printf '#!/bin/sh\necho "$1" >> "%s"\nexec "%s" 0.3\n' "$log" "$real_sleep" > "${bin}/sleep"
  chmod +x "${bin}/sleep"
  make_job a "$NOW" 7
  ( "$real_sleep" 0.5; registry_write_exit "${CLAUDE_JOB_REGISTRY}/a" "$(registry_now)" 0 ) &
  PATH="${bin}:${PATH}" run "$WATCHER"
  wait
  [ "$status" -eq 0 ]
  [[ "$output" == *"ended 0"* ]]
  grep -qx 7 "$log"
  fails grep -qvx 7 "$log"
}

@test "a job of a different directory is not watched" {
  make_job a "$NOW" 30 2 /elsewhere
  run "$WATCHER"
  [[ "$output" == *"No background job"* ]]
  fails registry_is_reported "${CLAUDE_JOB_REGISTRY}/a"
}

@test "law: a job that the watcher reported is not reported again" {
  make_job a "$NOW" 30 2
  run "$WATCHER"
  run "$WATCHER"
  [[ "$output" != *"cmd a"* ]]
}
