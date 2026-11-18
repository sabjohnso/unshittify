#!/usr/bin/env bats
# Tests of hooks/lib/job-registry.sh, the single place that knows the format
# of the job registry. The laws are in REQUIREMENTS.org under "Laws of the
# job registry". Each law has a loop over generated inputs with a fixed list
# of seeds. Thus a failure names a seed that reproduces it. A decision with a
# small domain has a loop over each input.
#
# bats runs each test in a subshell. A test sets RANDOM, and a generator
# that the test calls directly uses that value.
# shellcheck disable=SC2030,SC2031

load helpers

setup() {
  # shellcheck source=../../hooks/lib/job-registry.sh disable=SC1091
  source "${HOOKS_DIR}/lib/job-registry.sh"
  JOB="$(fixture_dir)/job"
  mkdir -p "$JOB"
}

SEEDS="1 2 3 5 8 13 21 34 55 89"

# random_text <seed>
#
# Prints text from an alphabet that holds each character that can break a
# record format: a space, a newline, "=", both quotes, a backslash, and a
# tab. The length is 0 to 11 characters, so the empty text occurs.
random_text() {
  local alphabet=(a Z 0 ' ' $'\n' '=' '"' "'" $'\\' $'\t' ':' '{' ',')
  local length i out=""
  RANDOM=$1
  length=$((RANDOM % 12))
  for ((i = 0; i < length; i++)); do
    out+="${alphabet[RANDOM % ${#alphabet[@]}]}"
  done
  printf '%s' "$out"
}

# exact <command ...>
#
# Runs the command with a sentinel after its output. Thus the command
# substitution of the caller does not remove a newline at the end.
exact() {
  "$@"
  printf 'x'
}

# fails <command ...>
#
# Succeeds when the command fails. A line that starts with "!" does not stop
# a bats test, so a test uses this function for a decision that must fail.
fails() {
  ! "$@"
}

# counted_commands <log> <name ...>
#
# Makes a stand-in for each named command and prints the directory that
# holds them. A stand-in adds its name to the log and then runs the real
# command. Thus a test can count the processes that a function starts.
counted_commands() {
  local log="$1" bin name
  bin="$(fixture_dir)/bin"
  mkdir -p "$bin"
  shift
  for name in "$@"; do
    printf '#!/bin/sh\necho %s >> "%s"\nexec "%s" "$@"\n' "$name" "$log" "$(command -v "$name")" > "$bin/$name"
    chmod +x "$bin/$name"
  done
  printf '%s' "$bin"
}

# make_job <root> <name> <start-time> [beat-time] [exit-status]
make_job() {
  local dir="$1/$2"
  mkdir -p "$dir"
  registry_write_start "$dir" 1 30 "$3" "cmd $2" "/work"
  [ -z "${4:-}" ] || registry_write_beat "$dir" "$4" 10 10
  [ -z "${5:-}" ] || registry_write_exit "$dir" "$4" "$5"
}

# --- the location -------------------------------------------------------------

@test "the registry root is CLAUDE_JOB_REGISTRY when that variable is set" {
  CLAUDE_JOB_REGISTRY=/a/b XDG_STATE_HOME=/x run registry_root
  [ "$output" = "/a/b" ]
}

@test "the registry root is below XDG_STATE_HOME, or below the home directory" {
  unset CLAUDE_JOB_REGISTRY
  XDG_STATE_HOME=/x run registry_root
  [ "$output" = "/x/claude-jobs" ]
  unset XDG_STATE_HOME
  HOME=/h run registry_root
  [ "$output" = "/h/.local/state/claude-jobs" ]
}

@test "the log of a job is in its directory" {
  [ "$(registry_log_path /r/job1)" = "/r/job1/log" ]
}

# --- the writer and the reader -----------------------------------------------

@test "law: the reader returns each free-text field that the writer got" {
  local seed command cwd
  for seed in $SEEDS; do
    command="$(exact random_text "$seed")"; command="${command%x}"
    cwd="$(exact random_text "$((seed + 100))")"; cwd="${cwd%x}"
    registry_write_start "$JOB" 4242 30 1000 "$command" "$cwd"
    [ "$(exact registry_field "$JOB" start command)" = "${command}x" ] || {
      echo "seed ${seed}: the command did not read back"; return 1; }
    [ "$(exact registry_job_command "$JOB")" = "${command}x" ] || {
      echo "seed ${seed}: the reader of the command gave a different text"; return 1; }
    [ "$(exact registry_field "$JOB" start cwd)" = "${cwd}x" ] || {
      echo "seed ${seed}: the directory did not read back"; return 1; }
  done
}

@test "the start record holds the pid, the interval, the time, and the directory" {
  registry_write_start "$JOB" 4242 30 1000 "make test" "/some/dir"
  [ "$(registry_field "$JOB" start pid)" = "4242" ]
  [ "$(registry_field "$JOB" start interval)" = "30" ]
  [ "$(registry_field "$JOB" start time)" = "1000" ]
  [ "$(registry_field "$JOB" start cwd)" = "/some/dir" ]
}

@test "the reader of the beats returns the last beat" {
  registry_write_beat "$JOB" 1030 120 500
  registry_write_beat "$JOB" 1060 0 700
  [ "$(registry_field "$JOB" beat time)" = "1060" ]
  [ "$(registry_field "$JOB" beat cpu_ms)" = "0" ]
  [ "$(registry_field "$JOB" beat log_bytes)" = "700" ]
}

@test "a field that is absent reads as the empty text" {
  registry_write_start "$JOB" 1 30 1000 "x" "/d"
  [ -z "$(registry_field "$JOB" start no_such_field)" ]
  [ -z "$(registry_field "$JOB" exit status)" ]
}

@test "the last beats as three numbers on a line, and not more lines than the job has beats" {
  [ -z "$(registry_last_beats "$JOB" 3)" ]
  local time
  for time in 10 20 30 40; do registry_write_beat "$JOB" "$time" "$((time * 2))" "$((time * 3))"; done
  [ "$(registry_last_beats "$JOB" 9 | wc -l)" -eq 4 ]
  [ "$(registry_last_beats "$JOB" 3)" = "$(printf '20\t40\t60\n30\t60\t90\n40\t80\t120')" ]
}

# --- the pure decision --------------------------------------------------------

@test "an example of each class" {
  [ "$(classify_job 1010 1000 30 "" "")" = "alive" ]
  [ "$(classify_job 1010 1000 30 "" 7)" = "ended 7" ]
  [ "$(classify_job 2000 1000 30 1030 "")" = "stale" ]
}

@test "the limit: an age of exactly three intervals is alive, one second more is stale" {
  [ "$(classify_job 1090 1000 30 "" "")" = "alive" ]
  [ "$(classify_job 1091 1000 30 "" "")" = "stale" ]
  [ "$(classify_job 1150 1000 30 1060 "")" = "alive" ]
  [ "$(classify_job 1151 1000 30 1060 "")" = "stale" ]
}

@test "law: the decision returns exactly one of the three classes" {
  local seed now start interval beat status class
  for seed in $SEEDS; do
    RANDOM=$seed
    start=$((RANDOM % 1000)); interval=$((RANDOM % 60 + 1))
    now=$((start + RANDOM % 500))
    beat=""; ((RANDOM % 2)) && beat=$((start + RANDOM % 300))
    status=""; ((RANDOM % 2)) && status=$((RANDOM % 256))
    class="$(classify_job "$now" "$start" "$interval" "$beat" "$status")"
    [[ "$class" =~ ^(alive|stale|ended\ [0-9]+)$ ]] || {
      echo "seed ${seed}: got '${class}'"; return 1; }
  done
}

@test "law: an exit record always gives the class ended with the status unchanged" {
  local seed now status
  for seed in $SEEDS; do
    RANDOM=$seed
    status=$((RANDOM % 256)); now=$((RANDOM * 100))
    [ "$(classify_job "$now" 0 30 "" "$status")" = "ended ${status}" ] || {
      echo "seed ${seed}: now=${now} status=${status}"; return 1; }
  done
}

@test "law: a job that is stale at one time is stale at each later time" {
  local seed start interval beat last t1 t2
  for seed in $SEEDS; do
    RANDOM=$seed
    start=$((RANDOM % 1000)); interval=$((RANDOM % 60 + 1))
    beat=""; ((RANDOM % 2)) && beat=$((start + RANDOM % 300))
    last="${beat:-$start}"
    t1=$((last + STALE_INTERVALS * interval + 1 + RANDOM % 100))
    t2=$((t1 + RANDOM % 1000))
    [ "$(classify_job "$t1" "$start" "$interval" "$beat" "")" = "stale" ] || {
      echo "seed ${seed}: not stale at t1=${t1}"; return 1; }
    [ "$(classify_job "$t2" "$start" "$interval" "$beat" "")" = "stale" ] || {
      echo "seed ${seed}: not stale at t2=${t2}"; return 1; }
  done
}

@test "law: a job with no beat uses the time of the start record" {
  local seed start interval now
  for seed in $SEEDS; do
    RANDOM=$seed
    start=$((RANDOM % 1000)); interval=$((RANDOM % 60 + 1))
    now=$((start + RANDOM % 400))
    [ "$(classify_job "$now" "$start" "$interval" "" "")" = \
      "$(classify_job "$now" "$start" "$interval" "$start" "")" ] || {
      echo "seed ${seed}"; return 1; }
  done
}

# --- the class of a job in the registry ----------------------------------------

@test "job_class reads the records of one job" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000 1030
  make_job "$root" b 1000 1030 2
  [ "$(job_class "$root/a" 1040)" = "alive" ]
  [ "$(job_class "$root/a" 5000)" = "stale" ]
  [ "$(job_class "$root/b" 5000)" = "ended 2" ]
}

@test "job_class of a job with no beats file uses the start record" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000
  [ "$(job_class "$root/a" 1090)" = "alive" ]
  [ "$(job_class "$root/a" 1091)" = "stale" ]
}

@test "a job with no beats file gives its exit record to a caller that uses set -e" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000
  registry_write_exit "$root/a" 2000 7
  run bash -c 'set -euo pipefail; source "$1"; job_class "$2" 5000' _ "${HOOKS_DIR}/lib/job-registry.sh" "$root/a"
  [ "$status" -eq 0 ]
  [ "$output" = "ended 7" ]
}

# random_not_object <seed>
#
# Prints a record line that is not a JSON object: random text, a number, a
# JSON text, true, null, or a list. The alphabet of the random text holds no
# "}", so that text is never an object.
random_not_object() {
  RANDOM=$1
  case $((RANDOM % 6)) in
    0) random_text "$1" ;;
    1) printf '%s' $((RANDOM % 1000)) ;;
    2) jq -cn --arg text "$(random_text "$1")" '$text' ;;
    3) printf 'true' ;;
    4) printf 'null' ;;
    5) printf '[%s,%s]' $((RANDOM % 10)) $((RANDOM % 10)) ;;
  esac
}

@test "law: a record line that is not a JSON object counts as an absent record, for each record" {
  local seed root line
  for seed in $(seq 1 30); do
    line="$(exact random_not_object "$seed")"; line="${line%x}"
    root="$(fixture_dir)/reg-${seed}"
    # The job "exit" has a beat at 1030, and the job "beats" has none.
    make_job "$root" exit 1000 1030
    make_job "$root" beats 1000
    mkdir -p "$root/start"
    printf '%s\n' "$line" > "$root/exit/exit"
    printf '%s\n' "$line" > "$root/beats/beats"
    printf '%s\n' "$line" > "$root/start/start"
    [ "$(registry_job_classes 1091 "$root/exit" "$root/beats" "$root/start")" = \
      "$(printf 'alive\t%s\nstale\t%s' "$root/exit" "$root/beats")" ] || {
      echo "seed ${seed}: '${line}'"; return 1; }
  done
}

# random_bad_status <seed>
#
# Prints a JSON value that is not a number: a text, true, false, null, a
# list, or an object. The text can hold only digits, and it is still a text.
random_bad_status() {
  RANDOM=$1
  case $((RANDOM % 7)) in
    0) jq -cn --arg text "$(random_text "$1")" '$text' ;;
    1) printf '"%s"' $((RANDOM % 256)) ;;
    2) printf 'true' ;;
    3) printf 'false' ;;
    4) printf 'null' ;;
    5) printf '[%s]' $((RANDOM % 256)) ;;
    6) printf '{"status":%s}' $((RANDOM % 256)) ;;
  esac
}

@test "law: an exit file gives an exit record exactly when its status is a number" {
  local seed root value number
  for seed in $(seq 1 30); do
    value="$(random_bad_status "$seed")"
    root="$(fixture_dir)/reg-${seed}"
    make_job "$root" a 1000
    printf '{"record":"exit","time":2000,"status":%s}\n' "$value" > "$root/a/exit"
    [ "$(registry_job_classes 5000 "$root/a")" = "$(printf 'stale\t%s' "$root/a")" ] || {
      echo "seed ${seed}: the status ${value} gave $(registry_job_classes 5000 "$root/a")"; return 1; }
    number=$((seed * 8 % 256))
    printf '{"record":"exit","time":2000,"status":%s}\n' "$number" > "$root/a/exit"
    [ "$(registry_job_classes 5000 "$root/a")" = "$(printf 'ended %s\t%s' "$number" "$root/a")" ] || {
      echo "seed ${seed}: the status ${number} gave $(registry_job_classes 5000 "$root/a")"; return 1; }
  done
}

@test "a beat that the wrapper did not finish does not hide the beat before it" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000 1030
  printf '{"record":"beat","time":10' >> "$root/a/beats"
  [ "$(job_class "$root/a" 1100)" = "alive" ]
}

@test "a record line that is JSON and not an object counts as a line that is not JSON" {
  local root text i=0
  for text in 7 '[1,2]' '"start"' true; do
    root="$(fixture_dir)/reg-$((i += 1))"
    make_job "$root" a 1000 1030
    printf '%s\n' "$text" > "$root/a/exit"
    [ "$(job_class "$root/a" 1040)" = "alive" ] || { echo "exit ${text}: no class"; return 1; }
    [ -z "$(registry_field "$root/a" exit status)" ] || { echo "exit ${text}: a field"; return 1; }
    printf '%s\n' "$text" >> "$root/a/beats"
    [ "$(job_class "$root/a" 1040)" = "alive" ] || { echo "beat ${text}: no class"; return 1; }
    [ "$(registry_last_beats "$root/a" 3)" = "$(printf '1030\t10\t10')" ] || {
      echo "beat ${text}: the last beats"; return 1; }
    mkdir -p "$root/b"
    printf '%s\n' "$text" > "$root/b/start"
    run job_class "$root/b" 1040
    { [ "$status" -ne 0 ] && [ -z "$output" ]; } || { echo "start ${text}: ${output}"; return 1; }
    [ "$(registry_shortest_interval "$root/b")" = "$DEFAULT_BEAT_INTERVAL" ] || {
      echo "start ${text}: the interval"; return 1; }
    [ "$(registry_jobs_due "$root" /work)" = "$root/a" ] || { echo "start ${text}: the list"; return 1; }
  done
}

@test "job_class fails on a directory with no start record" {
  mkdir -p "$(fixture_dir)/reg/empty"
  run job_class "$(fixture_dir)/reg/empty" 1000
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# --- the dead jobs ------------------------------------------------------------

@test "law: the dead jobs are exactly the jobs that are not alive, in each order of the list" {
  local seed root i count expected dirs
  for seed in $SEEDS; do
    RANDOM=$seed
    root="$(fixture_dir)/reg-${seed}"; expected=(); dirs=()
    count=$((RANDOM % 6 + 1))
    for ((i = 0; i < count; i++)); do
      case $((RANDOM % 3)) in
        0) make_job "$root" "j$i" 4990 4995 ;;
        1) make_job "$root" "j$i" 1000 1030; expected+=("$root/j$i") ;;
        2) make_job "$root" "j$i" 4990 4995 $((RANDOM % 256)); expected+=("$root/j$i") ;;
      esac
      dirs+=("$root/j$i")
    done
    mapfile -t dirs < <(printf '%s\n' "${dirs[@]}" | shuf --random-source=<(yes "$seed"))
    [ "$(dead_jobs 5000 "${dirs[@]}" | sort)" = "$(printf '%s\n' "${expected[@]}" | sed '/^$/d' | sort)" ] || {
      echo "seed ${seed}"; return 1; }
  done
}

# dead_jobs <now> [job-dir ...]
#
# Prints the directory of each line of registry_job_classes whose class is
# not "alive".
dead_jobs() {
  registry_job_classes "$@" | awk -F '\t' '$1 != "alive" { print $2 }'
}

@test "the dead jobs of an empty list are empty" {
  run registry_job_classes 5000
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- the reported marker ------------------------------------------------------

@test "law: a reported job is not in the list of the jobs to read" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000
  make_job "$root" b 1000
  fails registry_is_reported "$root/a"
  [ "$(registry_jobs_due "$root" /work | sort)" = "$(printf '%s\n' "$root/a" "$root/b")" ]
  registry_mark_reported stale "$root/a"
  registry_is_reported "$root/a"
  [ "$(registry_jobs_due "$root" /work)" = "$root/b" ]
  registry_mark_reported stale "$root/b"
  [ -z "$(registry_jobs_due "$root" /work)" ]
}

@test "law: a second mark of a job changes nothing, and one call marks each given job" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000
  make_job "$root" b 1000
  registry_mark_reported stale "$root/a" "$root/b"
  registry_mark_reported stale "$root/a"
  registry_is_reported "$root/a"
  registry_is_reported "$root/b"
  [ -z "$(registry_jobs_due "$root" /work)" ]
}

@test "law: a marker holds the highest class of its marks, for each a, b, and c" {
  local classes=("" stale ended) a b c
  for a in "${classes[@]}"; do
    [ "$(marker_join "$a" "$a")" = "$a" ] || { echo "a second mark of '${a}' changes the marker"; return 1; }
    [ "$(marker_join "$a" "")" = "$a" ] || { echo "no mark changes '${a}'"; return 1; }
    [ "$(marker_join "$a" ended)" = "ended" ] || { echo "'${a}' and ended do not give ended"; return 1; }
    [ "$(marker_join ended "$a")" = "ended" ] || { echo "ended and '${a}' do not give ended"; return 1; }
    for b in "${classes[@]}"; do
      [ "$(marker_join "$a" "$b")" = "$(marker_join "$b" "$a")" ] || {
        echo "the order of '${a}' and '${b}' changes the result"; return 1; }
      for c in "${classes[@]}"; do
        [ "$(marker_join "$(marker_join "$a" "$b")" "$c")" = "$(marker_join "$a" "$(marker_join "$b" "$c")")" ] || {
          echo "the groups of '${a}', '${b}', and '${c}' change the result"; return 1; }
      done
    done
  done
}

@test "the report is due: an example of each marker" {
  report_is_due "" ""
  report_is_due "" 3
  fails report_is_due stale ""
  report_is_due stale 3
  report_is_due stale 0
  fails report_is_due ended ""
  fails report_is_due ended 3
}

@test "law: after the class stale, a report is due exactly when the job has an exit record" {
  local seed record due=0 not_due=0
  for seed in $SEEDS; do
    # An even seed gives a job with no exit record. The text of an odd seed
    # is empty only when its length is zero.
    record=""; ((seed % 2 == 0)) || record="$(random_text "$seed")"
    if [ -n "$record" ]; then
      report_is_due stale "$record" || { echo "seed ${seed}: not due with '${record}'"; return 1; }
      due=$((due + 1))
    else
      fails report_is_due stale "$record" || { echo "seed ${seed}: due with no exit record"; return 1; }
      not_due=$((not_due + 1))
    fi
  done
  # A law that runs only one of its two directions proves only that one.
  { ((due > 0)) && ((not_due > 0)); } || { echo "due: ${due}, not due: ${not_due}"; return 1; }
}

@test "law: the list starts one jq process and no other reader, for each set of markers" {
  local seed root log bin i count
  log="$(fixture_dir)/calls"
  bin="$(counted_commands "$log" jq tail)"
  for seed in $SEEDS; do
    RANDOM=$seed
    root="$(fixture_dir)/reg-${seed}"
    make_job "$root" open 1000
    count=$((RANDOM % 8 + 1))
    for ((i = 0; i < count; i++)); do
      make_job "$root" "j$i" 1000 1030
      case $((RANDOM % 3)) in
        0) registry_mark_reported stale "$root/j$i" ;;
        1) registry_mark_reported stale "$root/j$i"; registry_write_exit "$root/j$i" 2000 3 ;;
        2) registry_write_exit "$root/j$i" 2000 3; registry_mark_reported ended "$root/j$i" ;;
      esac
    done
    : > "$log"
    (PATH="${bin}:${PATH}"; registry_jobs_due "$root" /elsewhere)
    [ "$(cat "$log")" = "jq" ] || { echo "seed ${seed}: started $(tr '\n' ' ' < "$log")"; return 1; }
  done
}

@test "a job reported as stale is not in the list when its exit file holds no record" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000
  registry_mark_reported stale "$root/a"
  printf '7\n' > "$root/a/exit"
  [ -z "$(registry_jobs_due "$root" /work)" ]
  printf '{"record":"exit","ti' > "$root/a/exit"
  [ -z "$(registry_jobs_due "$root" /work)" ]
}

# The texts of an exit file for the law below. The word before the first ":"
# is the oracle: "yes" when the text is an exit record, "no" when it is not.
# An exit record is an object with the record name "exit" and a status that
# is a number.
EXIT_FILE_TEXTS=(
  'yes:{"record":"exit","time":5,"status":0}'
  'yes:{"record":"exit","time":5,"status":3}'
  'yes:{"record":"exit","time":5,"status":255}'
  'no:{"record":"exit","time":5,"status":false}'
  'no:{"record":"exit","time":5,"status":true}'
  'no:{"record":"exit","time":5,"status":null}'
  'no:{"record":"exit","time":5,"status":""}'
  'no:{"record":"exit","time":5,"status":"a b"}'
  'no:{"record":"exit","time":5,"status":[1]}'
  'no:{"record":"exit","time":5}'
  'no:{"record":"beat","time":5,"status":3}'
  'no:{}'
  'no:[1,2]'
  'no:7'
  'no:not json'
)

@test "law: one rule decides that a job has an exit record, for the list and for the class" {
  local entry expected text root i=0 listed ended
  for entry in "${EXIT_FILE_TEXTS[@]}"; do
    expected="${entry%%:*}"; text="${entry#*:}"
    root="$(fixture_dir)/reg-$((i += 1))"
    make_job "$root" a 1000
    registry_mark_reported stale "$root/a"
    printf '%s\n' "$text" > "$root/a/exit"
    listed=no; [ -z "$(registry_jobs_due "$root" /work)" ] || listed=yes
    ended=no; [[ "$(job_class "$root/a" 5000)" != ended* ]] || ended=yes
    [ "$listed" = "$expected" ] || { echo "'${text}': in the list: ${listed}"; return 1; }
    [ "$ended" = "$expected" ] || { echo "'${text}': the class ended: ${ended}"; return 1; }
  done
}

@test "a start record with a directory that is not text hides no other job" {
  local root value i=0
  for value in 7 null true '[1]' '{}'; do
    root="$(fixture_dir)/reg-$((i += 1))"
    make_job "$root" good 1000 1030 2
    mkdir -p "$root/bad" "$root/none"
    printf '{"record":"start","cwd":%s,"time":1,"interval":30}\n' "$value" > "$root/bad/start"
    printf '{"record":"start","time":1,"interval":30}\n' > "$root/none/start"
    run registry_jobs_due "$root" /work
    [ "$status" -eq 0 ] || { echo "cwd ${value}: status ${status}"; return 1; }
    [ "$output" = "$root/good" ] || { echo "cwd ${value}: ${output}"; return 1; }
  done
}

@test "law: a report is never due after the class ended, and always due with no marker" {
  local seed status
  for seed in $SEEDS; do
    RANDOM=$seed
    status=""; ((RANDOM % 2)) && status=$((RANDOM % 256))
    fails report_is_due ended "$status" || { echo "seed ${seed}: due after ended"; return 1; }
    report_is_due "" "$status" || { echo "seed ${seed}: not due with no marker"; return 1; }
  done
}

@test "a job reported as stale is in the list again when it has an exit record" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000
  registry_mark_reported stale "$root/a"
  [ "$(registry_reported_class "$root/a")" = "stale" ]
  [ -z "$(registry_jobs_due "$root" /work)" ]
  registry_write_exit "$root/a" 2000 3
  [ "$(registry_jobs_due "$root" /work)" = "$root/a" ]
  registry_mark_reported ended "$root/a"
  [ "$(registry_reported_class "$root/a")" = "ended" ]
  [ -z "$(registry_jobs_due "$root" /work)" ]
}

@test "a mark records the class that the reader gives" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000
  make_job "$root" b 1000 1030 2
  [ -z "$(registry_reported_class "$root/a")" ]
  registry_mark_reported stale "$root/a"
  registry_mark_reported "ended 2" "$root/b"
  [ "$(registry_reported_class "$root/a")" = "stale" ]
  [ "$(registry_reported_class "$root/b")" = "ended" ]
}

@test "an empty marker of an older registry counts as the class ended" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000 1030 2
  : > "$root/a/reported"
  [ "$(registry_reported_class "$root/a")" = "ended" ]
  [ -z "$(registry_jobs_due "$root" /work)" ]
}

@test "law: a job is in the list after its marks only when no mark is ended and it has an exit record" {
  local classes=(stale ended) seed root i count class ended has_exit expected
  for seed in $SEEDS; do
    RANDOM=$seed
    root="$(fixture_dir)/reg-${seed}"; ended=0; has_exit=$((RANDOM % 2))
    if ((has_exit)); then make_job "$root" a 1000 1030 $((RANDOM % 256)); else make_job "$root" a 1000 1030; fi
    count=$((RANDOM % 4 + 1))
    for ((i = 0; i < count; i++)); do
      class="${classes[RANDOM % 2]}"
      [ "$class" != "ended" ] || ended=1
      registry_mark_reported "$class" "$root/a"
    done
    expected=""; ((has_exit && !ended)) && expected="$root/a"
    [ "$(registry_jobs_due "$root" /work)" = "$expected" ] || {
      echo "seed ${seed}: exit=${has_exit} ended=${ended}"; return 1; }
  done
}

@test "the list holds the jobs of the given directory, of the directories below it, and of those above it" {
  local root; root="$(fixture_dir)/reg"
  mkdir -p "$root/here" "$root/below" "$root/other" "$root/prefix" "$root/top"
  registry_write_start "$root/here" 1 30 1000 x "/work"
  registry_write_start "$root/below" 1 30 1000 x "/work/sub"
  registry_write_start "$root/other" 1 30 1000 x "/elsewhere"
  registry_write_start "$root/prefix" 1 30 1000 x "/workshop"
  registry_write_start "$root/top" 1 30 1000 x "/"
  [ "$(registry_jobs_due "$root" /work | sort)" = "$(printf '%s\n' "$root/below" "$root/here" "$root/top")" ]
  [ "$(registry_jobs_due "$root" /work/sub | sort)" = "$(printf '%s\n' "$root/below" "$root/here" "$root/top")" ]
  [ "$(registry_jobs_due "$root" /work/sub/deep | sort)" = "$(printf '%s\n' "$root/below" "$root/here" "$root/top")" ]
  [ "$(registry_jobs_due "$root" /workshop | sort)" = "$(printf '%s\n' "$root/prefix" "$root/top")" ]
  [ "$(registry_jobs_due "$root" /work/other | sort)" = "$(printf '%s\n' "$root/here" "$root/top")" ]
}

@test "a reader in the root directory gets the jobs of each directory" {
  local root; root="$(fixture_dir)/reg"
  mkdir -p "$root/a" "$root/b" "$root/c"
  registry_write_start "$root/a" 1 30 1000 x "/"
  registry_write_start "$root/b" 1 30 1000 x "/work"
  registry_write_start "$root/c" 1 30 1000 x "/elsewhere/sub"
  [ "$(registry_jobs_due "$root" / | sort)" = "$(printf '%s\n' "$root/a" "$root/b" "$root/c")" ]
}

# random_path <variable>
#
# Puts a path of zero to three components into the variable. The names are
# few, and one name starts with a different one. Thus two paths are
# frequently on one branch, and a match on characters and not on components
# shows. Four names hold "*", "[", a space, or a backslash, so a match that
# reads a name as a pattern also shows. Zero components is the root
# directory. The caller sets RANDOM. The result is in a variable, because
# bash gives a command substitution a new seed, and the seed of the test
# then reproduces nothing.
random_path() {
  local names=(work workshop w sub '*' '[w]' 'w b' $'w\\') path_length path_i path_out=""
  path_length=$((RANDOM % 4))
  for ((path_i = 0; path_i < path_length; path_i++)); do
    path_out+="/${names[RANDOM % ${#names[@]}]}"
  done
  printf -v "$1" '%s' "${path_out:-/}"
}

# random_slashes <variable>
#
# Puts zero to three slashes into the variable. The caller sets RANDOM.
random_slashes() {
  local all="///"
  printf -v "$1" '%s' "${all:0:RANDOM % 4}"
}

# on_one_branch <path> <path>
#
# The reference decision of the law below. It compares whole components.
on_one_branch() {
  local first second i
  IFS=/ read -ra first <<< "${1#/}"
  IFS=/ read -ra second <<< "${2#/}"
  for ((i = 0; i < ${#first[@]} && i < ${#second[@]}; i++)); do
    [ "${first[i]}" = "${second[i]}" ] || return 1
  done
}

@test "law: the list holds a job exactly when one directory is the other or is above it, on whole components" {
  local seed root i reader path expected listed=0 odd_listed=0 odd_not_listed=0
  for seed in $(seq 1 30); do
    RANDOM=$seed
    root="$(fixture_dir)/reg-${seed}"; expected=()
    random_path reader
    for ((i = 0; i < 8; i++)); do
      random_path path
      mkdir -p "$root/j$i"
      registry_write_start "$root/j$i" 1 30 1000 x "$path"
      if on_one_branch "$reader" "$path"; then
        expected+=("$root/j$i"); listed=$((listed + 1))
        ! is_odd_pair "$reader" "$path" || odd_listed=$((odd_listed + 1))
      else
        ! is_odd_pair "$reader" "$path" || odd_not_listed=$((odd_not_listed + 1))
      fi
    done
    [ "$(registry_jobs_due "$root" "$reader" | sort)" = "$(printf '%s\n' "${expected[@]}" | sed '/^$/d' | sort)" ] || {
      echo "seed ${seed}: reader=${reader}"; return 1; }
  done
  # The law must see a pattern character in a pair that is not equal, on the
  # two sides of the decision.
  { ((listed >= 10)) && ((odd_listed >= 5)) && ((odd_not_listed >= 10)); } || {
    echo "listed: ${listed}, odd and listed: ${odd_listed}, odd and not listed: ${odd_not_listed}"; return 1; }
}

# is_odd_pair <path> <path>
#
# Succeeds when the two paths are not equal, neither is the root directory,
# and one of them holds "*", "[", a space, or a backslash.
is_odd_pair() {
  [ "$1" != "$2" ] && [ "$1" != "/" ] && [ "$2" != "/" ] && [[ "$1$2" == *[*[\ \\]* ]]
}

@test "law: slashes at the end of the reader directory or of the job directory change nothing, for each pair" {
  local seed plain slashed i reader path slashes with_slashes=0
  for seed in $(seq 1 30); do
    RANDOM=$seed
    plain="$(fixture_dir)/plain-${seed}"; slashed="$(fixture_dir)/slashed-${seed}"
    random_path reader
    for ((i = 0; i < 6; i++)); do
      random_path path; random_slashes slashes
      mkdir -p "$plain/j$i" "$slashed/j$i"
      registry_write_start "$plain/j$i" 1 30 1000 x "$path"
      registry_write_start "$slashed/j$i" 1 30 1000 x "${path}${slashes}"
      [ -z "$slashes" ] || with_slashes=$((with_slashes + 1))
    done
    random_slashes slashes
    [ "$(registry_jobs_due "$slashed" "${reader}${slashes}" | sed 's|.*/||' | sort)" = \
      "$(registry_jobs_due "$plain" "$reader" | sed 's|.*/||' | sort)" ] || {
      echo "seed ${seed}: reader=${reader}${slashes}"; return 1; }
  done
  ((with_slashes >= 10)) || { echo "job directories with slashes: ${with_slashes}"; return 1; }
}

@test "law: the reader and the job directory can change places, and the reference decision agrees" {
  local seed root first second expected
  for seed in $SEEDS; do
    RANDOM=$seed
    root="$(fixture_dir)/reg-${seed}"
    random_path first; random_path second
    mkdir -p "$root/a" "$root/b"
    registry_write_start "$root/a" 1 30 1000 x "$first"
    registry_write_start "$root/b" 1 30 1000 x "$second"
    expected=0
    ! on_one_branch "$first" "$second" || expected=1
    [ "$(registry_jobs_due "$root" "$second" | grep -c "/a$")" = "$expected" ] || {
      echo "seed ${seed}: the reader ${second} and the job of ${first}"; return 1; }
    [ "$(registry_jobs_due "$root" "$first" | grep -c "/b$")" = "$expected" ] || {
      echo "seed ${seed}: the reader ${first} and the job of ${second}"; return 1; }
  done
}

# odd_directory <seed>
#
# Prints a path of one to three components. A component holds one to four
# characters from an alphabet with a space, a backslash, a tab, "+", "[",
# and "*". A match that reads the path as a pattern fails on these.
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

@test "law: a reader in a directory gets a job that started in that directory" {
  local seed root directory
  for seed in $(seq 1 40); do
    root="$(fixture_dir)/reg-${seed}"
    directory="$(exact odd_directory "$seed")"; directory="${directory%x}"
    mkdir -p "$root/a"
    registry_write_start "$root/a" 1 30 1000 x "$directory"
    [ "$(registry_jobs_due "$root" "$directory")" = "$root/a" ] || {
      echo "seed ${seed}: '${directory}'"; return 1; }
  done
}

@test "a reader in /work does not get the job of /workshop" {
  local root; root="$(fixture_dir)/reg"
  mkdir -p "$root/a"
  registry_write_start "$root/a" 1 30 1000 x "/workshop"
  [ -z "$(registry_jobs_due "$root" /work)" ]
}

@test "slashes at the end of the reader directory or of the job directory change nothing" {
  local root both; root="$(fixture_dir)/reg"
  mkdir -p "$root/a" "$root/b"
  registry_write_start "$root/a" 1 30 1000 x "/w/sub/deep"
  registry_write_start "$root/b" 1 30 1000 x "/w/sub///"
  both="$(printf '%s\n' "$root/a" "$root/b")"
  [ "$(registry_jobs_due "$root" /w/sub// | sort)" = "$both" ]
  [ "$(registry_jobs_due "$root" /w/sub/deep/// | sort)" = "$both" ]
  [ "$(registry_jobs_due "$root" /w// | sort)" = "$both" ]
  [ "$(registry_jobs_due "$root" // | sort)" = "$both" ]
  [ -z "$(registry_jobs_due "$root" /w/su//)" ]
}

@test "the list of a registry that does not exist is empty" {
  run registry_jobs_due "$(fixture_dir)/absent" /work
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- the removal --------------------------------------------------------------

@test "the cleanup age: an age of exactly the limit is kept, one second more is old" {
  local limit=$JOB_KEEP_SECONDS
  fails activity_is_old "$((1000 + limit))" 1000 "" ""
  activity_is_old "$((1001 + limit))" 1000 "" ""
}

@test "the last activity is the exit record, else the last beat, else the start record" {
  local limit=$JOB_KEEP_SECONDS
  activity_is_old "$((2001 + limit))" 1000 "" ""
  fails activity_is_old "$((2001 + limit))" 1000 2001 ""
  activity_is_old "$((3001 + limit))" 1000 2001 ""
  fails activity_is_old "$((3001 + limit))" 1000 2001 3001
  activity_is_old "$((3002 + limit))" 1000 2001 3001
}

@test "law: a job that is kept at one time was kept at each earlier time" {
  local seed start beat exit_time last t1 t2
  for seed in $SEEDS; do
    RANDOM=$seed
    start=$((RANDOM % 1000))
    beat=""; ((RANDOM % 2)) && beat=$((start + RANDOM % 300))
    exit_time=""; ((RANDOM % 2)) && exit_time=$((start + 300 + RANDOM % 300))
    last="${exit_time:-${beat:-$start}}"
    t1=$((last + JOB_KEEP_SECONDS - RANDOM % 1000))
    t2=$((t1 - RANDOM % 100000))
    ! activity_is_old "$t1" "$start" "$beat" "$exit_time" || {
      echo "seed ${seed}: old at t1=${t1}"; return 1; }
    ! activity_is_old "$t2" "$start" "$beat" "$exit_time" || {
      echo "seed ${seed}: old at t2=${t2}"; return 1; }
  done
}

@test "the removal deletes each job that is old, with a marker or without one, and keeps the others" {
  local root now; root="$(fixture_dir)/reg"; now="$(registry_now)"
  make_job "$root" marked 1000
  make_job "$root" open 1000
  make_job "$root" new "$now"
  registry_mark_reported stale "$root/marked"
  registry_remove_old "$root"
  [ ! -e "$root/marked" ]
  [ ! -e "$root/open" ]
  [ -d "$root/new" ]
}

@test "the removal keeps a job until its last activity is more than one day old, with a marker or without one" {
  local root limit=$JOB_KEEP_SECONDS marked
  for marked in yes no; do
    echo "marked: ${marked}"
    root="$(fixture_dir)/reg-${marked}"
    make_job "$root" started 1000
    make_job "$root" beat 1000 5000
    make_job "$root" ended 1000 5000 0
    registry_write_exit "$root/ended" 9000 0
    if [ "$marked" = "yes" ]; then
      registry_mark_reported stale "$root/started" "$root/beat"
      registry_mark_reported ended "$root/ended"
    fi
    registry_remove_old "$root" "$((1000 + limit))"
    [ -d "$root/started" ]; [ -d "$root/beat" ]; [ -d "$root/ended" ]
    registry_remove_old "$root" "$((5000 + limit))"
    [ ! -e "$root/started" ]; [ -d "$root/beat" ]; [ -d "$root/ended" ]
    registry_remove_old "$root" "$((9000 + limit))"
    [ ! -e "$root/beat" ]; [ -d "$root/ended" ]
    registry_remove_old "$root" "$((9001 + limit))"
    [ ! -e "$root/ended" ]
  done
}

@test "law: the removal deletes a job exactly when its last activity is old and the job is not alive" {
  local seed root dir i age last interval beat now=1000000
  local ages intervals deleted=0 kept=0 kept_alive=0
  for seed in $SEEDS; do
    RANDOM=$seed
    root="$(fixture_dir)/reg-${seed}"; ages=(); intervals=()
    for ((i = 0; i < 6; i++)); do
      dir="$root/j$i"; mkdir -p "$dir"
      # The ages are near the limit, so the two sides of it occur. The long
      # interval gives a job that is alive although its last beat is old.
      age=$((JOB_KEEP_SECONDS - 3 + RANDOM % 7)); last=$((now - age))
      interval=30; ((RANDOM % 2)) || interval=$MAX_BEAT_INTERVAL
      case $((RANDOM % 3)) in
        0) registry_write_start "$dir" 1 "$interval" "$last" x /work ;;
        1) registry_write_start "$dir" 1 "$interval" $((last - 500)) x /work
           registry_write_beat "$dir" "$last" 10 10 ;;
        2) # The exit record is the last activity, and the beat is older.
           beat=$((last - 1 - RANDOM % 400))
           registry_write_start "$dir" 1 "$interval" $((last - 500)) x /work
           registry_write_beat "$dir" "$beat" 10 10
           registry_write_exit "$dir" "$last" $((RANDOM % 256))
           interval=0 ;;
      esac
      ages+=("$age"); intervals+=("$interval")
      case $((RANDOM % 3)) in
        0) ;;
        1) registry_mark_reported stale "$dir" ;;
        2) registry_mark_reported ended "$dir" ;;
      esac
    done
    registry_remove_old "$root" "$now"
    for ((i = 0; i < 6; i++)); do
      # The oracle: old, and not alive. An interval of 0 here marks a job
      # with an exit record, which is never alive.
      if ((ages[i] > JOB_KEEP_SECONDS && ages[i] > STALE_INTERVALS * intervals[i])); then
        [ ! -e "$root/j$i" ] || { echo "seed ${seed}: kept j${i} with the age ${ages[i]}"; return 1; }
        deleted=$((deleted + 1))
      else
        [ -d "$root/j$i" ] || { echo "seed ${seed}: deleted j${i} with the age ${ages[i]}"; return 1; }
        kept=$((kept + 1))
        ((ages[i] <= JOB_KEEP_SECONDS)) || kept_alive=$((kept_alive + 1))
      fi
    done
  done
  # A law that runs only one of its directions proves only that one.
  { ((deleted >= 10)) && ((kept >= 10)) && ((kept_alive >= 5)); } || {
    echo "deleted: ${deleted}, kept: ${kept}, kept because alive: ${kept_alive}"; return 1; }
}

@test "the removal starts one jq process and no other reader for jobs that started in the last day" {
  local root log bin i now=1000000
  root="$(fixture_dir)/reg"; log="$(fixture_dir)/calls"
  bin="$(counted_commands "$log" jq tail)"
  for ((i = 0; i < 5; i++)); do make_job "$root" "j$i" $((now - 100 - i)) $((now - 50)); done
  : > "$log"
  (PATH="${bin}:${PATH}"; registry_remove_old "$root" "$now")
  [ "$(cat "$log")" = "jq" ] || { echo "started: $(tr '\n' ' ' < "$log")"; return 1; }
  [ -d "$root/j0" ]
}

@test "the removal reads the records of a job only when the job started more than one day ago" {
  local root log bin now=1000000
  root="$(fixture_dir)/reg"; log="$(fixture_dir)/calls"
  bin="$(counted_commands "$log" jq tail)"
  make_job "$root" young $((now - 100))
  make_job "$root" old $((now - JOB_KEEP_SECONDS - 5))
  : > "$log"
  (PATH="${bin}:${PATH}"; registry_remove_old "$root" "$now")
  [ "$(grep -c tail "$log")" -eq 1 ]
  [ -d "$root/young" ]
  [ ! -e "$root/old" ]
}

@test "the removal keeps a job that is alive, also when its last beat is more than one day old" {
  local root interval=$MAX_BEAT_INTERVAL; root="$(fixture_dir)/reg"
  mkdir -p "$root/a"
  registry_write_start "$root/a" 1 "$interval" 1000 x /work
  registry_remove_old "$root" "$((1001 + JOB_KEEP_SECONDS))"
  [ -d "$root/a" ]
  registry_remove_old "$root" "$((1000 + STALE_INTERVALS * interval))"
  [ -d "$root/a" ]
  registry_remove_old "$root" "$((1001 + STALE_INTERVALS * interval))"
  [ ! -e "$root/a" ]
}

@test "the removal keeps the log of a job that a reader reported a moment ago" {
  local root now; root="$(fixture_dir)/reg"; now="$(registry_now)"
  make_job "$root" a "$now" "$now" 0
  printf 'the output\n' > "$(registry_log_path "$root/a")"
  registry_mark_reported ended "$root/a"
  registry_remove_old "$root"
  [ "$(cat "$(registry_log_path "$root/a")")" = "the output" ]
}

@test "the removal does not delete a directory that is not a job, with a marker or without one" {
  local root; root="$(fixture_dir)/reg"
  mkdir -p "$root/marked" "$root/empty"
  registry_mark_reported stale "$root/marked"
  registry_remove_old "$root"
  [ -d "$root/marked" ]
  [ -d "$root/empty" ]
}

@test "the removal with an empty root reads no directory" {
  local log; log="$(fixture_dir)/calls"; : > "$log"
  # The stand-ins record each directory that the removal reads or deletes.
  # With no guard, the pattern of the removal is "/*/". The stand-ins are in
  # a subshell, because bats calls rm after the test.
  # shellcheck disable=SC2329 # The removal calls the two stand-ins.
  (
    job_is_old() { printf 'read %s\n' "$1" >> "$log"; return 1; }
    rm() { printf 'rm %s\n' "$*" >> "$log"; }
    registry_remove_old "" 5000
  )
  [ ! -s "$log" ] || { echo "the removal made $(wc -l < "$log") calls: $(head -n 3 "$log")"; return 1; }
}

@test "the removal with an empty root deletes nothing" {
  local root; root="$(fixture_dir)/reg"
  make_job "$root" a 1000
  registry_mark_reported stale "$root/a"
  cd "$(fixture_dir)"
  run registry_remove_old ""
  [ "$status" -eq 0 ]
  [ -d "$root/a" ]
}

# --- the interval -------------------------------------------------------------

@test "the shortest interval of a set of jobs" {
  local root; root="$(fixture_dir)/reg"
  mkdir -p "$root/a" "$root/b"
  registry_write_start "$root/a" 1 30 1000 x /d
  registry_write_start "$root/b" 1 7 1000 x /d
  [ "$(registry_shortest_interval "$root/a" "$root/b")" = "7" ]
}

@test "the shortest interval is the default when no start record is readable" {
  local root; root="$(fixture_dir)/reg"
  mkdir -p "$root/a"
  printf 'not json\n' > "$root/a/start"
  [ "$(registry_shortest_interval "$root/a")" = "$DEFAULT_BEAT_INTERVAL" ]
}

@test "the beat interval is CLAUDE_JOB_INTERVAL, or the default when the variable is absent" {
  CLAUDE_JOB_INTERVAL=7 run registry_beat_interval
  [ "$status" -eq 0 ]; [ "$output" = "7" ]
  unset CLAUDE_JOB_INTERVAL
  run registry_beat_interval
  [ "$status" -eq 0 ]; [ "$output" = "$DEFAULT_BEAT_INTERVAL" ]
}

# A whole number from 1 through 86400, with no zero at its start. The oracle
# is a glob match, a length test, and an arithmetic test. It does not use
# the pattern of the code under test. The length test comes first, because
# the arithmetic of a number with 20 digits overflows.
is_valid_interval() {
  [[ -n "$1" && "$1" != *[!0-9]* && "$1" != 0* ]] && [ "${#1}" -le 5 ] && (($1 <= 86400))
}

# random_interval <seed>
#
# Prints a candidate for the interval. One seed in three gives text with a
# character that is not a digit. One gives a number of 1 to 6 digits, so
# values on the two sides of the limit occur. One gives a number of 7 to 22
# digits, so values that overflow the arithmetic occur.
random_interval() {
  local mixed=(0 1 2 5 9 . - ' ' s $'\n') digits=(0 1 2 3 4 5 6 7 8 9) length i out=""
  RANDOM=$1
  case $(($1 % 3)) in
    0) length=$((RANDOM % 4 + 1))
       for ((i = 0; i < length; i++)); do out+="${mixed[RANDOM % ${#mixed[@]}]}"; done ;;
    1) length=$((RANDOM % 6 + 1))
       for ((i = 0; i < length; i++)); do out+="${digits[RANDOM % ${#digits[@]}]}"; done ;;
    2) length=$((RANDOM % 16 + 7))
       for ((i = 0; i < length; i++)); do out+="${digits[RANDOM % ${#digits[@]}]}"; done ;;
  esac
  printf '%s' "$out"
}

@test "the limits of the beat interval: 1 and 86400 are valid, 86401 and a number that overflows are not" {
  local value
  for value in 1 86400; do
    CLAUDE_JOB_INTERVAL="$value" run registry_beat_interval
    { [ "$status" -eq 0 ] && [ "$output" = "$value" ]; } || { echo "rejected: ${value}"; return 1; }
  done
  for value in 86401 99999 100000 6148914691236517206 18446744073709551617; do
    CLAUDE_JOB_INTERVAL="$value" run registry_beat_interval
    [ "$status" -eq 2 ] || { echo "accepted: ${value}"; return 1; }
  done
}

@test "law: a job with the longest interval is alive when it is 10 seconds old" {
  local seed start
  for seed in $SEEDS; do
    RANDOM=$seed
    start=$((RANDOM * 60000))
    [ "$(classify_job "$((start + 10))" "$start" 86400 "" "")" = "alive" ] || {
      echo "seed ${seed}: start=${start}"; return 1; }
  done
}

@test "law: the function accepts exactly a whole number from 1 through 86400 and prints it unchanged" {
  local seed value accepted=0 rejected=0
  for seed in $(seq 1 120); do
    value="$(exact random_interval "$seed")"; value="${value%x}"
    CLAUDE_JOB_INTERVAL="$value" run registry_beat_interval
    if is_valid_interval "$value"; then
      { [ "$status" -eq 0 ] && [ "$output" = "$value" ]; } || { echo "seed ${seed}: rejected '${value}'"; return 1; }
      accepted=$((accepted + 1))
    else
      [ "$status" -eq 2 ] || { echo "seed ${seed}: accepted '${value}'"; return 1; }
      rejected=$((rejected + 1))
    fi
  done
  # A law that runs only one of its two directions proves only that one.
  { ((accepted >= 10)) && ((rejected >= 10)); } || { echo "accepted: ${accepted}, rejected: ${rejected}"; return 1; }
}

@test "a beat interval that is not a whole number from 1 through 86400 fails with the status 2" {
  local value
  for value in 30s 0.5 0 -3 "1 2" 007x 86401; do
    CLAUDE_JOB_INTERVAL="$value" run registry_beat_interval
    [ "$status" -eq 2 ] || { echo "accepted: ${value}"; return 1; }
    [[ "$output" == *"CLAUDE_JOB_INTERVAL"* ]]
  done
}
