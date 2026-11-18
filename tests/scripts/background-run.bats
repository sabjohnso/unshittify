#!/usr/bin/env bats
# Tests of scripts/background-run.sh, the wrapper that starts a background
# job and writes its heartbeat. The laws of the processor time are in
# REQUIREMENTS.org under "Laws of the processor time". Each test uses a
# throwaway registry and an interval of one second.

load helpers

setup() {
  WRAPPER="${SCRIPTS_DIR}/background-run.sh"
  # shellcheck source=../../scripts/background-run.sh disable=SC1091
  source "$WRAPPER"
  export CLAUDE_JOB_REGISTRY; CLAUDE_JOB_REGISTRY="$(fixture_root)"
  export CLAUDE_JOB_INTERVAL=1
}

# The one job in the throwaway registry.
the_job() {
  local dirs=("$CLAUDE_JOB_REGISTRY"/*/)
  printf '%s' "${dirs[0]%/}"
}

# beat_count <job-dir>
#
# Prints the number of beats that the job has. No test here writes 1000
# beats.
beat_count() {
  registry_last_beats "$1" 1000 | wc -l
}

# stat_line <pid> <ppid> <utime> <stime> <cutime> <cstime> [comm] [state]
#
# One line in the format of /proc/<pid>/stat. The default name holds a space
# and a ")", because the kernel does not escape them.
stat_line() {
  printf '%s (%s) %s %s 1 1 0 -1 4194304 10 0 0 0 %s %s %s %s 20 0 1 0 100 0 0\n' \
    "$1" "${7:-a b) c}" "${8:-S}" "$2" "$3" "$4" "$5" "$6"
}

# invalid_interval <seed>
#
# Prints a value that is not a whole number of seconds from 1 through 86400.
invalid_interval() {
  RANDOM=$1
  local number=$((RANDOM % 90 + 1))
  case $((RANDOM % 5)) in
    0) printf '%ss' "$number" ;;
    1) printf '%s.%s' "$number" $((RANDOM % 10)) ;;
    2) printf '0.%s' $((RANDOM % 9 + 1)) ;;
    3) printf -- '-%s' "$number" ;;
    4) printf '0' ;;
  esac
}

SEEDS="1 2 3 5 8 13 21 34"

# The seeds of the laws of the processor time. A tree has many shapes, so
# these laws use more seeds than the others.
TREE_SEEDS="$(seq 1 50)"

# Each signal that the wrapper catches, with the exit status that it causes.
CAUGHT_SIGNALS="TERM:143 INT:130 HUP:129"

# with_default_signals <command> [argument ...]
#
# Runs the command with the default handlers of INT and QUIT. A shell with no
# job control starts a background command with these two signals ignored, and
# a bash process cannot catch a signal that it got ignored. The command
# replaces the shell, so its pid is the pid of the background process. Thus
# call this function only in the background or with "run".
with_default_signals() {
  exec env --default-signal=INT,QUIT "$@"
}

# random_tree <seed>
#
# Prints the stat lines of a tree with the root 100 and 1 to 6 descendants,
# then two processes that are outside the tree. Each process of the tree has
# four random times. The function sets EXPECTED_TICKS to their sum, so a
# test has an oracle that does not come from the code under test. Call it
# with a redirection and not in a command substitution, or the variable is
# lost.
random_tree() {
  local count i parent t1 t2 t3 t4
  RANDOM=$1
  count=$((RANDOM % 6 + 1))
  EXPECTED_TICKS=0
  for ((i = 0; i <= count; i++)); do
    parent=1; ((i == 0)) || parent=$((100 + RANDOM % i))
    t1=$((RANDOM % 50)); t2=$((RANDOM % 50)); t3=$((RANDOM % 50)); t4=$((RANDOM % 50))
    EXPECTED_TICKS=$((EXPECTED_TICKS + t1 + t2 + t3 + t4))
    stat_line $((100 + i)) "$parent" "$t1" "$t2" "$t3" "$t4"
  done
  stat_line 900 1 7777 7777 7777 7777
  stat_line 901 900 7777 7777 7777 7777
}

# --- the pure functions -------------------------------------------------------

@test "the total is the sum of the four times of the job and its descendants" {
  local total
  total="$({ stat_line 100 1 1 2 3 4; stat_line 101 100 10 20 0 0; stat_line 102 101 100 200 0 0; } | tree_cpu_ticks 100)"
  [ "$total" = "340" ]
}

@test "law: the total is the sum over the tree, and a process outside the tree adds nothing" {
  local seed lines; lines="$(fixture_root)/stat"
  for seed in $TREE_SEEDS; do
    random_tree "$seed" > "$lines"
    [ "$(tree_cpu_ticks 100 < "$lines")" = "$EXPECTED_TICKS" ] || {
      echo "seed ${seed}: expected ${EXPECTED_TICKS}"; return 1; }
  done
}

@test "law: the order of the entries does not change the total" {
  local seed lines; lines="$(fixture_root)/stat"
  for seed in $TREE_SEEDS; do
    random_tree "$seed" > "$lines"
    [ "$(shuf --random-source=<(yes "$seed") "$lines" | tree_cpu_ticks 100)" = "$EXPECTED_TICKS" ] || {
      echo "seed ${seed}: expected ${EXPECTED_TICKS}"; return 1; }
  done
}

@test "a tree with no entry has the total zero" {
  [ "$(tree_cpu_ticks 100 < /dev/null)" = "0" ]
}

@test "law: the beat holds the total now minus the total at the last beat" {
  local seed before after
  for seed in $SEEDS; do
    RANDOM=$seed
    before=$((RANDOM % 1000)); after=$((before + RANDOM % 1000))
    [ "$(cpu_delta_ms "$before" "$after" 100)" = "$(((after - before) * 10))" ] || {
      echo "seed ${seed}"; return 1; }
    [ "$(cpu_delta_ms "$before" "$after" 1000)" = "$((after - before))" ] || {
      echo "seed ${seed}: 1000 ticks in a second"; return 1; }
  done
}

@test "a number of ticks that is not a whole millisecond is rounded down" {
  [ "$(cpu_delta_ms 0 1 300)" = "3" ]
  [ "$(cpu_delta_ms 0 2 300)" = "6" ]
}

@test "law: a total that decreased gives zero" {
  local seed before after hz
  for seed in $SEEDS; do
    RANDOM=$seed
    after=$((RANDOM % 1000)); before=$((after + 1 + RANDOM % 1000)); hz=$((RANDOM % 1000 + 1))
    [ "$(cpu_delta_ms "$before" "$after" "$hz")" = "0" ] || { echo "seed ${seed}"; return 1; }
  done
}

@test "the reader of /proc finds a child of the job" {
  bash -c 'sleep 5 & wait' &
  local parent=$!
  sleep 0.3
  local lines; lines="$(read_tree_stats "$parent")"
  kill "$parent"; pkill -P "$parent" || true
  [ "$(printf '%s\n' "$lines" | wc -l)" -eq 2 ]
}

@test "the reader of /proc prints nothing for a process that ended" {
  true & local gone=$!; wait "$gone"
  [ -z "$(read_tree_stats "$gone")" ]
}

@test "law: a stat line with a state that is not Z or X shows a live process" {
  local seed states=(R S D T t I) state
  for seed in $SEEDS; do
    RANDOM=$seed
    state="${states[RANDOM % ${#states[@]}]}"
    stat_is_live "$(stat_line $((RANDOM + 1)) 1 0 0 0 0 "a) Z b) X c" "$state")" || {
      echo "seed ${seed}: state ${state}"; return 1; }
  done
}

@test "law: a stat line of a zombie or a dead process shows no live process" {
  local seed states=(Z X) state
  for seed in $SEEDS; do
    RANDOM=$seed
    state="${states[RANDOM % ${#states[@]}]}"
    ! stat_is_live "$(stat_line $((RANDOM + 1)) 1 0 0 0 0 "a) S b) R c" "$state")" || {
      echo "seed ${seed}: state ${state}"; return 1; }
  done
}

@test "an empty stat line shows no live process" {
  run stat_is_live ""
  [ "$status" -ne 0 ]
}

@test "the process test finds this shell and does not find a process that ended" {
  true & local gone=$!; wait "$gone"
  process_lives "$BASHPID"
  run process_lives "$gone"
  [ "$status" -ne 0 ]
}

# --- the beat writer and the wait ---------------------------------------------

@test "the beat writer writes no beat and stops when the wrapper is gone" {
  local job log beater alive=no
  job="$(fixture_root)"; log="$(registry_log_path "$job")"; : > "$log"
  true & local gone=$!; wait "$gone"
  write_beats "$job" "$BASHPID" 1 "$log" "$gone" 3>&- &
  beater=$!
  sleep 2.5
  if kill -0 "$beater" 2>/dev/null; then alive=yes; kill "$beater"; fi
  [ "$alive" = "no" ]
  [ "$(beat_count "$job")" -eq 0 ]
}

@test "law: a signal that arrived before the wait goes to the job" {
  local name expected status
  for name in TERM:143 HUP:129; do
    sleep 5 3>&- &
    PENDING_SIGNAL="${name%%:*}"; expected="${name##*:}"; status=0
    wait_for_job $! || status=$?
    [ "$status" -eq "$expected" ] || { echo "${name}: status ${status}"; return 1; }
    [ -z "$PENDING_SIGNAL" ]
  done
}

# --- the wrapper --------------------------------------------------------------

@test "the wrapper with no command prints the usage and fails" {
  run "$WRAPPER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
}

@test "the wrapper returns the status of the job and writes the three records" {
  run "$WRAPPER" bash -c 'echo hi; sleep 2.5; exit 5'
  [ "$status" -eq 5 ]
  local job; job="$(the_job)"
  [[ "$output" == *"$job"* ]]
  [ "$(registry_field "$job" start command)" = "bash -c echo hi; sleep 2.5; exit 5" ]
  [ "$(registry_field "$job" start interval)" = "1" ]
  [ "$(registry_field "$job" start cwd)" = "$PWD" ]
  [ "$(beat_count "$job")" -ge 2 ]
  [ "$(registry_field "$job" beat log_bytes)" = "3" ]
  [ "$(registry_field "$job" exit status)" = "5" ]
  [ "$(cat "$(registry_log_path "$job")")" = "hi" ]
}

@test "a beat holds the processor time of a descendant of the job" {
  run "$WRAPPER" timeout 2.5 bash -c 'while :; do :; done'
  [ "$status" -eq 124 ]
  local job; job="$(the_job)"
  [ "$(registry_field "$job" beat cpu_ms)" -gt 300 ]
}

@test "a beat of an idle job holds a processor time near zero" {
  run "$WRAPPER" sleep 2.5
  [ "$status" -eq 0 ]
  [ "$(registry_field "$(the_job)" beat cpu_ms)" -lt 100 ]
}

@test "law: each signal that the wrapper catches stops the job and writes its status" {
  local name signal expected wrapper_pid job status
  for name in $CAUGHT_SIGNALS; do
    signal="${name%%:*}"; expected="${name##*:}"; status=0
    rm -rf "${CLAUDE_JOB_REGISTRY:?}"/*
    with_default_signals "$WRAPPER" sleep 6 > /dev/null 3>&- &
    wrapper_pid=$!
    sleep 1
    job="$(the_job)"
    kill -s "$signal" "$wrapper_pid"
    wait "$wrapper_pid" || status=$?
    [ "$status" -eq "$expected" ] || { echo "${signal}: status ${status}"; return 1; }
    [ "$(registry_field "$job" exit status)" = "$expected" ] || {
      echo "${signal}: exit status $(registry_field "$job" exit status)"; return 1; }
    ! kill -0 "$(registry_field "$job" start pid)" 2>/dev/null || {
      echo "${signal}: the job still runs"; return 1; }
  done
}

@test "the job starts with the default handlers of INT and QUIT" {
  run with_default_signals "$WRAPPER" grep SigIgn /proc/self/status
  [ "$status" -eq 0 ]
  local ignored; ignored="$(awk '{ print $2 }' "$(registry_log_path "$(the_job)")")"
  # INT is signal 2 and QUIT is signal 3. Their bits in the mask are 2 and 4.
  [ $((16#$ignored & 6)) -eq 0 ] || { echo "ignored signals: ${ignored}"; return 1; }
}

@test "a signal from the job at its start stops the job and writes the exit record" {
  # shellcheck disable=SC2016 # The job must expand PPID, not this test.
  run "$WRAPPER" bash -c 'kill -TERM "$PPID"; exec sleep 5'
  [ "$status" -eq 143 ]
  [ "$(registry_field "$(the_job)" exit status)" = "143" ]
}

# signal_after_mktemp <signal>
#
# Makes a stand-in for mktemp and prints the directory that holds it. The
# stand-in makes the directory, and then it sends the signal to the wrapper
# before it prints the name. Thus the signal arrives after the wrapper made
# the job directory and before the job starts, with no wait and no race.
# The wrapper is the highest process above the stand-in that runs the
# wrapper script: a command substitution is a copy of the wrapper.
signal_after_mktemp() {
  local bin; bin="$(fixture_root)"
  # shellcheck disable=SC2016 # The stand-in must expand these, not this test.
  printf '%s\n' '#!/usr/bin/env bash' \
    "made=\"\$('$(command -v mktemp)' \"\$@\")\"" \
    'pid=$PPID' \
    'while parent="$(ps -o ppid= -p "$pid" | tr -d " ")" &&' \
    '  grep -qa background-run.sh "/proc/${parent}/cmdline"; do pid=$parent; done' \
    "kill -s $1 \"\$pid\"" \
    'printf "%s\n" "$made"' > "$bin/mktemp"
  chmod +x "$bin/mktemp"
  printf '%s' "$bin"
}

@test "law: a signal that arrives after the wrapper made the job directory gives a job with a start record and an exit record" {
  local name signal expected bin job
  for name in TERM:143 HUP:129; do
    signal="${name%%:*}"; expected="${name##*:}"
    rm -rf "${CLAUDE_JOB_REGISTRY:?}"/*
    bin="$(signal_after_mktemp "$signal")"
    run env PATH="${bin}:${PATH}" "$WRAPPER" sleep 5
    job="$(the_job)"
    [ "$status" -eq "$expected" ] || { echo "${signal}: status ${status}"; return 1; }
    [ -n "$(registry_field "$job" start pid)" ] || { echo "${signal}: no start record in ${job}"; return 1; }
    [ "$(registry_field "$job" exit status)" = "$expected" ] || {
      echo "${signal}: exit status $(registry_field "$job" exit status)"; return 1; }
  done
}

# signal_to_mktemp <signal>
#
# Makes a stand-in for mktemp and prints the directory that holds it. The
# stand-in makes the directory, and then it sends the signal to itself
# before it prints the name. Thus the signal arrives at the child of the
# wrapper after that child made the job directory, as a signal to the
# process group does, with no wait and no race.
signal_to_mktemp() {
  local bin; bin="$(fixture_root)"
  # shellcheck disable=SC2016 # The stand-in must expand these, not this test.
  printf '%s\n' '#!/usr/bin/env bash' \
    "made=\"\$('$(command -v mktemp)' \"\$@\")\"" \
    "kill -s $1 \"\$\$\"" \
    'printf "%s\n" "$made"' > "$bin/mktemp"
  chmod +x "$bin/mktemp"
  printf '%s' "$bin"
}

@test "law: a signal to the process that makes the job directory leaves no directory with no start record" {
  local signal bin dirs
  for signal in TERM INT HUP; do
    rm -rf "${CLAUDE_JOB_REGISTRY:?}"/*
    bin="$(signal_to_mktemp "$signal")"
    run with_default_signals env PATH="${bin}:${PATH}" "$WRAPPER" true
    [ "$status" -eq 0 ] || { echo "${signal}: status ${status}"; return 1; }
    dirs=("$CLAUDE_JOB_REGISTRY"/*/)
    [ "${#dirs[@]}" -eq 1 ] || { echo "${signal}: ${#dirs[@]} directories"; return 1; }
    [ -n "$(registry_field "$(the_job)" start pid)" ] || { echo "${signal}: no start record"; return 1; }
    [ "$(registry_field "$(the_job)" exit status)" = "0" ] || { echo "${signal}: no exit record"; return 1; }
  done
}

@test "a wrapper that got a KILL signal leaves a stale job and no beat writer" {
  "$WRAPPER" sleep 30 > /dev/null 3>&- &
  local wrapper_pid=$! job job_pid child beater="" before after class alive=no
  sleep 1.5
  job="$(the_job)"; job_pid="$(registry_field "$job" start pid)"
  for child in $(pgrep -P "$wrapper_pid"); do
    [ "$child" = "$job_pid" ] || beater="$child"
  done
  kill -KILL "$wrapper_pid"
  sleep 1.5
  before="$(beat_count "$job")"
  sleep 3.5
  after="$(beat_count "$job")"
  class="$(job_class "$job" "$(registry_now)")"
  if kill -0 "$beater" 2>/dev/null; then alive=yes; kill "$beater"; fi
  kill "$job_pid"
  [ -n "$beater" ]
  [ "$before" -ge 1 ]
  [ "$after" -eq "$before" ]
  [ "$class" = "stale" ]
  [ "$alive" = "no" ]
  [ -z "$(registry_field "$job" exit status)" ]
}

@test "law: an interval that is not valid stops the wrapper before the job starts" {
  local seed marker; marker="$(fixture_root)/marker"
  for seed in $SEEDS; do
    CLAUDE_JOB_INTERVAL="$(invalid_interval "$seed")"
    run "$WRAPPER" touch "$marker"
    [ "$status" -eq 2 ] || { echo "seed ${seed}: \"${CLAUDE_JOB_INTERVAL}\" gave status ${status}"; return 1; }
    [[ "$output" == *"CLAUDE_JOB_INTERVAL"* ]]
    [ ! -e "$marker" ] || { echo "seed ${seed}: \"${CLAUDE_JOB_INTERVAL}\" ran the command"; return 1; }
    [ -z "$(ls -A "$CLAUDE_JOB_REGISTRY")" ] || {
      echo "seed ${seed}: \"${CLAUDE_JOB_INTERVAL}\" made a job directory"; return 1; }
  done
}

@test "each named bad interval stops the wrapper before the job starts" {
  local value marker; marker="$(fixture_root)/marker"
  for value in 30s 0.5 0 86401 6148914691236517206; do
    CLAUDE_JOB_INTERVAL="$value"
    run "$WRAPPER" touch "$marker"
    [ "$status" -eq 2 ] || { echo "\"${value}\" gave status ${status}"; return 1; }
    [ ! -e "$marker" ] || { echo "\"${value}\" ran the command"; return 1; }
    [ -z "$(ls -A "$CLAUDE_JOB_REGISTRY")" ] || { echo "\"${value}\" made a job directory"; return 1; }
  done
}

@test "an interval that is not valid makes no registry directory" {
  local absent; absent="$(fixture_root)/absent"
  CLAUDE_JOB_REGISTRY="$absent" CLAUDE_JOB_INTERVAL=30s run "$WRAPPER" true
  [ "$status" -eq 2 ]
  [ ! -e "$absent" ]
}

@test "the interval is the default when the caller gives none" {
  unset CLAUDE_JOB_INTERVAL
  run "$WRAPPER" true
  [ "$status" -eq 0 ]
  [ "$(registry_field "$(the_job)" start interval)" = "$DEFAULT_BEAT_INTERVAL" ]
  [ "$DEFAULT_BEAT_INTERVAL" = "30" ]
}

@test "the wrapper removes each job that is more than one day old when it starts, with a marker or without one" {
  local marked="${CLAUDE_JOB_REGISTRY}/marked" open="${CLAUDE_JOB_REGISTRY}/open"
  mkdir -p "$marked" "$open"
  registry_write_start "$marked" 1 30 1000 x /d
  registry_write_start "$open" 1 30 1000 x /d
  registry_mark_reported stale "$marked"
  run "$WRAPPER" true
  [ "$status" -eq 0 ]
  [ ! -e "$marked" ]
  [ ! -e "$open" ]
}

@test "the wrapper finds its library when its path holds no slash" {
  cd "$SCRIPTS_DIR"
  run bash background-run.sh true
  [ "$status" -eq 0 ]
  [ "$(registry_field "$(the_job)" exit status)" = "0" ]
}
