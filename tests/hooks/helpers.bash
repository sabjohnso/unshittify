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

# fixture_dir - the directory every throwaway fixture is created under.
#
# BATS_TEST_TMPDIR is per-test and bats removes it; BATS_TMPDIR is shared
# across the run and nothing removes it, so the transcripts and stderr
# captures written there accumulated in /tmp one per assertion, run after
# run. The fallbacks keep the suite working on a bats too old to set the
# per-test variable.
fixture_dir() {
  printf '%s' "${BATS_TEST_TMPDIR:-${BATS_TMPDIR:-/tmp}}"
}

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
  HOOK_STDERR="$(mktemp "$(fixture_dir)/hook_stderr.XXXXXX")"
  run bash -c 'printf "%s" "$1" | "$2" 2>"$3"' _ "$stdin" "$script" "$HOOK_STDERR"
}

# write_transcript <heredoc-content>
#
# Writes the given content (one JSON object per line) to a fresh temp file
# and prints its path. Caller is responsible for nothing further: the file
# goes under fixture_dir, which bats removes when the test ends.
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

# user_prompt_event [text]
#
# Prints one compact-JSON transcript line for a genuine user prompt message
# (string content) — as distinct from a tool_result user message (array
# content) or a skill/system injection (isMeta:true). This is the reliable
# turn boundary, unlike a last-prompt marker, which the harness appends out
# of chronological order relative to the turn's own tool calls.
user_prompt_event() {
  local text="${1:-a user prompt with several plain words in it}"
  jq -nc --arg text "$text" '{type:"user", message:{role:"user", content:$text}}'
}

# user_prompt_array_event [text]
#
# Prints one compact-JSON transcript line for a genuine user prompt whose
# content is an array of text blocks (the shape a prompt takes when it carries
# an attachment) rather than a bare string. Still a genuine prompt: it must act
# as a boundary, which distinguishes it from a tool_result array.
user_prompt_array_event() {
  local text="${1:-a genuine prompt delivered as an array of text blocks here}"
  jq -nc --arg text "$text" '{type:"user", message:{role:"user", content:[{type:"text", text:$text}]}}'
}

# tool_result_event
#
# Prints one compact-JSON transcript line for a user-role tool_result message
# (array content). Not a genuine prompt, so it must never act as a boundary.
tool_result_event() {
  printf '%s' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}'
}

# meta_injection_event [text]
#
# Prints one compact-JSON transcript line for an isMeta:true user message —
# how a skill's injected instructions are recorded. Not a genuine prompt, so
# it must never act as a boundary.
meta_injection_event() {
  local text="${1:-injected skill instructions}"
  jq -nc --arg text "$text" '{type:"user", isMeta:true, message:{role:"user", content:[{type:"text", text:$text}]}}'
}

# task_notification_event [task-id]
#
# Prints one compact-JSON transcript line for the harness message that
# announces an asynchronous subagent's completion. The harness records it as
# a user-role message with string content and no isMeta flag, so it is
# structurally indistinguishable from a typed prompt except for its
# origin.kind - and it is always written AFTER the Agent tool_use that
# spawned the subagent. Treating it as a turn boundary therefore hides the
# very delegation that produced it, which is what defeated
# enforce-prose-review.sh's check for every asynchronously delegated review.
# Not a genuine prompt: it must never act as a boundary.
task_notification_event() {
  local task_id="${1:-a96433995f69d06a7}"
  jq -nc --arg id "$task_id" \
    '{type:"user", promptSource:"system", origin:{kind:"task-notification"},
      message:{role:"user", content:("<task-notification>\n<task-id>" + $id + "</task-id>\n<status>completed</status>\n</task-notification>")}}'
}

# slash_command_marker_event [command]
#
# Prints one compact-JSON transcript line for the marker the harness writes
# when the user runs a built-in slash command (/model, /config). It carries
# neither origin nor promptSource, so it is recognised by its content shape.
# Not a genuine prompt: it must never act as a boundary.
slash_command_marker_event() {
  local command="${1:-/model}"
  jq -nc --arg c "$command" \
    '{type:"user", message:{role:"user", content:("<command-name>" + $c + "</command-name>\n<command-args>opus</command-args>")}}'
}

# local_command_stdout_event
#
# Prints one compact-JSON transcript line for the output the harness records
# after a built-in slash command runs. Not a genuine prompt.
local_command_stdout_event() {
  printf '%s' '{"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model to Opus 5</local-command-stdout>"}}'
}

# typed_prompt_event [text]
#
# A genuine typed prompt carrying the origin/promptSource fields the current
# harness records. Must act as a boundary, which is what distinguishes it
# from task_notification_event.
typed_prompt_event() {
  local text="${1:-a genuine typed prompt with several plain words}"
  jq -nc --arg text "$text" \
    '{type:"user", promptSource:"typed", origin:{kind:"human"},
      message:{role:"user", content:$text}}'
}

# bash_command_event <command>
#
# Prints one compact-JSON transcript line for a Bash tool_use carrying the
# given command string. The command is what decides whether the turn changed
# a file, so it must survive into the fixture verbatim.
bash_command_event() {
  jq -nc --arg cmd "$1" \
    '{type:"assistant", message:{content:[{type:"tool_use", name:"Bash", input:{command:$cmd}}]}}'
}

# shaped_event <name> [skill=<skill>] [subagent_type=<type>] [command=<cmd>]
#
# Prints one SHAPED event, the {name, skill, subagent_type, command} form
# tool_use_events_since_line emits - which is what code_was_edited and
# review_satisfied consume. Distinct from tool_use_event, which prints the
# raw assistant transcript LINE those are derived from; passing a raw line
# where a shaped event is expected silently reports "nothing happened".
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
# A genuine user prompt whose content is an array of COUNT text blocks — the
# shape a prompt takes when the harness delivers attachments or reminders
# alongside the typed words. It is still ONE transcript object on ONE line, so
# the boundary classifier must produce exactly one verdict for it: a
# classifier that emits one verdict per text block desynchronises every line
# number after it, and the boundary then lands past the events it must cover.
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
# result, so the raw line contains the text {"type":"last-prompt"} unescaped
# while the record itself is a tool_result. Reading or testing a transcript
# produces exactly this shape, and this repository does that constantly. A
# fallback that greps the raw file for the marker text matches here and moves
# the boundary FORWARD, past the turn's own events, which is fail-open for the
# code gate. Neither a genuine prompt nor a genuine marker: never a boundary.
tool_result_embedding_marker_event() {
  jq -nc '{type:"user",
           message:{role:"user", content:[{type:"tool_result", content:"read the fixture"}]},
           toolUseResult:{lines:[{type:"last-prompt"}]}}'
}
