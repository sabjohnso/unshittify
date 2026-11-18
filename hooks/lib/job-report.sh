#!/usr/bin/env bash
# The text that tells the model about a background job, and the sequence
# that reports the dead jobs. A script sources this file after
# lib/job-registry.sh. Nothing executes it on its own. The watcher and the
# report hook call report_dead_jobs, so the model learns one layout and the
# two readers mark a job by one rule. The file reads a job only through the
# functions of the registry. It knows no record format and no file name.

# report_dead_jobs <printer> <now> [job-dir ...]
#
# Reports each given job that is not alive, and then marks it. <printer> is
# the name of a function of the caller. It gets the reports as one argument
# and prints them in the layout of that caller. The function reads the class
# of each job one time, before the print. The mark comes after the print.
# Thus a failed print does not lose a report, and the class in the marker is
# the class in the report.
#
# The status is 0 after a report, 1 when no given job is dead, and 2 when
# the printer fails. The last two cases print nothing here and mark no job.
report_dead_jobs() {
  local printer="$1" dead
  shift
  if dead="$(registry_job_classes "$@" | grep -v $'^alive\t')"; then
    "$printer" "$(reports_of_classes <<< "$dead")" || return 2
    mark_classes_reported <<< "$dead"
  else
    return 1
  fi
}

# --- private: only the functions of this file call the names below ------------

# reports_of_classes
#
# Reads the lines of registry_job_classes on stdin. It prints the report of
# each job, with an empty line after each one.
reports_of_classes() {
  local class dir
  while IFS=$'\t' read -r class dir; do
    job_report "$dir" "$class"
    printf '\n'
  done
}

# mark_classes_reported
#
# Reads the lines of registry_job_classes on stdin. It marks each job as
# reported with the class on its line.
mark_classes_reported() {
  local class dir
  while IFS=$'\t' read -r class dir; do
    registry_mark_reported "$class" "$dir"
  done
}

# job_report <job-dir> <class>
#
# Prints what the model needs to judge one job: the command, the class, the
# last three beats, and the path of the log.
job_report() {
  local dir="$1" class="$2" time cpu_ms log_bytes
  printf 'job: %s\n' "$dir"
  printf 'command: %s\n' "$(registry_job_command "$dir")"
  printf 'class: %s\n' "$class"
  printf 'last beats (cpu_ms and log_bytes are facts, not a verdict):\n'
  while IFS=$'\t' read -r time cpu_ms log_bytes; do
    printf '  time=%s cpu_ms=%s log_bytes=%s\n' "$time" "$cpu_ms" "$log_bytes"
  done < <(registry_last_beats "$dir" 3)
  printf 'log: %s\n' "$(registry_log_path "$dir")"
}
