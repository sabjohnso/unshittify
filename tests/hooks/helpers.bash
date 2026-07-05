# Shared helpers for the Stop-hook bats test suites.
#
# Loaded via `load helpers` at the top of each *.bats file. Provides:
#   - HOOKS_DIR path constant
#   - stdin_payload:   build a synthetic Stop-hook stdin JSON payload
#   - run_hook:        invoke a hook script with a given stdin payload,
#                      capturing $status/$output the same way bats' own
#                      `run` does
#   - write_transcript: write a synthetic JSONL transcript fixture to a
#                      throwaway file and print its path
#   - decision_field / reason_field: pull fields out of $output when the
#                      hook emitted a block-decision JSON object

# shellcheck disable=SC2034 # consumed by the *.bats files that `load helpers`,
# which shellcheck can't see across files since .bats isn't shell it parses.
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../hooks" && pwd)"

# stdin_payload key=value [key=value ...]
#
# Builds the JSON object a Stop hook receives on stdin. Recognized keys:
# session_id, transcript_path, cwd, prompt_id, stop_hook_active,
# last_assistant_message. Any key not supplied is omitted (scripts under
# test already treat missing fields as their jq `// default` fallback).
stdin_payload() {
  local jq_args=() filter_parts=()
  local arg key value
  for arg in "$@"; do
    key="${arg%%=*}"
    value="${arg#*=}"
    jq_args+=(--arg "$key" "$value")
    filter_parts+=("\"${key}\": \$${key}")
  done
  local filter="{"
  local part first=1
  for part in "${filter_parts[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      filter="${filter} ${part}"
      first=0
    else
      filter="${filter}, ${part}"
    fi
  done
  filter="${filter} }"
  jq -n "${jq_args[@]}" "$filter"
}

# run_hook <script-path> <stdin-json>
#
# Runs the given hook script with the given JSON string on stdin, using
# bats' own `run` so that $status and $output are populated from stdout
# alone (the decision-JSON channel). stderr (diagnostic-only warnings) is
# captured separately into $HOOK_STDERR, a file path, so tests asserting on
# $output's JSON shape aren't broken by unrelated stderr noise, while tests
# that specifically care about a diagnostic can still read it.
run_hook() {
  local script="$1"
  local stdin="$2"
  HOOK_STDERR="$(mktemp "${BATS_TMPDIR:-/tmp}/hook_stderr.XXXXXX")"
  run bash -c 'printf "%s" "$1" | "$2" 2>"$3"' _ "$stdin" "$script" "$HOOK_STDERR"
}

# write_transcript <heredoc-content>
#
# Writes the given content (one JSON object per line) to a fresh temp file
# and prints its path. Caller is responsible for nothing further; files
# are written under BATS_TMPDIR which bats/the OS clean up.
write_transcript() {
  local content="$1"
  local file
  file="$(mktemp "${BATS_TMPDIR:-/tmp}/transcript.XXXXXX.jsonl")"
  printf '%s\n' "$content" > "$file"
  printf '%s' "$file"
}

decision_field() {
  printf '%s' "$1" | jq -r '.decision // empty'
}

reason_field() {
  printf '%s' "$1" | jq -r '.reason // empty'
}

# tool_use_event <name> [skill=<skill>] [subagent_type=<type>]
#
# Prints one compact-JSON transcript line for an assistant tool_use event,
# for building up synthetic transcripts line by line in tests.
tool_use_event() {
  local name="$1"; shift
  local skill="" subagent_type=""
  local arg
  for arg in "$@"; do
    case "$arg" in
      skill=*) skill="${arg#skill=}" ;;
      subagent_type=*) subagent_type="${arg#subagent_type=}" ;;
    esac
  done
  jq -nc --arg name "$name" --arg skill "$skill" --arg subagent_type "$subagent_type" \
    '{type:"assistant", message:{content:[
       {type:"tool_use", name:$name, input: (
         ({} + (if $skill != "" then {skill:$skill} else {} end)
             + (if $subagent_type != "" then {subagent_type:$subagent_type} else {} end)))}
     ]}}'
}

last_prompt_marker() {
  printf '%s' '{"type":"last-prompt"}'
}
