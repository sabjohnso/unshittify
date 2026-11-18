#!/usr/bin/env bats
# Tests of hooks/lib/job-report.sh, the text that tells the model about a
# background job, and the sequence that reports the dead jobs. The watcher
# and the report hook print the same text.

load helpers

setup() {
  # shellcheck source=../../hooks/lib/job-registry.sh disable=SC1091
  source "${HOOKS_DIR}/lib/job-registry.sh"
  # shellcheck source=../../hooks/lib/job-report.sh disable=SC1091
  source "${HOOKS_DIR}/lib/job-report.sh"
  ROOT="$(fixture_dir)/reg"
}

# make_job <name> <start-time> [exit-status]
make_job() {
  mkdir -p "$ROOT/$1"
  registry_write_start "$ROOT/$1" 1 30 "$2" "cmd $1" "/work"
  [ -z "${3:-}" ] || registry_write_exit "$ROOT/$1" "$2" "$3"
}

# fails <command ...>
#
# Succeeds when the command fails. A line that starts with "!" does not stop
# a bats test, so a test uses this function for a decision that must fail.
fails() {
  ! "$@"
}

# print_plain <reports>
#
# A printer for report_dead_jobs. It prints the reports unchanged.
print_plain() {
  printf '%s\n' "$1"
}

# print_nothing <reports>
#
# A printer for report_dead_jobs that fails.
print_nothing() {
  return 1
}

@test "the report of a job names the command, the class, and the log" {
  make_job a 1000
  run report_dead_jobs print_plain 5000 "$ROOT/a"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd a"* ]]
  [[ "$output" == *"class: stale"* ]]
  [[ "$output" == *"$(registry_log_path "$ROOT/a")"* ]]
}

@test "the report holds the last three beats and not an older one" {
  make_job a 1000
  local time
  for time in 1010 1020 1030 1040; do registry_write_beat "$ROOT/a" "$time" "$time" 99; done
  run report_dead_jobs print_plain 5000 "$ROOT/a"
  [[ "$output" != *"cpu_ms=1010"* ]]
  [[ "$output" == *"time=1020 cpu_ms=1020 log_bytes=99"* ]]
  [[ "$output" == *"time=1040 cpu_ms=1040 log_bytes=99"* ]]
}

@test "the reports of several jobs hold each job, and each marker holds the class in the report" {
  make_job a 1000 3
  make_job b 1000
  run report_dead_jobs print_plain 5000 "$ROOT/a" "$ROOT/b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd a"* ]]
  [[ "$output" == *"class: ended 3"* ]]
  [[ "$output" == *"cmd b"* ]]
  [ "$(registry_reported_class "$ROOT/a")" = "ended" ]
  [ "$(registry_reported_class "$ROOT/b")" = "stale" ]
}

@test "a job that is alive gets no report and no marker, and the status is 1" {
  make_job a 1000
  run report_dead_jobs print_plain 1010 "$ROOT/a"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  fails registry_is_reported "$ROOT/a"
}

@test "a printer that fails gives the status 2 and marks no job" {
  make_job a 1000 3
  make_job b 1000
  run report_dead_jobs print_nothing 5000 "$ROOT/a" "$ROOT/b"
  [ "$status" -eq 2 ]
  fails registry_is_reported "$ROOT/a"
  fails registry_is_reported "$ROOT/b"
}
