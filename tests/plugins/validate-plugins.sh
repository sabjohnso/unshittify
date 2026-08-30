#!/usr/bin/env bash
# Structural validator over a plugin marketplace tree.
#
# Everything under plugins/ is a JSON manifest or a Markdown prompt that the
# Claude Code harness loads directly. There is no compiler and no runtime to
# catch a defect there, so a rule stated only in prose - in CLAUDE.md, or in
# the meta plugin's authoring skills - holds exactly as long as the next
# author remembers it. Four skill descriptions shipped silently truncated by
# a YAML comment before anything noticed.
#
# Usage: validate-plugins.sh [marketplace-root]   (default: the repo root)
#
# Prints one "path:line: message" per violation and exits 1 if there were
# any, 0 otherwise. Exit 2 means the validator could not run at all, which
# is not the same answer as "the tree is broken". Every check runs on every
# file: a report that stops at the first violation turns one fix into one
# full re-run.
set -euo pipefail
# Without this, errexit stops at the command substitution main runs every
# check inside, and a check that dies mid-tree looks like a clean tree.
shopt -s inherit_errexit

# Everything this validator matches on - YAML keys, tool names, model names,
# filenames, JSON field names - is ASCII, and in a UTF-8 locale bash decodes
# every pattern match character by character. Measured over this repository,
# the C locale alone took the run from 0.65s to 0.50s. Not exported: the
# child processes keep whatever locale the caller had.
LC_ALL=C

# Tool names the harness recognises. A skill's allowed-tools or an agent's
# tools naming anything else is a silent failure at load time, not an error -
# which is how Task(...) survived in a skill after the harness renamed that
# tool to Agent. Update this list when the harness's tool set changes.
# MCP tools are matched by their mcp__<server>__<tool> shape instead: their
# names come from whatever servers a user has connected, so no fixed list
# can hold them.
KNOWN_TOOLS=(
  Agent Artifact AskUserQuestion Bash BashOutput CronCreate CronDelete
  CronList DesignSync Edit EnterWorktree ExitPlanMode ExitWorktree Glob
  Grep KillShell ListAgents ListMcpResources LSP Monitor NotebookEdit
  PushNotification Read ReadMcpResource RemoteTrigger ReportFindings
  ScheduleWakeup SendFeedback SendMessage SendUserFile Skill SlashCommand
  TaskStop TodoWrite ToolSearch WebFetch WebSearch Workflow Write
)

# Models an agent may name. "Every agent names its model" is a house rule
# with a stated reason: an agent's cost and capability must not swing with
# whatever model the session happens to be using.
KNOWN_MODELS=(haiku sonnet opus)

# The frontmatter keys each file kind may carry, per the meta plugin's
# write-skill and write-agent authoring skills. Anything else is ignored by
# the harness in silence, so a skill that writes `tools:` where the harness
# reads `allowed-tools:` gets no tools and no complaint. Checking against a
# closed list catches that whole misspelling class at once.
KNOWN_SKILL_KEYS=(allowed-tools argument-hint description disable-model-invocation)
KNOWN_AGENT_KEYS=(description model name tools)

# report <path> <line> <message>
#
# The single place a violation reaches stdout, so every check reports in the
# one format an editor can jump to. Checks only ever PRINT; main counts what
# it collected. Keeping the count out of the checks is what lets each one be
# called on its own and judged by its output alone.
report() {
  printf '%s:%s: %s\n' "$1" "$2" "$3"
}

# trim_blanks <text>
#
# Sets TRIMMED to <text> without leading or trailing whitespace. It assigns
# rather than prints because it runs once per frontmatter line: a command
# substitution here is a process fork per line of every file in the tree.
TRIMMED=''
trim_blanks() {
  TRIMMED="${1#"${1%%[![:space:]]*}"}"
  TRIMMED="${TRIMMED%"${TRIMMED##*[![:space:]]}"}"
}

# unquote_into <scalar>
#
# Sets UNQUOTED to <scalar> without its surrounding quotes. It assigns rather
# than prints because it runs once per tool list and twice per agent: at a
# measured 3ms a fork, a command substitution here was a third of the run.
UNQUOTED=''
unquote_into() {
  UNQUOTED="${1#\"}"; UNQUOTED="${UNQUOTED%\"}"
  UNQUOTED="${UNQUOTED#\'}"; UNQUOTED="${UNQUOTED%\'}"
}

# unquote <scalar> - the same, printed.
unquote() {
  unquote_into "$1"
  printf '%s' "$UNQUOTED"
}

# --- the one frontmatter parser ---------------------------------------------
#
# read_markdown <markdown-file>
#
# Reads a file once and publishes everything the checks need from it:
#
#   FM_STATUS      ok | none | unterminated
#   FM_KEYS        the frontmatter keys, in the order they appear
#   FM_RAW[key]    the value as written, quotes intact, blanks trimmed
#   FM_LINE[key]   the 1-based line the key sits on
#   FM_DUPLICATES  "line<TAB>key" for each key written more than once
#   FM_BODY        everything after the closing --- delimiter
#
# Every check consumes this and none re-parses a raw line of its own. Two
# parsers over one input is how the truncation check came to strip a single
# leading space where the loader stripped all of them, reporting a correctly
# quoted description as truncated whenever it was indented by two.
declare -gA FM_LINE FM_RAW
declare -ga FM_KEYS FM_DUPLICATES
FM_STATUS=''
FM_BODY=''
read_markdown() {
  local file="$1" line key value item number=1 pending_key=''
  local -a lines body_lines=()

  FM_LINE=(); FM_RAW=(); FM_KEYS=(); FM_DUPLICATES=()
  FM_STATUS='none'; FM_BODY=''

  mapfile -t lines < "$file"
  [ "${#lines[@]}" -gt 0 ] || return 0

  # A byte-order mark or a CRLF ending is invisible in an editor but hides
  # the delimiter from a naive comparison, sending the author to look for a
  # --- that is plainly there.
  lines[0]="${lines[0]#$'\xef\xbb\xbf'}"
  [ "${lines[0]%$'\r'}" = "---" ] || return 0
  FM_STATUS='unterminated'

  for line in "${lines[@]:1}"; do
    number=$((number + 1))          # lines[1] is file line 2
    line="${line%$'\r'}"

    if [ "$FM_STATUS" = "ok" ]; then
      body_lines+=("$line")
      continue
    fi
    if [ "$line" = "---" ]; then
      FM_STATUS='ok'
      continue
    fi

    # A block-sequence item: `tools:` with the entries on following indented
    # lines is the same list as `tools: Read, Grep`, and must reach the tool
    # check as one. It did not, and an unknown tool spelled this way was
    # checked against an empty string and passed.
    if [ -n "$pending_key" ] && [[ $line =~ ^[[:space:]]+-[[:space:]]+(.*)$ ]]; then
      trim_blanks "${BASH_REMATCH[1]}"
      item="$TRIMMED"
      if [ -n "${FM_RAW[$pending_key]}" ]; then
        FM_RAW["$pending_key"]+=", ${item}"
      else
        FM_RAW["$pending_key"]="$item"
      fi
      continue
    fi

    if [[ $line =~ ^([A-Za-z][A-Za-z0-9_-]*):(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      trim_blanks "${BASH_REMATCH[2]}"
      value="$TRIMMED"
      if [ -n "${FM_LINE[$key]:-}" ]; then
        FM_DUPLICATES+=("${number}"$'\t'"${key}")
      else
        FM_KEYS+=("$key")
      fi
      FM_LINE["$key"]="$number"
      FM_RAW["$key"]="$value"
      if [ -z "$value" ]; then pending_key="$key"; else pending_key=''; fi
      continue
    fi

    pending_key=''
  done

  if [ "$FM_STATUS" = "ok" ] && [ "${#body_lines[@]}" -gt 0 ]; then
    printf -v FM_BODY '%s\n' "${body_lines[@]}"
  fi
}

# --- check: a YAML comment silently truncating a scalar --------------------
#
# YAML ends an unquoted scalar at a space-then-#. A description mentioning a
# Racket #:keyword therefore reaches the harness cut in half, usually losing
# the "Use when..." clause that makes the skill triggerable at all. The file
# on disk still reads correctly, so nothing but a parser finds this.
check_yaml_truncation() {
  local file="$1" key raw
  for key in "${FM_KEYS[@]}"; do
    raw="${FM_RAW[$key]}"
    case $raw in
      \"*|\'*) continue ;;               # quoted: the # is safely inside it
    esac
    if [[ $raw == *[[:space:]]"#"* ]]; then
      report "$file" "${FM_LINE[$key]}" \
        "YAML comment truncates this value at the ' #': everything after it is lost. Quote the value."
    fi
  done
}

# --- check: keys the harness does not read ----------------------------------
#
# check_unknown_keys <file> <known-key>...
check_unknown_keys() {
  local file="$1"; shift
  local key known found
  for key in "${FM_KEYS[@]}"; do
    found=0
    for known in "$@"; do
      [ "$key" = "$known" ] && { found=1; break; }
    done
    [ "$found" -eq 1 ] || report "$file" "${FM_LINE[$key]}" \
      "unknown frontmatter key '${key}' - the harness reads none of it"
  done
}

# --- check: a key written twice ---------------------------------------------
#
# A real YAML parser rejects a duplicate key; this one took the last and said
# nothing, so `tools: Taks` followed by `tools: Read` validated clean while
# the harness saw whichever its own parser preferred.
check_duplicate_keys() {
  local file="$1" entry number key
  for entry in "${FM_DUPLICATES[@]}"; do
    number="${entry%%$'\t'*}"
    key="${entry#*$'\t'}"
    report "$file" "$number" "duplicate frontmatter key '${key}'"
  done
}

# --- check: skill directory contents and citations --------------------------
#
# check_reference_cited <skill-file> <marketplace-root> <body>
#
# A SKILL.md's sibling files are loaded only if the skill's body names them,
# and a name the body gives that resolves to nothing strands the model just
# as an unnamed file does. Both directions are checked, plus CLAUDE.md's rule
# that a skill is one file: no references/, scripts/ or assets/ subdirectory.
check_reference_cited() {
  local skill_file="$1" root="$2" body="$3"
  local dir="${skill_file%/*}" entry base

  for entry in "$dir"/*; do
    [ -e "$entry" ] || continue
    base="${entry##*/}"
    if [ -d "$entry" ]; then
      report "$skill_file" 1 \
        "skill directory holds a subdirectory ${base}/: a skill in this repository is a single SKILL.md plus named siblings"
      continue
    fi
    [ "$base" = "SKILL.md" ] && continue
    body_names "$body" "$base" || report "$skill_file" 1 \
      "sibling ${base} is never named in this SKILL.md, so nothing instructs the model to open it"
  done

  # Only Markdown citations are resolved. A body legitimately names files
  # belonging to whatever it teaches about - info.rkt, settings.json - and
  # those are not this validator's to find.
  md_citations "$body"
  for base in "${CITED_ORDER[@]}"; do
    [ -e "${dir}/${base}" ] && continue
    [ -e "${root}/${base}" ] && continue
    report "$skill_file" 1 \
      "this SKILL.md names ${base}, but no such file sits beside it or at the marketplace root"
  done
}

# body_names <body> <filename>
#
# True when the body names <filename> as a whole word. A plain substring
# search is not enough in either direction: a body naming other-reference.md
# would satisfy the requirement for reference.md, and a search over the whole
# file would count a mention in the frontmatter, which instructs the model to
# open nothing. The body handed in here is already frontmatter-free.
body_names() {
  local rest="$1" name="$2" before
  while [[ $rest == *"$name"* ]]; do
    before="${rest%%"$name"*}"
    # Cut by index, not by ${rest#*"$name"}: stripping a prefix through a
    # leading * costs a rescan per candidate length, which is quadratic in
    # the distance to the match and measurably dominated this whole file.
    rest="${rest:${#before}+${#name}}"
    case ${before: -1} in [A-Za-z0-9._-]) continue ;; esac
    case ${rest:0:1} in [A-Za-z0-9._-]) continue ;; esac
    return 0
  done
  return 1
}

# md_citations <body>
#
# Fills CITED_ORDER with each distinct Markdown filename the body names, in
# the order they appear so the report is stable. It steps over the ".md"
# occurrences rather than over the words: a skill body runs to a couple of
# thousand words, there are dozens of them, and a per-word loop over the tree
# cost more than every external process the validator ever spawned.
declare -gA CITED
declare -ga CITED_ORDER
md_citations() {
  local rest="$1" head name
  CITED=(); CITED_ORDER=()
  while [[ $rest == *.md* ]]; do
    head="${rest%%.md*}"
    rest="${rest:${#head}+3}"
    case ${rest:0:1} in
      [A-Za-z0-9_-]) continue ;;                  # .mdx, .mdown: a different name
      .) case ${rest:1:1} in [A-Za-z0-9]) continue ;; esac ;;
    esac
    name="${head##*[!A-Za-z0-9._-]}.md"
    [ "$name" != ".md" ] || continue
    if [ -z "${CITED[$name]:-}" ]; then
      CITED["$name"]=1
      CITED_ORDER+=("$name")
    fi
  done
}

# --- check: tool names ------------------------------------------------------
check_tool_names() {
  local file="$1" number="$2" token known found
  local -a tokens=()
  unquote_into "$3"
  IFS=',' read -ra tokens <<< "$UNQUOTED"
  for token in "${tokens[@]}"; do
    token="${token%%(*}"                       # Bash(git status:*) -> Bash
    token="${token//[[:space:]]/}"             # in-shell: no process per token
    [ -n "$token" ] || continue
    case $token in mcp__*) continue ;; esac
    found=0
    for known in "${KNOWN_TOOLS[@]}"; do
      [ "$token" = "$known" ] && { found=1; break; }
    done
    [ "$found" -eq 1 ] || report "$file" "$number" \
      "unknown tool name '${token}' - the harness will not grant it"
  done
}

# --- check: an agent's tool list takes bare names ---------------------------
#
# check_tool_names above strips the argument off each token before matching
# it, which is what lets a skill's allowed-tools scope one. An agent's list
# takes bare names in this repository and narrows the use in the agent's body
# instead, so a scoped token there validated clean and the rule lived only in
# the meta plugin's prose. Reading the token before that strip is what makes
# it enforceable.
check_bare_tool_names() {
  local file="$1" number="$2" token
  local -a tokens=()
  unquote_into "$3"
  IFS=',' read -ra tokens <<< "$UNQUOTED"
  for token in "${tokens[@]}"; do
    trim_blanks "$token"; token="$TRIMMED"
    case $token in
      *'('*) report "$file" "$number" \
        "tool '${token}' is argument-scoped - an agent's tools list takes bare names; say what it may run in the body instead" ;;
    esac
  done
}

# --- check: what every file with frontmatter owes ---------------------------
#
# check_skill and check_agent both had to read the frontmatter, handle its
# absence, and run the truncation check. Sharing that here means a new rule
# covering both file kinds is added in one place.
#
# Returns 1 when there is no usable frontmatter, so callers can stop rather
# than reporting a cascade of missing keys against a file that has none.
check_frontmatter_common() {
  local file="$1"
  read_markdown "$file"
  case $FM_STATUS in
    none)
      report "$file" 1 "no YAML frontmatter block"
      return 1
      ;;
    unterminated)
      report "$file" 1 \
        "the YAML frontmatter block opens but never closes: no later line is '---', so the whole file reads as frontmatter"
      return 1
      ;;
  esac
  check_duplicate_keys "$file"
  check_yaml_truncation "$file"
}

# --- check: one skill file --------------------------------------------------
check_skill() {
  local file="$1" root="$2"
  check_frontmatter_common "$file" || return 0
  check_unknown_keys "$file" "${KNOWN_SKILL_KEYS[@]}"
  check_reference_cited "$file" "$root" "$FM_BODY"

  [ -n "${FM_RAW[description]:-}" ] || report "$file" "${FM_LINE[description]:-1}" \
    "no description: it is the only field always loaded into context, so without it the skill cannot trigger"

  if [ -n "${FM_RAW[allowed-tools]:-}" ]; then
    check_tool_names "$file" "${FM_LINE[allowed-tools]}" "${FM_RAW[allowed-tools]}"
  fi
}

# --- check: one agent file --------------------------------------------------
check_agent() {
  local file="$1" expected name model known found
  check_frontmatter_common "$file" || return 0
  check_unknown_keys "$file" "${KNOWN_AGENT_KEYS[@]}"

  expected="${file##*/}"
  expected="${expected%.md}"
  unquote_into "${FM_RAW[name]:-}"; name="$UNQUOTED"
  if [ -z "${FM_LINE[name]:-}" ]; then
    report "$file" 1 "no name: an agent names itself, and the name must match the filename '${expected}'"
  elif [ "$name" != "$expected" ]; then
    report "$file" "${FM_LINE[name]}" \
      "name '${name}' does not match the filename '${expected}'"
  fi

  [ -n "${FM_RAW[description]:-}" ] || report "$file" "${FM_LINE[description]:-1}" "no description"

  unquote_into "${FM_RAW[model]:-}"; model="$UNQUOTED"
  if [ -z "$model" ]; then
    report "$file" "${FM_LINE[model]:-1}" \
      "no model: every agent here names one, so its cost and capability do not swing with the session's model"
  else
    found=0
    for known in "${KNOWN_MODELS[@]}"; do
      [ "$model" = "$known" ] && { found=1; break; }
    done
    [ "$found" -eq 1 ] || report "$file" "${FM_LINE[model]}" "unknown model '${model}'"
  fi

  if [ -n "${FM_RAW[tools]:-}" ]; then
    check_tool_names "$file" "${FM_LINE[tools]}" "${FM_RAW[tools]}"
    check_bare_tool_names "$file" "${FM_LINE[tools]}" "${FM_RAW[tools]}"
  else
    report "$file" "${FM_LINE[tools]:-1}" "no tools list"
  fi
}

# --- the plugin manifests, read in one pass ---------------------------------
#
# read_plugin_manifests <marketplace-root>
#
# Fills PLUGIN_NAME[path], PLUGIN_DESCRIPTION[path] and PLUGIN_INVALID[path].
# jq takes every manifest at once and keys the results by input_filename, so
# the common case costs one process rather than the two per plugin that
# validating and then querying each file separately did.
declare -gA PLUGIN_NAME PLUGIN_DESCRIPTION PLUGIN_INVALID
read_plugin_manifests() {
  local root="$1" file path name description rows
  local -a files=() valid=()

  PLUGIN_NAME=(); PLUGIN_DESCRIPTION=(); PLUGIN_INVALID=()

  for file in "${root}"/plugins/*/.claude-plugin/plugin.json; do
    [ -f "$file" ] && files+=("$file")
  done
  [ "${#files[@]}" -gt 0 ] || return 0

  if ! rows="$(manifest_rows "${files[@]}")"; then
    # One malformed manifest fails the whole batch, and the batch cannot say
    # which. Only then is a process per file worth paying for.
    for file in "${files[@]}"; do
      if jq empty "$file" >/dev/null 2>&1; then
        valid+=("$file")
      else
        PLUGIN_INVALID["$file"]=1
      fi
    done
    [ "${#valid[@]}" -gt 0 ] || return 0
    rows="$(manifest_rows "${valid[@]}")" || rows=''
  fi

  while IFS=$'\t' read -r path name description; do
    [ -n "$path" ] || continue
    PLUGIN_NAME["$path"]="$name"
    PLUGIN_DESCRIPTION["$path"]="$description"
  done <<< "$rows"
}

# manifest_rows <plugin.json>... - one "path<TAB>name<TAB>description" per file
manifest_rows() {
  jq -r '[input_filename, (.name // ""), (.description // "")] | @tsv' "$@" 2>/dev/null
}

# --- check: the two manifests agree ----------------------------------------
#
# Each plugin's description is written twice: in its own plugin.json and
# again in the root marketplace.json. Nothing but this check keeps them
# together, and they have drifted before.
check_manifests() {
  local root="$1" marketplace entries failure kind
  local name source description manifest resolved dir base
  local -A listed=()

  marketplace="${root}/.claude-plugin/marketplace.json"
  if [ ! -f "$marketplace" ]; then
    report "$marketplace" 1 "missing marketplace manifest"
    return 0
  fi
  # Each jq call is guarded and its own error becomes the message. Left
  # unguarded, a manifest with no .plugins array leaked "Cannot iterate over
  # null" to stderr and then compared nothing, in silence.
  if ! failure="$(jq empty "$marketplace" 2>&1)"; then
    report "$marketplace" 1 "invalid JSON: ${failure%%$'\n'*}"
    return 0
  fi
  kind="$(jq -r '.plugins | type' "$marketplace" 2>/dev/null || printf 'unreadable')"
  if [ "$kind" != "array" ]; then
    report "$marketplace" 1 \
      "no .plugins array to compare against (its .plugins is ${kind})"
    return 0
  fi
  if ! entries="$(jq -r '.plugins[] | [.name, .source, .description] | @tsv' \
                    "$marketplace" 2>&1)"; then
    report "$marketplace" 1 \
      "cannot read the .plugins entries: ${entries%%$'\n'*}"
    return 0
  fi

  read_plugin_manifests "$root"

  while IFS=$'\t' read -r name source description; do
    [ -n "$name" ] || continue
    if [ -n "${listed[$name]:-}" ]; then
      report "$marketplace" 1 "plugin '${name}' is listed twice in the marketplace manifest"
      continue
    fi
    listed["$name"]=1

    if [ -n "$source" ]; then
      case $source in
        /*) resolved="$source" ;;
        *)  resolved="${root}/${source#./}" ;;
      esac
      [ -d "$resolved" ] || report "$marketplace" 1 \
        "plugin '${name}' names source '${source}', which is not a directory here"
    fi

    manifest="${root}/plugins/${name}/.claude-plugin/plugin.json"
    if [ ! -f "$manifest" ]; then
      report "$marketplace" 1 "plugin '${name}' is listed but ${manifest} does not exist"
      continue
    fi
    if [ -n "${PLUGIN_INVALID[$manifest]:-}" ]; then
      report "$manifest" 1 "invalid JSON"
      continue
    fi
    if [ "$description" != "${PLUGIN_DESCRIPTION[$manifest]:-}" ]; then
      report "$manifest" 1 \
        "description differs from the marketplace manifest's entry for '${name}'"
    fi
  done <<< "$entries"

  for dir in "${root}"/plugins/*/; do
    [ -d "$dir" ] || continue
    base="${dir%/}"
    base="${base##*/}"
    # An associative array built once, rather than a grep down the whole
    # list per directory: that was a process per plugin and quadratic in
    # the plugin count.
    [ -n "${listed[$base]:-}" ] || report "$marketplace" 1 \
      "plugin directory '${base}' exists but is not listed in the marketplace manifest"

    manifest="${dir}.claude-plugin/plugin.json"
    [ -f "$manifest" ] || continue
    [ -z "${PLUGIN_INVALID[$manifest]:-}" ] || continue
    [ "${PLUGIN_NAME[$manifest]:-}" = "$base" ] || report "$manifest" 1 \
      "name '${PLUGIN_NAME[$manifest]:-}' does not match its directory '${base}'"
  done
}

# all_violations <marketplace-root>
#
# Every check, run over the whole tree, printing one line per violation and
# nothing else. Separating this from main is what keeps the checks free of
# any notion of counting or exit status.
all_violations() {
  local root="$1" file examined=0

  # A mistyped root once validated an empty set and printed "plugins:
  # clean.", so a wrong path in CI read exactly like a passing run.
  if [ ! -d "${root}/plugins" ]; then
    report "$root" 1 "no plugins/ directory here - is this the marketplace root?"
    return 0
  fi

  check_manifests "$root"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    check_skill "$file" "$root"
    examined=$((examined + 1))
  done < <(find "${root}/plugins" -name SKILL.md -type f | sort)

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    check_agent "$file"
    examined=$((examined + 1))
  done < <(find "${root}/plugins" -path '*/agents/*.md' -type f | sort)

  if [ "$examined" -eq 0 ]; then
    report "${root}/plugins" 1 \
      "no skills and no agents found under it - is this the marketplace root?"
  fi
}

main() {
  local root script_dir found

  # A missing jq is an environment failure, not a plugin defect. Reported as
  # one it read as "invalid JSON" against a perfectly valid manifest.
  if ! command -v jq >/dev/null 2>&1; then
    printf 'validate-plugins.sh: jq is required and is not on PATH.\n' >&2
    return 2
  fi

  # Declared apart from the assignment on purpose: `local root="$(cd ...)"`
  # takes local's exit status, so a failed cd left root empty and the run
  # went on to validate /plugins.
  root="${1:-}"
  if [ -z "$root" ]; then
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    root="$(cd "${script_dir}/../.." && pwd)"
  fi

  found="$(all_violations "$root")"

  if [ -n "$found" ]; then
    printf '%s\n' "$found"
    printf '\n%d violation(s).\n' "$(printf '%s\n' "$found" | wc -l)"
    return 1
  fi
  printf 'plugins: clean.\n'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
