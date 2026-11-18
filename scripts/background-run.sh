#!/usr/bin/env bash
# Runs one command as a background job that reports its own death.
#
#   scripts/background-run.sh <command> [argument ...]
#
# The wrapper starts the command, writes a beat to the job registry at a
# fixed interval, and writes the exit status when the command ends. A reader
# (scripts/background-watch.sh or hooks/report-dead-jobs.sh) reads those
# records. A job that ends has an exit record. A job whose wrapper died has
# a heartbeat that stops. Neither case needs a prediction of how long the
# job takes. The interval of the heartbeat is the only time constant.
#
# A beat holds two facts: the processor time that the job and all its
# descendants used since the last beat, and the size of the log. The wrapper
# makes no decision from them. A job that waits on a remote service uses no
# processor time in normal operation, so only the reader can judge.
#
# Environment:
#   CLAUDE_JOB_REGISTRY  the registry root (see registry_root)
#   CLAUDE_JOB_INTERVAL  seconds between two beats, a whole number from 1
#                        through 86400 (see registry_beat_interval)
#
# The wrapper prints the job directory first, and it exits with the status
# of the command. The output of the command goes to the log in the job
# directory.
set -euo pipefail

# The directory of this script. A path with no "/" is a script in the
# current directory. A parameter expansion starts no process.
case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) SCRIPT_DIR="." ;;
esac

# shellcheck source=../hooks/lib/job-registry.sh disable=SC1091
source "${SCRIPT_DIR}/../hooks/lib/job-registry.sh"

main() {
  if [ "$#" -eq 0 ]; then
    printf 'usage: %s <command> [argument ...]\n' "${0##*/}" >&2
    return 2
  fi

  local root interval job_dir log job_pid wrapper_pid beater_pid status
  interval="$(registry_beat_interval)" || return
  root="$(registry_root)"

  # The traps come before the job directory. A signal that ends the wrapper
  # after it made the directory leaves a directory with no start record,
  # and the removal never deletes such a directory. The removal deletes
  # each other job that is old, with a marker or without one.
  catch_signals
  mkdir -p "$root"
  registry_remove_old "$root"
  job_dir="$(make_job_dir "$root")"
  log="$(registry_log_path "$job_dir")"

  run_job "$@" > "$log" 2>&1 &
  job_pid=$!
  registry_write_start "$job_dir" "$job_pid" "$interval" "$(registry_now)" "$*" "$PWD"
  printf 'job: %s\n' "$job_dir"

  # The shell expands the arguments of a background command in the new
  # process. Thus the wrapper must read its own pid before that command.
  wrapper_pid="$BASHPID"
  write_beats "$job_dir" "$job_pid" "$interval" "$log" "$wrapper_pid" < /dev/null > /dev/null 2>&1 &
  beater_pid=$!

  status=0
  wait_for_job "$job_pid" || status=$?

  kill "$beater_pid" 2>/dev/null || true
  registry_write_exit "$job_dir" "$(registry_now)" "$status"
  printf 'exit status: %s\nlog: %s\n' "$status" "$log"
  return "$status"
}

# The name of the last signal that the wrapper got and did not send to the
# job yet. It is a global because a trap handler has no other scope.
PENDING_SIGNAL=""

# catch_signals
#
# Records each TERM, INT, or HUP signal in PENDING_SIGNAL. The wrapper calls
# it BEFORE it makes the job directory and starts the job. Thus no signal
# can end the wrapper between the job directory and the exit record. A
# signal that arrives before the job starts goes to the job when the wrapper
# waits for it (see wait_for_job). A signal that the caller of the wrapper
# ignores stays ignored, because bash cannot catch it.
catch_signals() {
  trap 'PENDING_SIGNAL=TERM' TERM
  trap 'PENDING_SIGNAL=INT' INT
  trap 'PENDING_SIGNAL=HUP' HUP
}

# make_job_dir <root>
#
# Makes the directory of a new job below the root and prints it. The process
# that makes the directory ignores TERM, INT, and HUP. The traps of the
# wrapper protect only the wrapper. A signal to the process group, for
# example from Ctrl-C, otherwise ends that process after it made the
# directory, and a directory with no start record stays. The wrapper
# records the same signal and sends it to the job (see wait_for_job).
make_job_dir() {
  (
    trap '' TERM INT HUP
    exec mktemp -d "$1/$(printf '%(%Y%m%dT%H%M%S)T' -1).XXXXXX"
  )
}

# run_job <command> [argument ...]
#
# Replaces this process with the command. Call it in the background. Bash
# starts a background command with INT and QUIT ignored, and an INT that the
# wrapper sends would then have no effect. Thus this function sets the
# default handlers of the two signals first. A signal that the caller of the
# wrapper ignores stays ignored in the job also.
run_job() {
  trap - INT QUIT
  exec "$@"
}

# wait_for_job <pid>
#
# Returns the exit status of the job. A TERM, INT, or HUP signal to the
# wrapper goes to the job, and the wrapper then waits for the job to end.
# Thus the exit record holds the status that the signal caused, and the
# wrapper leaves no job behind it. A job that catches or ignores the signal
# continues, and the wrapper continues to wait for it. A signal that arrived
# before this call goes to the job first. A KILL signal permits no handler.
# That case leaves no exit record, and the stale heartbeat reports it.
wait_for_job() {
  local pid="$1" status
  while :; do
    send_pending_signal "$pid"
    status=0
    wait "$pid" || status=$?
    [ -n "$PENDING_SIGNAL" ] || break
  done
  return "$status"
}

# send_pending_signal <pid>
#
# Sends the recorded signal to the process, and clears the record. It does
# nothing when no signal is recorded.
send_pending_signal() {
  local signal="$PENDING_SIGNAL"
  PENDING_SIGNAL=""
  [ -z "$signal" ] || kill -s "$signal" "$1" 2>/dev/null || true
}

# write_beats <job-dir> <pid> <interval> <log> <wrapper-pid>
#
# Writes one beat after each interval while the wrapper lives. It tests the
# wrapper before each beat. A wrapper that got a KILL signal cannot stop this
# process, so this process must stop itself. The heartbeat then becomes
# stale, and a reader reports the job. A TERM signal from the wrapper also
# stops it. The sleep is a child that the handler stops, so no process stays
# after the wrapper ends.
write_beats() {
  local job_dir="$1" pid="$2" interval="$3" log="$4" wrapper_pid="$5"
  local hz previous=0 total sleep_pid=""
  hz="$(getconf CLK_TCK)"
  trap '[ -z "$sleep_pid" ] || kill "$sleep_pid" 2>/dev/null; exit 0' TERM
  while :; do
    sleep "$interval" &
    sleep_pid=$!
    wait "$sleep_pid"
    if process_lives "$wrapper_pid"; then
      total="$(read_tree_stats "$pid" | tree_cpu_ticks "$pid")"
      registry_write_beat "$job_dir" "$(registry_now)" \
        "$(cpu_delta_ms "$previous" "$total" "$hz")" "$(wc -c < "$log")"
      previous="$total"
    else
      return 0
    fi
  done
}

# process_lives <pid>
#
# Succeeds when the process runs. A zombie does not run: it got its signal,
# and it only waits for its parent to collect it.
process_lives() {
  stat_is_live "$(cat "/proc/$1/stat" 2>/dev/null)"
}

# stat_is_live <stat-line>
#
# The pure decision. It succeeds when the line is not empty and its state is
# not Z (zombie) or X (dead). The state is the first field after the LAST
# ")", because the name of a process can hold a space or a ")".
stat_is_live() {
  local rest="${1##*) }"
  [[ -n "$1" && "${rest%% *}" != [ZX] ]]
}

# cpu_delta_ms <ticks-at-the-last-beat> <ticks-now> <ticks-in-a-second>
#
# Prints the processor time since the last beat, in milliseconds. A total
# that decreased gives zero. That occurs when a descendant ends and no
# process in the tree collected it.
cpu_delta_ms() {
  local delta=$(($2 - $1))
  ((delta > 0)) || delta=0
  printf '%s' $((delta * 1000 / $3))
}

# tree_cpu_ticks <root-pid>
#
# The pure calculation. It reads stat lines on stdin and prints the
# processor time, in clock ticks, of the root and all its descendants. The
# time of a process is utime + stime + cutime + cstime. The last two are the
# time of the children that ended and that the process collected. Thus the
# total does not decrease when a child ends in the normal way. A line of a
# process outside the tree adds nothing, and the order of the lines does not
# matter.
#
# The name of a process can hold a space or a ")". The fields are counted
# from the LAST ")" for that reason.
tree_cpu_ticks() {
  awk -v root="$1" '
    {
      pid = $1
      rest = $0
      while ((at = index(rest, ")")) > 0) rest = substr(rest, at + 1)
      split(rest, field, " ")
      parent[pid] = field[2]
      ticks[pid] = field[12] + field[13] + field[14] + field[15]
    }
    function in_tree(pid,   hops) {
      for (hops = 0; hops <= NR; hops++) {
        if (pid == root) return 1
        if (!(pid in parent)) return 0
        pid = parent[pid]
      }
      return 0
    }
    END {
      for (pid in ticks) if (in_tree(pid)) total += ticks[pid]
      print total + 0
    }'
}

# read_tree_stats <pid>
#
# Prints the /proc stat line of the process and of each descendant. It
# follows the children of each process, so the cost is the size of the tree
# of the job and not the number of processes on the machine. A process that
# ends between the list and the read prints nothing.
read_tree_stats() {
  local pid="$1" child children=()
  cat "/proc/${pid}/stat" 2>/dev/null || return 0
  read -r -d '' -a children < <(cat "/proc/${pid}"/task/*/children 2>/dev/null) || true
  for child in "${children[@]}"; do
    read_tree_stats "$child"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
