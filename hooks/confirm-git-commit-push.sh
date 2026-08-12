#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): gates git commit and push. A git commit is
# denied until the communication:prose-reviewer agent has been invoked this
# turn (the commit-message skill's required review step for the drafted
# message). A commit that passes that gate - and any push - still asks for
# confirmation, per the standing instruction that commits and pushes require
# an explicit instruction in the current turn. When the transcript cannot be
# judged (missing path or file, no turn boundary), the review gate degrades
# to the plain ask rather than blocking the commit.
set -euo pipefail

# The agent that satisfies the commit gate. Kept in lockstep with
# enforce-prose-review.sh's REVIEW_AGENT - the two hooks enforce the same
# prose-review policy at different moments (commit time vs turn end), so a
# rename must change both.
REVIEW_AGENT="communication:prose-reviewer"

# Commands that can execute text handed to them, so a heredoc body near one
# may be executed rather than merely written. Add a name here to widen the
# masker's refusal - no other code changes needed. Matched as a whole word,
# optionally path-prefixed (/bin/bash counts).
SHELL_FEEDS="bash sh zsh ksh dash fish csh tcsh busybox eval source ssh su sudo env xargs parallel"

# shellcheck source=lib/transcript.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/transcript.sh"

# mask_nonexecuting <command-string>
#
# Prints the command with text the shell will NOT execute removed, so the
# matcher below is not tripped by a command that merely MENTIONS the gated
# words. Two kinds are removed: shell comments, and the bodies of heredocs
# that are not fed to a shell.
#
# EVERY RULE HERE FAILS CLOSED. Removing text can only lose a match, and a
# lost match is a real git command running without the gate, so each rule
# declines to mask whenever it cannot be sure. A false positive costs one
# confirmation prompt; a false negative costs the guarantee. The first
# version of this function masked optimistically and opened eight bypasses,
# each of which is now a BYPASS test in the suite.
#
# The rules, and what each refuses to touch:
#
#   comments      A "#" starts a comment only outside quotes and at a word
#                 boundary. Quote state is tracked character by character AND
#                 carried across lines, since a shell string may span them,
#                 and backslash escapes are honoured (a \" inside a double
#                 quoted string does not close it). Getting either wrong
#                 fabricates a comment that deletes a real command.
#   heredocs      A body is removed only when its introducer is a << or <<-
#                 found OUTSIDE quotes and not backslash-escaped, with the
#                 delimiter adjacent to it (<<EOF, <<-EOF, <<'EOF', <<"EOF" -
#                 never << EOF with a space), and a matching terminator line
#                 AFTER it exists. Adjacency is what separates a heredoc from
#                 a here-string (<<<), an arithmetic shift (1 << N), and a
#                 C++ stream insertion.
#   expansions    An UNQUOTED delimiter (<<EOF) means the shell expands the
#                 body, so a body containing $(, ` or ${ keeps every line -
#                 the shell really does run what is in there. A quoted
#                 delimiter (<<'EOF') suppresses expansion, so its body is
#                 inert data.
#   shell feeds   Nothing is masked when the command anywhere names a shell
#                 interpreter (SHELL_FEEDS below), pipes into one, or calls
#                 eval: the body may be executed somewhere other than its
#                 own introducer line, as in "{ cat <<EOF ... } | bash" or a
#                 heredoc captured into a variable and evaled later.
#   indirection   A command word that is a variable ($SHELL <<EOF) could name
#                 any interpreter, so such a line masks nothing.
#
# ACCEPTED HOLE, stated plainly rather than papered over: a heredoc fed to a
# NON-shell interpreter (python3, perl, node, ruby) is masked, yet that
# interpreter can run git itself - python3 - <<'PY' calling subprocess is a
# real bypass. Closing it means adding those names to SHELL_FEEDS, which
# would defeat the masker's whole purpose, since a python heredoc mentioning
# a commit in a comment is the case that motivated it. The fail-closed claim
# above is therefore a claim about SHELLS, not about every interpreter.
#
# The introducer and terminator lines are always printed. Keeping the
# introducer preserves this repository's own commit form, where the git
# invocation sits on the introducer. An unterminated introducer masks
# nothing AND suppresses comment stripping for the rest of the input, so
# that re-masking the output cannot turn a commented terminator lookalike
# ("EOF # done", which bash does not accept as a terminator) into a real
# one.
mask_nonexecuting() {
  printf '%s' "$1" | awk -v feeds="$SHELL_FEEDS" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }

    # scan_line(l, q0): walk one line from entry quote state q0, honouring
    # backslash escapes. Records, in globals: CUT (index of the "#" that
    # starts a comment, or 0), LT (index of an unquoted, unescaped "<<", or
    # 0), and returns the quote state the NEXT line inherits. One scan
    # answers both questions, so no character is examined twice.
    function scan_line(l, q0,   i, c, n, q) {
      q = q0; CUT = 0; LT = 0; n = length(l)
      for (i = 1; i <= n; i++) {
        c = substr(l, i, 1)
        if (c == "\\" && q != SQ) { i++; continue }   # escape; literal in ''
        if (q != "") { if (c == q) q = ""; continue }
        if (c == SQ || c == DQ) { q = c; continue }
        if (c == "#" && !CUT && (i == 1 || substr(l, i - 1, 1) ~ /[[:space:];&|(]/)) CUT = i
        if (c == "<" && !LT && !CUT && substr(l, i + 1, 1) == "<") { LT = i; i++ }
      }
      return q
    }

    # The visible-code part of a line: everything before a real comment.
    function code_of(l, q0) { scan_line(l, q0); return CUT ? substr(l, 1, CUT - 1) : l }

    # The heredoc delimiter introduced on this line, or "". Sets DELIM_QUOTED.
    function intro_delim(l, q0,   rest) {
      DELIM_QUOTED = 0
      if (l ~ /\(\(/) return ""                          # arithmetic, both forms
      if (l ~ /(^|[|&;(])[[:space:]]*\$/) return ""      # interpreter via variable
      scan_line(l, q0)
      if (!LT) return ""
      if (substr(l, LT + 2, 1) == "<") return ""         # here-string
      rest = substr(l, LT + 2)
      sub(/^-/, "", rest)
      if (match(rest, "^" SQ "[^" SQ "]*" SQ) || match(rest, "^" DQ "[^" DQ "]*" DQ)) {
        DELIM_QUOTED = 1
        return substr(rest, RSTART + 1, RLENGTH - 2)
      }
      if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) return substr(rest, RSTART, RLENGTH)
      return ""                                          # << EOF, or junk
    }

    function body_expands(from, to,   k) {
      for (k = from; k <= to; k++)
        if (line[k] ~ /\$\(/ || line[k] ~ /\$\{/ || index(line[k], BQ)) return 1
      return 0
    }

    BEGIN {
      SQ = sprintf("%c", 39); DQ = "\""; BQ = sprintf("%c", 96)
      gsub(/[[:space:]]+/, "|", feeds)
      FEED = "(^|[[:space:];&|(])([^[:space:];&|(]*/)?(" feeds ")([[:space:]<;&|)]|$)"
    }
    { line[++n] = $0 }
    END {
      # One pass: entry quote state per line, and the visible code of each,
      # both computed once and reused by every later pass.
      q = ""
      for (i = 1; i <= n; i++) { entry[i] = q; code[i] = code_of(line[i], q); q = scan_line(line[i], q) }

      # A shell interpreter or eval anywhere means a body may be executed
      # away from its introducer; mask no bodies at all. The guard reads the
      # whole line, not just its visible code: a fabricated comment must not
      # be able to hide the interpreter from this check.
      for (i = 1; i <= n; i++)
        if (code[i] ~ FEED || line[i] ~ FEED) { feeds_present = 1; break }

      stop_stripping = n + 1
      if (!feeds_present) {
        # Occurrence lists per delimiter, so "the first terminator AFTER this
        # introducer" is a cursor step rather than a scan. Two heredocs
        # sharing a delimiter - the commonest multi-heredoc shape - need the
        # occurrence after i, not the globally first one.
        for (i = 1; i <= n; i++) { t = trim(line[i]); occ[t, ++seen[t]] = i }

        for (i = 1; i <= n; i++) {
          d = intro_delim(code[i], entry[i])
          if (d == "") continue
          j = 0
          while (++cur[d] <= seen[d]) if (occ[d, cur[d]] > i) { j = occ[d, cur[d]]; break }
          if (!j) { stop_stripping = i + 1; break }        # unterminated
          if (!DELIM_QUOTED && body_expands(i + 1, j - 1)) continue
          for (k = i + 1; k < j; k++) drop[k] = 1          # body, not terminator
          i = j
        }
      }
      for (i = 1; i <= n; i++)
        if (!(i in drop)) print (i < stop_stripping) ? code[i] : line[i]
    }
  '
}

# is_git_subcommand <masked-command-string> <subcommand>
#
# Succeeds when <subcommand> appears as a standalone token after a git
# invocation within the same shell-separator segment. The argument is
# already-masked text (main calls mask_nonexecuting once), so this is a
# pure matcher over what the shell will execute. Token matching on
# both words, not substring: a ref such as fix-commit-message or a remote
# named commit-fixes must never count as a commit, and a command like "legit"
# is not git (though a path-prefixed /usr/bin/git is). The subcommand token
# may end at whitespace, a separator, a redirection, a closing paren, or the
# end of the command. Matching is per line, so a backslash-continuation
# between git and its subcommand escapes the gate - accepted, since real
# commit commands (including the heredoc form) keep the two words on one line.
#
# The text is fed to grep as a here-string rather than through a pipe.
# Piping would fail open on a large command: grep -q exits at the first
# match, the writer upstream is killed by SIGPIPE (141), and `set -o
# pipefail` turns that into a failing pipeline - reporting "no match" for a
# command that does match.
is_git_subcommand() {
  grep -Eq "(^|[[:space:];&|(/\`])git[^&|;]*[[:space:]]$2([[:space:]&|;><)\`]|\$)" <<<"$1"
}

ask_confirmation() {
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: "git commit/push requires an explicit instruction in this turn - confirm to proceed."
    }
  }'
}

deny_unreviewed_commit() {
  jq -n --arg agent "$REVIEW_AGENT" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "This commit message has not been prose-reviewed: delegate the drafted message to the \($agent) agent, apply any confirmed fixes, then retry the commit."
    }
  }'
}

# commit_prose_reviewed <transcript-path>
#
# Succeeds when the review agent was invoked since the turn start, or when
# the transcript cannot be judged (unjudgeable path or no turn boundary) -
# the gate denies only when the turn's events are readable and contain no
# review. The boundary is computed once and reused, so the transcript is
# scanned a single time.
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
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

  # Masking only ever deletes characters, so a command with no "git" in it
  # cannot acquire one; skipping both the mask and the match here keeps the
  # awk program off the latency path of every non-git Bash call. Masking
  # once, rather than inside each is_git_subcommand call, halves the rest.
  case $cmd in
    *git*) ;;
    *) return 0 ;;
  esac
  cmd=$(mask_nonexecuting "$cmd")

  if is_git_subcommand "$cmd" commit; then
    transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
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
