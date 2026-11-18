#!/usr/bin/env bash
# Stop and UserPromptSubmit hook. It reports each background job that ended
# or whose heartbeat is stale, when no reader reported that job before.
#
# scripts/background-watch.sh is the first reader of the job registry. This
# hook is the backup. The watcher can die, or nobody started it, and one
# reader that fails must not hide a dead job. The hook marks each job that
# it reports with the class that it reported. A job that ended is reported
# one time. A job with a stale heartbeat is reported one time as stale. If
# that job gets an exit record later, the hook reports it one more time as
# ended, so the model gets the real exit status.
#
#   Stop              The hook blocks the end of the turn and gives the
#                     report as the reason. The model then deals with the
#                     dead job before it stops. The next Stop finds the
#                     marker and does not block again.
#   UserPromptSubmit  The hook prints the report. The harness adds the
#                     stdout of this hook to the context of the model.
#
# The hook is silent when the registry does not exist, and when it cannot
# parse the payload. It reports only the jobs that started in the directory
# of the session, below it, or above it. A known limit: the hook reads only
# the first line of a directory name that holds a newline, so it does not
# find the jobs of that directory.
set -euo pipefail

# The directory of this script. A path with no "/" is a script in the
# current directory. A parameter expansion starts no process, and the hook
# runs on each turn.
case "${BASH_SOURCE[0]}" in
  */*) HOOK_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) HOOK_DIR="." ;;
esac

# shellcheck source=lib/job-registry.sh disable=SC1091
source "${HOOK_DIR}/lib/job-registry.sh"
# shellcheck source=lib/job-report.sh disable=SC1091
source "${HOOK_DIR}/lib/job-report.sh"

ADVICE="A background job ended or its heartbeat stopped. Do not wait for it. Read the log, tell the user what occurred, and decide the next step."

main() {
  local root event cwd jobs printer
  root="$(registry_root)"
  # The usual case is a session with no background job. This test keeps
  # that case free of a jq call on each turn.
  [ -d "$root" ] || return 0

  # jq prints each value raw on its own line, and "IFS= read -r" changes no
  # character of a line. Thus a space, a tab, or a backslash in the name of
  # the directory arrives unchanged.
  { IFS= read -r event && IFS= read -r cwd; } \
    < <(jq -r '.hook_event_name // "", .cwd // ""' 2>/dev/null) || return 0

  mapfile -t jobs < <(registry_jobs_due "$root" "${cwd:-$PWD}")
  [ "${#jobs[@]}" -gt 0 ] || return 0
  if [ "$event" = "Stop" ]; then
    printer=block_the_stop
  else
    printer=add_to_context
  fi
  # The status 1 is the case of no dead job, and the hook is then silent.
  # The status 2 is a print that failed. The test then fails, and the hook
  # exits with the status 1. The harness reads the status 2 as a block, so
  # the hook must not exit with it.
  report_dead_jobs "$printer" "$(registry_now)" "${jobs[@]}" || [ "$?" -eq 1 ]
}

# block_the_stop <reports>
#
# Prints the decision that blocks the end of the turn, with the advice and
# the reports as the reason.
block_the_stop() {
  jq -n --arg reason "${ADVICE}"$'\n\n'"$1" '{decision: "block", reason: $reason}'
}

# add_to_context <reports>
#
# Prints the advice and the reports as plain text.
add_to_context() {
  printf '%s\n\n%s\n' "$ADVICE" "$1"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
