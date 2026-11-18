#!/usr/bin/env bash
# Waits until a background job of this directory ends or its heartbeat is
# stale, then prints the report of each such job and exits.
#
#   scripts/background-watch.sh
#
# Start it with `run_in_background`. The harness starts the model when a
# background command exits, also after the turn ended. Thus the exit of this
# script is the event that tells the model about a dead job, and the model
# does not poll. The jobs are those that scripts/background-run.sh started
# in the current directory, below it, or above it.
#
# The watcher marks each job that it reports with the class that it
# reported. hooks/report-dead-jobs.sh is the backup reader of the same
# registry, and the marker stops a second report. A job that a reader
# reported as stale is reported one more time when it gets an exit record.
#
# The model starts the wrapper and the watcher in one message. Thus the
# watcher can start before the wrapper writes the start record. When the
# watcher finds no job, it waits for one interval and looks one more time.
# Only then does it say that no job exists.
#
# Environment:
#   CLAUDE_JOB_REGISTRY  the registry root (see registry_root)
#   CLAUDE_JOB_INTERVAL  the wait for a job that is not in the registry yet,
#                        in seconds (see registry_beat_interval)
set -euo pipefail

# The directory of this script. A path with no "/" is a script in the
# current directory. A parameter expansion starts no process.
case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) SCRIPT_DIR="." ;;
esac

# shellcheck source=../hooks/lib/job-registry.sh disable=SC1091
source "${SCRIPT_DIR}/../hooks/lib/job-registry.sh"
# shellcheck source=../hooks/lib/job-report.sh disable=SC1091
source "${SCRIPT_DIR}/../hooks/lib/job-report.sh"

main() {
  local wait
  if wait="$(registry_beat_interval)"; then
    watch_jobs "$(registry_root)" "$wait"
  else
    return 2
  fi
}

# watch_jobs <root> <wait>
#
# Reads the jobs of this directory until one is dead, then reports the dead
# jobs. With no job after the wait, it says so.
watch_jobs() {
  local root="$1" wait="$2" jobs status
  while :; do
    mapfile -t jobs < <(jobs_after_wait "$root" "$wait")
    if [ "${#jobs[@]}" -gt 0 ]; then
      status=0
      report_dead_jobs print_reports "$(registry_now)" "${jobs[@]}" || status=$?
      # The status 1 is the case of no dead job. The watcher then continues.
      # The status 2 is a print that failed, and the watcher exits with it.
      [ "$status" -eq 1 ] || return "$status"
      sleep "$(registry_shortest_interval "${jobs[@]}")"
    else
      printf 'No background job of %s is in the registry.\n' "$PWD"
      return 0
    fi
  done
}

# jobs_after_wait <root> <wait>
#
# Prints the jobs that the watcher must read. When it finds none, it waits
# for <wait> seconds and reads the registry one more time.
jobs_after_wait() {
  local root="$1" wait="$2" jobs
  jobs="$(registry_jobs_due "$root" "$PWD")"
  if [ -z "$jobs" ]; then
    sleep "$wait"
    jobs="$(registry_jobs_due "$root" "$PWD")"
  fi
  [ -z "$jobs" ] || printf '%s\n' "$jobs"
}

# print_reports <reports>
#
# Prints the reports, with an empty line after the last one.
print_reports() {
  printf '%s\n\n' "$1"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
