# Shared helpers for the bats test suites of the Stop hooks.
#
# Each *.bats file loads this file with `load helpers` at its top. It gives:
#   - HOOKS_DIR, a path constant
#   - stdin_payload:   builds a synthetic stdin JSON payload for a Stop hook
#   - run_hook:        runs a hook script with a given stdin payload and
#                      captures $status and $output as the `run` of bats does
#   - write_transcript: writes a synthetic JSONL transcript fixture to a
#                      throwaway file and prints its path
#   - decision_field / reason_field: read a field from $output when the hook
#                      emitted a block-decision JSON object

# shellcheck disable=SC2034 # The *.bats files that `load helpers` use it.
# The linter cannot see across files, because it does not parse .bats.
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../hooks" && pwd)"

# fixture_dir. The directory that holds every throwaway fixture.
#
# BATS_TEST_TMPDIR is per test, and bats removes it. BATS_TMPDIR is shared
# across the run, and nothing removes it. The transcripts and the stderr
# captures written there accumulated in /tmp, one per assertion, run after
# run. The fallbacks keep the suite in operation on a bats that is too old
# to set the per-test variable.
fixture_dir() {
  printf '%s' "${BATS_TEST_TMPDIR:-${BATS_TMPDIR:-/tmp}}"
}

# stdin_payload key=value [key=value ...]
#
# Builds the JSON object that a Stop hook receives on stdin. The known keys
# are session_id, transcript_path, cwd, prompt_id, stop_hook_active, and
# last_assistant_message. A key that is not given is omitted. The scripts
# under test treat a missing field with their jq `// default` fallback.
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
# Runs the given hook script with the given JSON string on stdin. It uses
# the `run` of bats, so $status and $output come from stdout alone, which is
# the channel of the decision JSON. The function captures stderr (the
# diagnostic warnings) into a file named by $HOOK_STDERR. Thus unrelated
# stderr text does not break a test that asserts on the JSON shape of
# $output, and a test that cares about a diagnostic can read it.
run_hook() {
  local script="$1"
  local stdin="$2"
  HOOK_STDERR="$(mktemp "$(fixture_dir)/hook_stderr.XXXXXX")"
  run bash -c 'printf "%s" "$1" | "$2" 2>"$3"' _ "$stdin" "$script" "$HOOK_STDERR"
}

# write_transcript <heredoc-content>
#
# Writes the given content (one JSON object per line) to a new temporary
# file and prints its path. The caller does nothing more. The file is under
# fixture_dir, and bats removes it when the test ends.
write_transcript() {
  local content="$1"
  local file
  file="$(mktemp "$(fixture_dir)/transcript.XXXXXX.jsonl")"
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
# Prints one compact JSON transcript line for an assistant tool_use event.
# A test builds a synthetic transcript line by line with it.
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

# user_prompt_event [text]
#
# Prints one compact JSON transcript line for a genuine user prompt message
# with string content. It differs from a tool_result user message (array
# content) and from a skill or system injection (isMeta:true). This is the
# reliable turn boundary. A last-prompt marker is not, because the harness
# appends it out of chronological order relative to the tool calls of the
# turn.
user_prompt_event() {
  local text="${1:-a user prompt with several plain words in it}"
  jq -nc --arg text "$text" '{type:"user", message:{role:"user", content:$text}}'
}

# user_prompt_array_event [text]
#
# Prints one compact JSON transcript line for a genuine user prompt whose
# content is an array of text blocks, not a bare string. A prompt has this
# shape when it carries an attachment. It is a genuine prompt, so it must
# act as a boundary. That separates it from a tool_result array.
user_prompt_array_event() {
  local text="${1:-a genuine prompt delivered as an array of text blocks here}"
  jq -nc --arg text "$text" '{type:"user", message:{role:"user", content:[{type:"text", text:$text}]}}'
}

# tool_result_event
#
# Prints one compact JSON transcript line for a user-role tool_result
# message (array content). It is not a genuine prompt, so it must never act
# as a boundary.
tool_result_event() {
  printf '%s' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}'
}

# meta_injection_event [text]
#
# Prints one compact JSON transcript line for an isMeta:true user message.
# That is the record of the injected instructions of a skill. It is not a
# genuine prompt, so it must never act as a boundary.
meta_injection_event() {
  local text="${1:-injected skill instructions}"
  jq -nc --arg text "$text" '{type:"user", isMeta:true, message:{role:"user", content:[{type:"text", text:$text}]}}'
}

# task_notification_event [task-id]
#
# Prints one compact JSON transcript line for the harness message that
# announces the completion of an asynchronous subagent. The harness records
# it as a user-role message with string content and no isMeta flag. In
# structure, only its origin.kind separates it from a typed prompt. The
# harness always writes it AFTER the Agent tool_use that started the
# subagent. A boundary on it therefore hides the delegation that produced
# it. That defeated the check of enforce-prose-review.sh for every review
# delegated asynchronously. It is not a genuine prompt, so it must never act
# as a boundary.
task_notification_event() {
  local task_id="${1:-a96433995f69d06a7}"
  jq -nc --arg id "$task_id" \
    '{type:"user", promptSource:"system", origin:{kind:"task-notification"},
      message:{role:"user", content:("<task-notification>\n<task-id>" + $id + "</task-id>\n<status>completed</status>\n</task-notification>")}}'
}

# slash_command_marker_event [command]
#
# Prints one compact JSON transcript line for the marker that the harness
# writes when the user runs a built-in slash command (/model, /config). It
# carries no origin and no promptSource, so its content shape identifies it.
# It is not a genuine prompt, so it must never act as a boundary.
slash_command_marker_event() {
  local command="${1:-/model}"
  jq -nc --arg c "$command" \
    '{type:"user", message:{role:"user", content:("<command-name>" + $c + "</command-name>\n<command-args>opus</command-args>")}}'
}

# local_command_stdout_event
#
# Prints one compact JSON transcript line for the output that the harness
# records after a built-in slash command runs. It is not a genuine prompt.
local_command_stdout_event() {
  printf '%s' '{"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model to Opus 5</local-command-stdout>"}}'
}

# typed_prompt_event [text]
#
# A genuine typed prompt with the origin and promptSource fields that the
# current harness records. It must act as a boundary. That separates it
# from task_notification_event.
typed_prompt_event() {
  local text="${1:-a genuine typed prompt with several plain words}"
  jq -nc --arg text "$text" \
    '{type:"user", promptSource:"typed", origin:{kind:"human"},
      message:{role:"user", content:$text}}'
}

# bash_command_event <command>
#
# Prints one compact JSON transcript line for a Bash tool_use with the given
# command string. The command decides whether the turn changed a file, so it
# must reach the fixture unchanged.
bash_command_event() {
  jq -nc --arg cmd "$1" \
    '{type:"assistant", message:{content:[{type:"tool_use", name:"Bash", input:{command:$cmd}}]}}'
}

# shaped_event <name> [skill=<skill>] [subagent_type=<type>] [command=<cmd>]
#
# Prints one SHAPED event, the {name, skill, subagent_type, command} form
# that tool_use_events_since_line emits. code_was_edited and
# review_satisfied consume that form. It differs from tool_use_event, which
# prints the raw assistant transcript LINE that the shaped form comes from.
# A raw line in the place of a shaped event reports "nothing occurred" with
# no error.
shaped_event() {
  local name="$1"; shift
  local skill="" subagent_type="" command="" arg
  for arg in "$@"; do
    case "$arg" in
      skill=*) skill="${arg#skill=}" ;;
      subagent_type=*) subagent_type="${arg#subagent_type=}" ;;
      command=*) command="${arg#command=}" ;;
    esac
  done
  jq -nc --arg name "$name" --arg skill "$skill" \
         --arg subagent_type "$subagent_type" --arg command "$command" \
    '{name: $name,
      skill: (if $skill == "" then null else $skill end),
      subagent_type: (if $subagent_type == "" then null else $subagent_type end),
      command: (if $command == "" then null else $command end)}'
}

# user_prompt_multiblock_event <count> [text]
#
# A genuine user prompt whose content is an array of COUNT text blocks. A
# prompt has this shape when the harness delivers attachments or reminders
# with the typed words. It is ONE transcript object on ONE line, so the
# boundary classifier must give exactly one verdict for it. A classifier
# that emits one verdict per text block shifts every later line number, and
# the boundary then lands after the events it must cover.
user_prompt_multiblock_event() {
  local count="$1"
  local text="${2:-a genuine prompt split across several text blocks}"
  jq -nc --argjson count "$count" --arg text "$text" \
    '{type:"user", message:{role:"user",
      content:[range($count) | {type:"text", text:"\($text) \(.)"}]}}'
}

# tool_result_embedding_marker_event
#
# A tool_result that carries a transcript record inside its own structured
# result. The raw line holds the text {"type":"last-prompt"} unescaped, but
# the record itself is a tool_result. A read or a test of a transcript
# produces exactly this shape, and this repository does that all the time. A
# fallback that greps the raw file for the marker text matches here and
# moves the boundary FORWARD, past the events of the turn. That is fail-open
# for the code gate. It is neither a genuine prompt nor a genuine marker, so
# it is never a boundary.
tool_result_embedding_marker_event() {
  jq -nc '{type:"user",
           message:{role:"user", content:[{type:"tool_result", content:"read the fixture"}]},
           toolUseResult:{lines:[{type:"last-prompt"}]}}'
}
