#!/usr/bin/env bash
# The job registry: the records that scripts/background-run.sh writes for
# each background job, and the decision that reads them. A script sources
# this file. Nothing executes it on its own. It is the single place that
# knows the format of a record and the layout of a job directory, as
# lib/transcript.sh is for the transcript. The wrapper, the watcher
# (scripts/background-watch.sh), and the report hook (report-dead-jobs.sh)
# all call it. Thus a change of the format is a change of this file only.
# The text that tells the model about a job is in lib/job-report.sh.
#
# A job is one directory below the registry root. It holds:
#
#   start     one record: the pid, the interval of the heartbeat, the start
#             time, the command, and the directory of the caller
#   beats     one record for each beat, the newest last
#   exit      one record: the end time and the exit status, a number
#   reported  a marker. A reader reported this job to the model. It holds
#             the class that the reader reported: "stale" or "ended".
#   log       the output of the job. The wrapper writes it.
#
# A record is one JSON object on one line. JSON keeps a newline, a quote, or
# an "=" in a command unchanged, and jq is already necessary for the hooks.
# All times are whole seconds since the epoch.
#
# A known limit: the registry has no lock. Two readers that start at the
# same moment can each read a job before the other one marks it, and each
# one then prints the report of that job. The marker stays correct, because
# a mark keeps the higher class (see marker_join).

# A heartbeat is stale when the age of its last beat is MORE than this number
# of intervals. This is the only place that holds the number.
STALE_INTERVALS=3

# The interval of the wrapper when the caller gives none, in seconds. The
# start record holds the interval that a job really uses. A reader gets it
# from there and never from this default.
DEFAULT_BEAT_INTERVAL=30

# The longest interval that a new job can use, in seconds: one day. This is
# the only place that holds the number (see registry_beat_interval).
MAX_BEAT_INTERVAL=86400

# The removal keeps a job until its last activity is MORE than this number
# of seconds old. The number is a cleanup age. It is not a prediction of the
# duration of a job. The model reads the log after the report, so the log
# must stay for some time. This is the only place that holds the number.
JOB_KEEP_SECONDS=86400

# --- the decision ---------------------------------------------------------------

# registry_job_classes <now> [job-dir ...]
#
# Prints the class and the directory of each given job on one line, with a
# tab between them. It reads the records of each job one time and changes
# nothing. A reader takes the report and the marker of a job from this one
# line. Thus the class in the marker is the class in the report. A directory
# with no start record is not a job, and it gets no line.
registry_job_classes() {
  local now="$1" dir class
  shift
  for dir in "$@"; do
    class="$(job_class "$dir" "$now")" || continue
    printf '%s\t%s\n' "$class" "$dir"
  done
}

# job_class <job-dir> <now>
#
# Prints the class of one job from its records. It fails with no output when
# the directory holds no start record, because that directory is not a job.
job_class() {
  local dir="$1" now="$2" start interval beat status
  read -r start interval beat status _ < <(job_facts "$dir") || return 1
  [ -n "${start:-}" ] || return 1
  classify_job "$now" "$start" "$interval" "${beat#-}" "${status#-}"
}

# classify_job <now> <start-time> <interval> <last-beat-time> <exit-status>
#
# The pure decision. It reads no clock and no file. The last two arguments
# are the empty text when the job has no beat or no exit record. It prints
# exactly one of:
#
#   ended <status>  The job has an exit record. This wins over a stale
#                   heartbeat, because the wrapper wrote the status last.
#   stale           The age of the last beat is more than STALE_INTERVALS
#                   intervals. The heartbeat stopped, and the wrapper is
#                   possibly dead. A heartbeat can also continue later
#                   (see report_is_due).
#   alive           All other cases. An age of exactly STALE_INTERVALS
#                   intervals is alive.
#
# A job with no beat uses its start time as the last beat.
classify_job() {
  local now="$1" start="$2" interval="$3" beat="$4" status="$5"
  local last="${beat:-$start}"
  if [ -n "$status" ]; then
    printf 'ended %s' "$status"
  elif ((now - last > STALE_INTERVALS * interval)); then
    printf 'stale'
  else
    printf 'alive'
  fi
}

# report_is_due <marker-class> <exit-record>
#
# The pure decision of the marker. It succeeds when a reader must read the
# job. <marker-class> is the empty text for a job with no marker.
# <exit-record> is the empty text for a job with no exit record, and any
# other text for a job with one. The exit status is such a text.
#
#   no marker  A reader must read the job.
#   stale      A reader must read the job again only when it has an exit
#              record. A heartbeat can stop for some time and then continue,
#              for example when the computer sleeps. The wrapper then writes
#              the exit record, and the model must get the real status.
#   ended      The report is final. No reader reads the job again.
report_is_due() {
  case "$1" in
    "") return 0 ;;
    stale) [ -n "$2" ] ;;
    *) return 1 ;;
  esac
}

# marker_join <marker-class> <marker-class>
#
# The pure rule of a mark. It prints the higher of two classes in the order:
# no marker, stale, ended. Thus a second mark with the same class changes
# nothing, the order of two marks changes nothing, and "ended" stays.
marker_join() {
  if [ "$1" = "ended" ] || [ "$2" = "ended" ]; then
    printf 'ended'
  elif [ "$1" = "stale" ] || [ "$2" = "stale" ]; then
    printf 'stale'
  fi
}

# activity_is_old <now> <start-time> <last-beat-time> <exit-time>
#
# A pure decision of the removal. It succeeds when the last activity of a
# job is more than JOB_KEEP_SECONDS old. The last activity is the time of
# the exit record, else the time of the last beat, else the start time. The
# last two arguments are the empty text when the record is absent. An age of
# exactly the limit is not old.
activity_is_old() {
  local now="$1" start="$2" beat="$3" exit_time="$4"
  local last="${exit_time:-${beat:-$start}}"
  ((now - last > JOB_KEEP_SECONDS))
}

# --- the set of jobs ------------------------------------------------------------

# registry_root
#
# Prints the directory that holds the jobs.
registry_root() {
  printf '%s' "${CLAUDE_JOB_REGISTRY:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-jobs}"
}

# registry_now
#
# Prints the current time. It is here so that every caller uses one clock
# and one unit.
registry_now() {
  printf '%(%s)T' -1
}

# registry_beat_interval
#
# Prints the interval of the heartbeat for a new job or a new watcher, in
# seconds: CLAUDE_JOB_INTERVAL, or the default. It fails with the status 2
# when the value is not valid (see interval_is_valid). A value that is not
# valid must stop here and not in a record.
registry_beat_interval() {
  local interval="${CLAUDE_JOB_INTERVAL:-$DEFAULT_BEAT_INTERVAL}"
  if interval_is_valid "$interval"; then
    printf '%s' "$interval"
  else
    printf 'CLAUDE_JOB_INTERVAL must be a whole number of seconds from 1 through %s, not "%s".\n' \
      "$MAX_BEAT_INTERVAL" "$interval" >&2
    return 2
  fi
}

# interval_is_valid <text>
#
# The pure decision of the interval. It succeeds for a whole number from 1
# through MAX_BEAT_INTERVAL. The decision of classify_job is 64-bit integer
# arithmetic. A value such as "0.5" or "30s" stops that arithmetic. A number
# of 19 digits overflows it, and a job that is 10 seconds old then reads as
# stale. The test of the length comes first, because the comparison with the
# limit is the same arithmetic.
interval_is_valid() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] && [ "${#1}" -le "${#MAX_BEAT_INTERVAL}" ] && (($1 <= MAX_BEAT_INTERVAL))
}

# registry_jobs_due <root> <cwd>
#
# Prints the directory of each job whose report is due, one on a line. A
# reader must read these jobs. The list holds a job with no marker, and
# also a job that a reader reported as stale and that now has an exit
# record (see report_is_due). The directory of the job must be on one branch
# with <cwd>: the job started in <cwd>, below it, or above it. The model can
# start a job in the root of a repository and then work in a directory below
# that root. The registry is common to every session of the user, and a
# session must not get the dead jobs of a different project.
#
# The report hook calls this function on each turn. Thus the loop starts no
# process: it reads the marker with a builtin, and a file test tells it
# that an exit file holds data. One jq call then reads the records of the
# jobs that remain. For a job with a stale marker, jq also reads the exit
# file, and the job is in the list only when that file holds an exit record.
# The rule of an exit record is JQ_EXIT_RECORD, which job_facts also uses.
# Thus a job is in the list for its exit record only when its class is
# "ended", and the mark that follows the report is final.
registry_jobs_due() {
  local root="$1" dir exit_file files=()
  for dir in "$root"/*/; do
    read_marker "${dir%/}"
    exit_file=""
    [ ! -s "${dir}exit" ] || exit_file="${dir}exit"
    if [ -e "${dir}start" ] && report_is_due "$MARKER_CLASS" "$exit_file"; then
      files+=("${dir}start")
      [ -z "$MARKER_CLASS" ] || files+=("$exit_file")
    fi
  done
  [ "${#files[@]}" -gt 0 ] || return 0
  jq -rRn --arg cwd "$2" "${JQ_RECORD}${JQ_EXIT_RECORD}${JQ_ON_ONE_BRANCH}"'
    [inputs | {file: input_filename, record: [record][0]}]
    | group_by(.file | sub("/[^/]*$"; ""))[]
    | select(any(.[]; .record | .record == "start" and on_one_branch($cwd; .cwd)))
    | select(all(.[]; .file | endswith("/exit") | not) or any(.[]; .record | is_exit_record))
    | .[0].file | sub("/[^/]*$"; "")' "${files[@]}"
}

# registry_shortest_interval <job-dir> [job-dir ...]
#
# Prints the shortest heartbeat interval of the given jobs. The watcher
# sleeps for that time between two reads. When no start record is readable,
# it prints the default interval.
registry_shortest_interval() {
  local dir starts=()
  for dir in "$@"; do starts+=("${dir}/start"); done
  jq -rRn --argjson default "$DEFAULT_BEAT_INTERVAL" \
    "${JQ_RECORD}"'[inputs | record | .interval] | min // $default' "${starts[@]}"
}

# registry_mark_reported <class> [job-dir ...]
#
# Records that a reader reported each given job as <class>. <class> is a
# class as job_class prints it, and the marker gets its first word: "stale"
# or "ended". The marker keeps the higher class (see marker_join). Thus a
# second mark changes nothing, and a mark of "stale" does not change a
# marker that holds "ended". A reader gives the class that it put in the
# report.
registry_mark_reported() {
  local class="${1%% *}" dir
  shift
  for dir in "$@"; do
    printf '%s\n' "$(marker_join "$(registry_reported_class "$dir")" "$class")" > "${dir}/reported"
  done
}

# registry_is_reported <job-dir>
registry_is_reported() {
  [ -e "$1/reported" ]
}

# registry_reported_class <job-dir>
#
# Prints the class in the marker of the job: "stale" or "ended". It prints
# nothing for a job with no marker. A marker that does not hold "stale"
# reads as "ended". An older registry wrote an empty marker for a report
# that was final.
registry_reported_class() {
  # The local name keeps the result of read_marker in this function.
  local MARKER_CLASS
  read_marker "$1"
  printf '%s' "$MARKER_CLASS"
}

# registry_remove_old <root> [now]
#
# Deletes each job that is old (see job_is_old), with a marker or without
# one. The wrapper calls it when it starts, so the registry does not grow
# without limit. A job that no session of its directory reads has no marker,
# and each reader of each turn scans it until this function deletes it. A
# job that a reader reported a short time ago stays, because the model reads
# its log after the report. A job with a wrapper that continues stays,
# because its beats are new. A directory with no start record is not a job,
# and the function does not delete it. An empty root deletes nothing.
# Without that rule, the pattern is "/*/". <now> is the current time when
# the caller gives none.
#
# job_is_old is the reference decision, and it starts two processes for a
# job. Measured: 200 jobs of the last day added 1257 ms to each start of the
# wrapper. Thus the function gives job_is_old only the jobs that started
# more than one day ago. A job cannot be old when it started later than
# that, because its last activity is not before its start.
registry_remove_old() {
  local root="$1" now="${2:-}" dir
  [ -n "$root" ] || return 0
  [ -n "$now" ] || now="$(registry_now)"
  while IFS= read -r dir; do
    if job_is_old "$dir" "$now"; then
      rm -rf -- "$dir"
    fi
  done < <(jobs_started_before "$root" "$((now - JOB_KEEP_SECONDS))")
  return 0
}

# --- the records of one job -----------------------------------------------------

# registry_log_path <job-dir>
#
# Prints the path of the file that holds the output of the job.
registry_log_path() {
  printf '%s/log' "$1"
}

# registry_write_start <job-dir> <pid> <interval> <time> <command> <cwd>
registry_write_start() {
  jq -cn --argjson pid "$2" --argjson interval "$3" --argjson time "$4" \
    --arg command "$5" --arg cwd "$6" \
    '{record: "start", pid: $pid, interval: $interval, time: $time, command: $command, cwd: $cwd}' \
    > "$1/start"
}

# registry_write_beat <job-dir> <time> <cpu-ms> <log-bytes>
#
# <cpu-ms> is the processor time that the job and its descendants used since
# the last beat. <log-bytes> is the size of the log now.
registry_write_beat() {
  jq -cn --argjson time "$2" --argjson cpu_ms "$3" --argjson log_bytes "$4" \
    '{record: "beat", time: $time, cpu_ms: $cpu_ms, log_bytes: $log_bytes}' \
    >> "$1/beats"
}

# registry_write_exit <job-dir> <time> <status>
registry_write_exit() {
  jq -cn --argjson time "$2" --argjson status "$3" \
    '{record: "exit", time: $time, status: $status}' > "$1/exit"
}

# registry_field <job-dir> <record> <key>
#
# Prints the value of one field of a record of the job, with no newline
# after it. <record> is "start", "beat", or "exit". The record "beat" is the
# last beat. A record or a field that is absent gives the empty text.
registry_field() {
  local file
  file="$(record_path "$1" "$2")"
  [ -e "$file" ] || return 0
  tail -n 1 "$file" | jq -jR --arg key "$3" "${JQ_RECORD}"'record | .[$key] // empty'
}

# registry_job_command <job-dir>
#
# Prints the command of the job, with no newline after it.
registry_job_command() {
  registry_field "$1" start command
}

# registry_last_beats <job-dir> <count>
#
# Prints the last <count> beats, the newest last. A line holds the time, the
# processor time in milliseconds, and the size of the log in bytes, with a
# tab between them.
registry_last_beats() {
  [ -e "$1/beats" ] || return 0
  tail -n "$2" "$1/beats" | jq -rR "${JQ_RECORD}"'record | [.time, .cpu_ms, .log_bytes] | @tsv'
}

# --- private: only the functions of this file call the names below --------------

# job_facts <job-dir>
#
# The one read of the records for the decisions. It prints the numbers that
# they use, on one line: the start time, the interval, the time of the last
# beat, the exit status, and the time of the exit record. A "-" is a value
# that is absent. It prints nothing when the directory holds no start
# record. It reads the last TWO lines of the beats. The wrapper can be in
# the middle of a write, and a half-written last line must not hide the beat
# before it. One tail command reads the three files. Thus a file that is
# absent does not stop the read of the next file in a caller with "set -e".
job_facts() {
  tail -q -n 2 "$1/start" "$1/beats" "$1/exit" 2>/dev/null |
    jq -rRn "${JQ_RECORD}${JQ_EXIT_RECORD}"'
      [inputs | record] as $records
      | ($records | map(select(.record == "start")) | last) as $start
      | ($records | map(select(.record == "beat")) | last) as $beat
      | ($records | map(select(is_exit_record)) | last) as $exit
      | select($start != null)
      | "\($start.time) \($start.interval) \($beat.time // "-") \($exit.status // "-") \($exit.time // "-")"'
}

# The class in the marker of the job that read_marker read last. Only the
# loop of registry_jobs_due reads this global, immediately after its call of
# read_marker. The reason is the cost. The report hook runs that loop for
# each job on each turn. A result on stdout needs a command substitution,
# and that starts a process. Each other caller of read_marker must make a
# local variable with this name.
MARKER_CLASS=""

# read_marker <job-dir>
#
# Puts the class in the marker of the job into MARKER_CLASS: "stale",
# "ended", or the empty text for a job with no marker. A marker that does
# not hold "stale" reads as "ended".
read_marker() {
  MARKER_CLASS=""
  if registry_is_reported "$1"; then
    read -r MARKER_CLASS < "$1/reported" || true
    [ "$MARKER_CLASS" = "stale" ] || MARKER_CLASS="ended"
  fi
}

# jobs_started_before <root> <time>
#
# Prints the directory of each job whose start record holds a time before
# <time>, one on a line. One jq call reads all the start records.
jobs_started_before() {
  local root="$1" dir starts=()
  for dir in "$root"/*/; do
    [ -e "${dir}start" ] && starts+=("${dir}start")
  done
  [ "${#starts[@]}" -gt 0 ] || return 0
  jq -rR --argjson limit "$2" "${JQ_RECORD}"'
    record
    | select(.record == "start" and (.time | type) == "number" and .time < $limit)
    | input_filename | sub("/+start$"; "")' "${starts[@]}"
}

# job_is_old <job-dir> <now>
#
# Succeeds when the records of the job give a last activity that is old and
# a class that is not "alive". A job with an interval of almost one day is
# alive when its last beat is more than one day old, and it must stay. It
# fails for a directory with no start record.
job_is_old() {
  local start interval beat status exit_time
  read -r start interval beat status exit_time < <(job_facts "$1") || return 1
  [ -n "${start:-}" ] || return 1
  activity_is_old "$2" "$start" "${beat#-}" "${exit_time#-}" &&
    [ "$(classify_job "$2" "$start" "$interval" "${beat#-}" "${status#-}")" != "alive" ]
}

# record_path <job-dir> <record>
#
# Prints the path of the file that holds a record. The file has the name of
# the record. The beats are the exception: one file, "beats", holds them all.
record_path() {
  case "$2" in
    beat) printf '%s/beats' "$1" ;;
    *) printf '%s/%s' "$1" "$2" ;;
  esac
}

# The one reader of a record line, as jq text. It gives the object on the
# line. A line that is not JSON gives nothing. A line that is JSON and not
# an object, for example 7 or [1,2], also gives nothing, because a field
# read of such a value stops jq with an error.
JQ_RECORD='def record: fromjson? | objects;'

# The one rule of an exit record, as jq text. An exit record has the record
# name "exit" and a status that is a number. The wrapper writes only a
# number. An exit file with a different status, for example false or a
# text, is a damaged file, and the job then has no exit record. Each
# decision that asks for an exit record must use this rule. With two rules,
# a reader listed a job as ended and reported it as stale on each turn.
JQ_EXIT_RECORD='def is_exit_record: .record == "exit" and (.status | type) == "number";'

# The pure decision of the directory filter of registry_jobs_due, as jq
# text. Two directories are on one branch when they are equal or when one is
# above the other. The comparison is on whole path components: "/work" is
# not above "/workshop". The decision first removes each "/" at the end of
# the two paths, so "/w/sub//" is "/w/sub". Thus the root directory is the
# empty text, and it is above each other directory. A value that is not
# text, for example the number in a damaged start record, is no directory.
# It is on no branch, and it does not stop jq with an error.
# shellcheck disable=SC2016 # The "$" names are jq variables, not shell ones.
JQ_ON_ONE_BRANCH='
  def without_end_slashes: sub("/+$"; "");
  def at_or_below($top; $path): $path == $top or ($path | startswith($top + "/"));
  def on_one_branch($a; $b):
    ([$a, $b] | all(type == "string")) and
    (($a | without_end_slashes) as $a | ($b | without_end_slashes) as $b
     | at_or_below($a; $b) or at_or_below($b; $a));'
