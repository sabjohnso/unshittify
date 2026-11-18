#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). It gates git commit and git push. The hook
# denies a git commit until the communication:prose-reviewer agent ran
# this turn. That run is the required review step of the commit-message
# skill for the drafted message. A commit that passes that gate, and every
# push, still asks for confirmation. The standing instruction says that a
# commit or a push needs an explicit instruction in the current turn. When
# the hook cannot judge the transcript (no path, no file, or no turn
# boundary), the review gate degrades to the plain ask. It does not block
# the commit.
set -euo pipefail

# The agent that satisfies the commit gate. Keep this value equal to
# REVIEW_AGENT in enforce-prose-review.sh. The two hooks apply the same
# prose-review policy at two moments, the time of the commit and the end of
# the turn. A rename must change both.
REVIEW_AGENT="communication:prose-reviewer"

# The directory of this script. The expansion starts no process. A path with
# no slash is a file in the current directory.
if [[ "${BASH_SOURCE[0]}" == */* ]]; then HOOK_DIR="${BASH_SOURCE[0]%/*}"; else HOOK_DIR=.; fi

# shellcheck source=lib/transcript.sh disable=SC1091
source "${HOOK_DIR}/lib/transcript.sh"
# shellcheck source=lib/shell-command.sh disable=SC1091
source "${HOOK_DIR}/lib/shell-command.sh"

# is_git_subcommand <masked-command-string> <subcommand>
#
# Succeeds when the text runs git with <subcommand> as its subcommand. The
# argument is masked text (main calls mask_nonexecuting once), so this is a
# pure matcher over what the shell will execute.
#
# The subcommand is the FIRST non-option word after a git command word, not
# any occurrence of the word. "git help commit", "git log --grep commit", and
# "git rev-parse --verify commit" are read-only commands whose ARGUMENT is
# the watched word. A gate on one of them denies a commit that does not
# exist and tells the model to review a message that it never wrote. The
# matcher skips the global options that git accepts before its subcommand.
# It also skips the value of each option that takes a separate token (-C,
# -c, --git-dir, and the rest of GIT_GLOBAL_OPTS_WITH_VALUE).
#
# The match is on whole words. A ref such as fix-commit-message or a remote
# named commit-fixes is not the commit subcommand. A command such as "legit"
# is not git, but a path-prefixed /usr/bin/git is.
#
# QUOTES ARE THE REASON THIS IS A TOKENIZER AND NOT A PATTERN. The pattern
# that this replaced demanded whitespace before the command word and around
# the subcommand. A quote character near either one ran with no gate: git
# "commit", git 'commit', "git" commit, and the whole of bash -c "...". The
# text was intact and nothing was masked. The matcher was blind to a quote.
# The same pattern read a ";" inside a quoted path (git -C "/a;b" commit) as
# a command separator and stopped there. The removal of quotes must occur
# before the comparison of words. Only a scanner that tracks the quote
# state can tell a separator from a character inside a string.
#
# There are two passes, because a quoted string is BOTH one word and, when
# an interpreter receives it, a command line of its own:
#
#   grouping   Quotes group. This is the reading of the shell: the command
#              git -C "/a;b" commit has four words and no separator. This
#              pass always runs.
#   splitting  Quotes are whitespace, so the words inside a quoted string are
#              words. This pass reaches inside bash -c "...", where the
#              reading of the shell is one word and git runs anyway. It runs
#              only when the text names an interpreter (FEED_PATTERN). A
#              quoted string is a command line only when something executes
#              it. grep -rn "..." and echo "..." only MENTION the words, and
#              a gate on a mention is the exact failure that the masker
#              above prevents. Non-shell interpreters keep the hole that the
#              masker states: perl -e '...' can run git too.
#
# A match in EITHER pass gates, so the splitting pass can only add matches.
# That is the same fail-closed direction as the masker. A false positive
# costs one confirmation prompt. A false negative costs the guarantee.
#
# A line break separates commands. A backslash at the end of a line joins
# the next line, as in the shell, so a continuation between the command word
# and its subcommand does not escape the gate. A quoted string spans lines,
# and the scanner carries the quote state across them to match.
#
# The matcher reads the whole command before it gives the verdict. Thus no
# early exit can leave a writer upstream killed by SIGPIPE (141), with
# `set -o pipefail` as the cause of a failed pipeline. That is how a large
# command escaped the gate when this matcher was a `grep -q` at the end of a
# pipe.
#
# The program is the tokenizer, then SHELL_NO_TRACKER_AWK, then the matcher.
# The matcher reads only TOK, KIND, and NT. Thus it loads the empty tracker,
# and a change of a subshell rule or of a wait rule does not change it.
GIT_GLOBAL_OPTS_WITH_VALUE="-C -c --git-dir --work-tree --namespace --exec-path --super-prefix --config-env"

is_git_subcommand() {
  awk -v want="$2" -v valued="$GIT_GLOBAL_OPTS_WITH_VALUE" -v FEED="$FEED_PATTERN" "${SHELL_TOKENIZER_AWK}${SHELL_NO_TRACKER_AWK}"'
    function is_git(t) { return t == "git" || t ~ /\/git$/ }

    # The subcommand that the call with command word TOK[i] runs, or "" when
    # the command ends before one. The scan skips options, and it skips the
    # separate-token value of an option that takes one. It never skips
    # across a separator, because "git -C ; commit" runs no subcommand.
    function subcommand_after(i,   j, alias_of, name, body) {
      for (j = i + 1; j <= NT && KIND[j] == "word"; j++) {
        if (substr(TOK[j], 1, 1) != "-") return (TOK[j] in alias_expands_to) ? alias_expands_to[TOK[j]] : TOK[j]
        if (TOK[j] in takes_value) {
          j++
          if (j > NT || KIND[j] == "sep") return ""
          # "git -c alias.ci=commit ci" defines the alias and runs it in one
          # call. The subcommand word is "ci", and the name of what it runs
          # is only inside a value that this loop would otherwise skip
          # unread. The scan records the expansion, so the word resolves to
          # it.
          if (TOK[j] ~ /^alias\.[^=]+=/) {
            alias_of = substr(TOK[j], 7)
            name = substr(alias_of, 1, index(alias_of, "=") - 1)
            body = substr(alias_of, index(alias_of, "=") + 1)
            sub(/^[[:space:]!]+/, "", body)
            if (match(body, /[^[:space:]]+/)) alias_expands_to[name] = substr(body, RSTART, RLENGTH)
          }
        }
      }
      return ""
    }

    function matches(split_quotes,   i) {
      reset_tokens(); split("", alias_expands_to)
      for (i = 1; i <= n; i++) tokenize(line[i], split_quotes)
      for (i = 1; i <= NT; i++)
        if (KIND[i] == "word" && is_git(TOK[i]) && subcommand_after(i) == want) return 1
      return 0
    }

    BEGIN {
      split(valued, opts, " ")
      for (k in opts) takes_value[opts[k]] = 1
    }
    { line[++n] = $0; if ($0 ~ FEED) feeds_present = 1 }
    END { exit (matches(0) || (feeds_present && matches(1))) ? 0 : 1 }
  ' <<<"$1"
}

ask_confirmation() {
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: "A git commit or a git push needs an explicit instruction in this turn. Confirm to continue."
    }
  }'
}

deny_unreviewed_commit() {
  jq -n --arg agent "$REVIEW_AGENT" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "The \($agent) agent did not review this commit message. Delegate the drafted message to that agent, apply the confirmed fixes, and then try the commit again."
    }
  }'
}

# commit_prose_reviewed <transcript-path>
#
# Succeeds when the review agent ran after the start of the turn. It also
# succeeds when the hook cannot judge the transcript (a path it cannot judge,
# or no turn boundary). The gate denies only when the events of the turn are
# readable and hold no review. The boundary is computed once and used again,
# so the transcript is scanned a single time.
commit_prose_reviewed() {
  local transcript="$1"
  local start_line
  transcript_judgeable "$transcript" || return 0
  start_line=$(find_turn_start_line "$transcript") || return 0
  agent_invoked_since_line "$transcript" "$start_line" "$REVIEW_AGENT"
}

main() {
  local input cmd transcript
  input=$(cat)

  # A payload that the hook cannot read (nothing at all, or text that jq
  # rejects) says nothing about the command that is about to run. To a
  # PreToolUse hook, every exit status but 2 is a NON-BLOCKING error. When
  # the assignment fails under `set -e`, the tool runs with no gate at all.
  # The ask is the fail-closed answer. A payload that the harness must never
  # send costs one confirmation prompt. An object with no command is a
  # different case. jq reads it, reports no command, and there is nothing to
  # gate.
  if [ -z "$input" ]; then
    ask_confirmation
    return 0
  fi

  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty') || {
    ask_confirmation
    return 0
  }

  # The mask only deletes characters, so a command with no "git" in it
  # cannot get one. The skip of the mask and the match here keeps the awk
  # program off the latency path of every Bash call without git. One mask,
  # and not one inside each is_git_subcommand call, halves the rest.
  #
  # The prefilter must not overrule the matcher. is_git_subcommand is a
  # quote-aware tokenizer because a quote can sit anywhere, also INSIDE the
  # command word. The shell reads g"it" and g'it' as git and runs them. The
  # tokenizer reads them as git too. But neither string holds the substring
  # "git", so a raw-substring prefilter answered "no git here" and returned
  # before the matcher ran. The removal of the quote and backslash
  # characters first makes the two agree. It can only ADD candidates, the
  # same fail-closed direction as the rest of this file. The cost is a
  # matcher run on the rare command whose quoted words join into "git".
  case ${cmd//[\'\"\\]/} in
    *git*) ;;
    *) return 0 ;;
  esac
  cmd=$(mask_nonexecuting "$cmd")

  if is_git_subcommand "$cmd" commit; then
    # An unreadable transcript path is the degraded case that
    # commit_prose_reviewed handles with an ask. A second jq failure lands
    # there too. It does not abort between the decision and its output.
    transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty') || transcript=""
    if commit_prose_reviewed "$transcript"; then
      ask_confirmation
    else
      deny_unreviewed_commit
    fi
  elif is_git_subcommand "$cmd" push; then
    ask_confirmation
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
