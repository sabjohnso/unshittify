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
# any, 0 otherwise. Every check runs on every file: a report that stops at
# the first violation turns one fix into one full re-run.
set -euo pipefail

# Tool names the harness recognises. A skill's allowed-tools or an agent's
# tools naming anything else is a silent failure at load time, not an error -
# which is how Task(...) survived in a skill after the harness renamed that
# tool to Agent. Update this list when the harness's tool set changes.
KNOWN_TOOLS=(
  Agent Artifact AskUserQuestion Bash Edit ExitPlanMode Glob Grep
  KillShell ListAgents LSP Monitor NotebookEdit Read ReportFindings
  ScheduleWakeup SendMessage Skill SlashCommand TodoWrite WebFetch
  WebSearch Workflow Write
)

# Models an agent may name. "Every agent names its model" is a house rule
# with a stated reason: an agent's cost and capability must not swing with
# whatever model the session happens to be using.
KNOWN_MODELS=(haiku sonnet opus)

# report <path> <line> <message>
#
# The single place a violation reaches stdout, so every check reports in the
# one format an editor can jump to. Checks only ever PRINT; main counts what
# it collected. Keeping the count out of the checks is what lets each one be
# called on its own and judged by its output alone.
report() {
  printf '%s:%s: %s\n' "$1" "$2" "$3"
}

# frontmatter_of <markdown-file>
#
# Prints the YAML frontmatter block (between the first two --- lines) with
# each line prefixed by its 1-based line number in the file, so a check can
# report where a violation actually is rather than naming the file alone.
frontmatter_of() {
  awk 'NR==1 && $0 != "---" { exit }
       /^---$/ { c++; if (c == 2) exit; next }
       c == 1 { printf "%d\t%s\n", NR, $0 }' "$1"
}

# load_frontmatter <numbered-frontmatter>
#
# Fills FM_LINE[key] and FM_RAW[key] from one already-read frontmatter block,
# in a single pass with no subprocess per key.
#
# The earlier shape called a `sed` per key, plus another per key whose line
# number was wanted - six process spawns for one agent file, and around 350
# across this repository, which was most of the validator's runtime. The
# validator runs after every edit under plugins/, so that was time paid on
# every iteration.
# -g, not a bare -A: when this script is SOURCED from inside a function (as
# the test suite's setup() does), a bare `declare -A` makes the arrays local
# to that function and they are gone by the time a check runs, leaving the
# name undeclared and every keyed assignment evaluating its subscript as
# arithmetic. -g declares them globally whatever the sourcing context.
declare -gA FM_LINE FM_RAW
load_frontmatter() {
  local number rest key value
  FM_LINE=(); FM_RAW=()
  while IFS=$'\t' read -r number rest; do
    [ -n "$number" ] || continue
    case $rest in
      [a-zA-Z-]*:*) ;;
      *) continue ;;
    esac
    key="${rest%%:*}"
    FM_LINE["$key"]="$number"
    value="${rest#*:}"
    value="${value#"${value%%[![:space:]]*}"}"   # trim leading blanks in-shell
    FM_RAW["$key"]="$value"
  done <<< "$1"
}

# frontmatter_value <key> - the unquoted value, or empty if the key is absent.
frontmatter_value() { unquote "${FM_RAW[$1]:-}"; }

# frontmatter_line <key> - the 1-based line the key sits on, or empty.
frontmatter_line() { printf '%s' "${FM_LINE[$1]:-}"; }

# unquote <scalar>
unquote() {
  local v="$1"
  v="${v#\"}"; v="${v%\"}"
  v="${v#\'}"; v="${v%\'}"
  printf '%s' "$v"
}

# --- check: a YAML comment silently truncating a scalar --------------------
#
# YAML ends an unquoted scalar at a space-then-#. A description mentioning a
# Racket #:keyword therefore reaches the harness cut in half, usually losing
# the "Use when..." clause that makes the skill triggerable at all. The file
# on disk still reads correctly, so nothing but a parser finds this.
check_yaml_truncation() {
  local file="$1" fm="$2" line number value
  while IFS=$'\t' read -r number value; do
    [ -n "$number" ] || continue
    case $value in
      [a-zA-Z-]*:*) ;;
      *) continue ;;
    esac
    line="${value#*:}"
    line="${line# }"
    case $line in
      \"*|\'*) continue ;;               # quoted: the # is safely inside it
    esac
    # In-shell glob rather than a grep per frontmatter line.
    if [[ "$line" == *[[:space:]]"#"* ]]; then
      report "$file" "$number" \
        "YAML comment truncates this value at the ' #': everything after it is lost. Quote the value."
    fi
  done <<< "$fm"
}

# --- check: a reference file nothing points at -----------------------------
#
# A SKILL.md's sibling files are loaded only if the skill's body names them.
# One that is never named is unreachable content.
check_reference_cited() {
  local skill_file="$1" dir sibling base
  dir="$(dirname "$skill_file")"
  for sibling in "$dir"/*.md; do
    base="$(basename "$sibling")"
    [ "$base" = "SKILL.md" ] && continue
    [ -f "$sibling" ] || continue
    if ! grep -qF "$base" "$skill_file"; then
      report "$skill_file" 1 \
        "sibling ${base} is never named in this SKILL.md, so nothing instructs the model to open it"
    fi
  done
}

# --- check: tool names ------------------------------------------------------
check_tool_names() {
  local file="$1" number="$2" list="$3" token known found
  list="$(unquote "$list")"
  while IFS= read -r token; do
    token="${token%%(*}"                       # Bash(git status:*) -> Bash
    token="${token//[[:space:]]/}"             # in-shell: no process per token
    [ -n "$token" ] || continue
    found=0
    for known in "${KNOWN_TOOLS[@]}"; do
      [ "$token" = "$known" ] && { found=1; break; }
    done
    [ "$found" -eq 1 ] || report "$file" "$number" \
      "unknown tool name '${token}' - the harness will not grant it"
    # printf adds the trailing newline deliberately: without it `read`
    # returns nonzero on the final token and the loop silently skips the
    # last tool in every list - which is exactly where a stale name sits.
  done < <(printf '%s\n' "$list" | tr ',' '\n')
}

# --- check: what every file with frontmatter owes ---------------------------
#
# check_skill and check_agent both had to read the frontmatter, handle its
# absence, and run the truncation check. Sharing that here means a new rule
# covering both file kinds is added in one place.
#
# Returns 1 when there is no frontmatter at all, so callers can stop rather
# than reporting a cascade of missing keys against a file that has none.
check_frontmatter_common() {
  local file="$1" fm
  fm="$(frontmatter_of "$file")"
  if [ -z "$fm" ]; then
    report "$file" 1 "no YAML frontmatter block"
    return 1
  fi
  load_frontmatter "$fm"
  check_yaml_truncation "$file" "$fm"
}

# --- check: one skill file --------------------------------------------------
check_skill() {
  local file="$1"
  check_frontmatter_common "$file" || return 0
  check_reference_cited "$file"

  [ -n "$(frontmatter_value description)" ] || report "$file" 1 \
    "no description: it is the only field always loaded into context, so without it the skill cannot trigger"

  if [ -n "$(frontmatter_line allowed-tools)" ]; then
    check_tool_names "$file" "$(frontmatter_line allowed-tools)" "$(frontmatter_value allowed-tools)"
  fi
}

# --- check: one agent file --------------------------------------------------
check_agent() {
  local file="$1" expected name model known found
  check_frontmatter_common "$file" || return 0

  expected="$(basename "$file" .md)"
  name="$(frontmatter_value name)"
  [ "$name" = "$expected" ] || report "$file" 1 \
    "name '${name}' does not match the filename '${expected}'"

  [ -n "$(frontmatter_value description)" ] || report "$file" 1 "no description"

  model="$(frontmatter_value model)"
  if [ -z "$model" ]; then
    report "$file" 1 \
      "no model: every agent here names one, so its cost and capability do not swing with the session's model"
  else
    found=0
    for known in "${KNOWN_MODELS[@]}"; do
      [ "$model" = "$known" ] && { found=1; break; }
    done
    [ "$found" -eq 1 ] || report "$file" 1 "unknown model '${model}'"
  fi

  if [ -n "$(frontmatter_line tools)" ]; then
    check_tool_names "$file" "$(frontmatter_line tools)" "$(frontmatter_value tools)"
  else
    report "$file" 1 "no tools list"
  fi
}

# --- check: the two manifests agree ----------------------------------------
#
# Each plugin's description is written twice: in its own plugin.json and
# again in the root marketplace.json. Nothing but this check keeps them
# together, and they have drifted before.
check_manifests() {
  local root="$1" marketplace name description manifest listed dir

  marketplace="${root}/.claude-plugin/marketplace.json"
  if [ ! -f "$marketplace" ]; then
    report "$marketplace" 1 "missing marketplace manifest"
    return
  fi
  if ! jq empty "$marketplace" 2>/dev/null; then
    report "$marketplace" 1 "invalid JSON"
    return
  fi

  # Name and description are pulled out together in ONE pass. Looking the
  # description up per plugin re-parsed the whole marketplace manifest once
  # per entry - an N+1 read of a file already in hand.
  local entries
  entries="$(jq -r '.plugins[] | "\(.name)\t\(.description)"' "$marketplace")"
  listed="$(printf '%s\n' "$entries" | cut -f1)"

  while IFS=$'\t' read -r name description; do
    [ -n "$name" ] || continue
    manifest="${root}/plugins/${name}/.claude-plugin/plugin.json"
    if [ ! -f "$manifest" ]; then
      report "$marketplace" 1 "plugin '${name}' is listed but ${manifest} does not exist"
      continue
    fi
    if ! jq empty "$manifest" 2>/dev/null; then
      report "$manifest" 1 "invalid JSON"
      continue
    fi
    if [ "$description" != "$(jq -r '.description' "$manifest")" ]; then
      report "$manifest" 1 \
        "description differs from the marketplace manifest's entry for '${name}'"
    fi
  done <<< "$entries"

  for dir in "${root}"/plugins/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    if ! grep -Fxq "$name" <<< "$listed"; then
      report "${root}/.claude-plugin/marketplace.json" 1 \
        "plugin directory '${name}' exists but is not listed in the marketplace manifest"
    fi
  done
}

# all_violations <marketplace-root>
#
# Every check, run over the whole tree, printing one line per violation and
# nothing else. Separating this from main is what keeps the checks free of
# any notion of counting or exit status.
all_violations() {
  local root="$1" file

  check_manifests "$root"

  while IFS= read -r file; do
    [ -n "$file" ] && check_skill "$file"
  done < <(find "${root}/plugins" -name SKILL.md -type f 2>/dev/null | sort)

  while IFS= read -r file; do
    [ -n "$file" ] && check_agent "$file"
  done < <(find "${root}/plugins" -path '*/agents/*.md' -type f 2>/dev/null | sort)
}

main() {
  local root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  local found

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
