#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). It gates git commit and git push. The hook
# denies a git commit until the communication:prose-reviewer agent has run
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

# Commands that can execute text given to them. A heredoc body near one of
# them can run, not only be written. To widen the refusal of the masker, add
# a name here. No other code change is necessary. The match is on a whole
# word, with an optional path prefix (/bin/bash counts).
SHELL_FEEDS="bash sh zsh ksh dash fish csh tcsh busybox eval source ssh su sudo env xargs parallel"

# SHELL_FEEDS as one ERE. The match is on a whole word, with an optional path
# prefix. It is built here and not inside either awk program. Thus the masker
# and the matcher cannot disagree about what counts as an interpreter.
FEED_PATTERN="(^|[[:space:];&|(])([^[:space:];&|(]*/)?(${SHELL_FEEDS// /|})([[:space:]<;&|)]|\$)"

# shellcheck source=lib/transcript.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/transcript.sh"

# mask_nonexecuting <command-string>
#
# Prints the command without the text that the shell will NOT execute. Thus
# a command that only MENTIONS the gated words does not trip the matcher
# below. The function removes two kinds of text: shell comments, and the
# bodies of heredocs that do not feed a shell.
#
# EVERY RULE HERE FAILS CLOSED. The removal of text can only lose a match. A
# lost match is a real git command that runs without the gate. So each rule
# refuses to mask when it is not sure. A false positive costs one
# confirmation prompt. A false negative costs the guarantee. The first
# version of this function masked optimistically and opened eight bypasses.
# Each of them is now a BYPASS test in the suite.
#
# The rules, and what each one refuses to touch:
#
#   comments      A "#" starts a comment only outside quotes and at a word
#                 boundary. The scanner tracks the quote state character by
#                 character AND carries it across lines, because a shell
#                 string can span lines. It honors backslash escapes. A \"
#                 inside a double-quoted string does not close the string.
#                 An error in either rule fabricates a comment that deletes
#                 a real command.
#   heredocs      The function removes a body only when its introducer is a
#                 << or <<- that is OUTSIDE quotes and not escaped with a
#                 backslash, with the delimiter adjacent to it (<<EOF,
#                 <<-EOF, <<'EOF', <<"EOF", never << EOF with a space), and
#                 with a matching terminator line AFTER it. Adjacency
#                 separates a heredoc from a here-string (<<<), an
#                 arithmetic shift (1 << N), and a C++ stream insertion.
#   expansions    An UNQUOTED delimiter (<<EOF) means that the shell expands
#                 the body. A body that holds $(, ` or ${ keeps every line.
#                 The shell runs what is in there. A quoted delimiter
#                 (<<'EOF') stops the expansion, so its body is inert data.
#   shell feeds   The function masks nothing when the command names a shell
#                 interpreter anywhere (SHELL_FEEDS below), pipes into one,
#                 or calls eval. The body can run somewhere other than its
#                 own introducer line, as in "{ cat <<EOF ... } | bash" or a
#                 heredoc captured into a variable and passed to eval later.
#   indirection   A command word that is a variable ($SHELL <<EOF) can name
#                 any interpreter, so such a line masks nothing.
#
# ACCEPTED HOLE, stated and not hidden: the function masks a heredoc that
# feeds a NON-shell interpreter (python3, perl, node, ruby), but that
# interpreter can run git itself. python3 - <<'PY' with a subprocess call is
# a real bypass. A fix adds those names to SHELL_FEEDS, and that defeats the
# whole purpose of the masker. A python heredoc that mentions a commit in a
# comment is the case that motivated it. The fail-closed claim above is
# therefore a claim about SHELLS, not about every interpreter.
#
# The function always prints the introducer line and the terminator line.
# The introducer keeps the commit form of this repository, where the git
# call sits on the introducer. An unterminated introducer masks nothing AND
# stops the removal of comments for the rest of the input. Thus a second
# mask of the output cannot turn a commented terminator lookalike ("EOF #
# done", which bash does not accept as a terminator) into a real one.
mask_nonexecuting() {
  printf '%s' "$1" | awk -v FEED="$FEED_PATTERN" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }

    # scan_line(l, q0): walk one line from the entry quote state q0, with
    # backslash escapes honored. It records two globals: CUT (the index of
    # the "#" that starts a comment, or 0) and LT (the index of an unquoted,
    # unescaped "<<", or 0). It returns the quote state that the NEXT line
    # inherits. One scan answers both questions, so no character is read
    # twice.
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

    # The visible code of a line: all text before a real comment.
    function code_of(l, q0) { scan_line(l, q0); return CUT ? substr(l, 1, CUT - 1) : l }

    # The heredoc delimiter that this line introduces, or "". Sets DELIM_QUOTED.
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

    BEGIN { SQ = sprintf("%c", 39); DQ = "\""; BQ = sprintf("%c", 96) }
    { line[++n] = $0 }
    END {
      # One pass. It computes the entry quote state of each line and the
      # visible code of each line once. Every later pass uses both.
      q = ""
      for (i = 1; i <= n; i++) { entry[i] = q; code[i] = code_of(line[i], q); q = scan_line(line[i], q) }

      # A shell interpreter or eval anywhere means that a body can run away
      # from its introducer. Then mask no body at all. The guard reads the
      # whole line, not only its visible code. A fabricated comment must not
      # hide the interpreter from this check.
      for (i = 1; i <= n; i++)
        if (code[i] ~ FEED || line[i] ~ FEED) { feeds_present = 1; break }

      stop_stripping = n + 1
      if (!feeds_present) {
        # Occurrence lists per delimiter. Thus "the first terminator AFTER
        # this introducer" is one cursor step, not a scan. Two heredocs that
        # share a delimiter, the most common multi-heredoc shape, need the
        # occurrence after i, not the first one in the file.
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
# Succeeds when the text runs git with <subcommand> as its subcommand. The
# argument is masked text (main calls mask_nonexecuting once), so this is a
# pure matcher over what the shell will execute.
#
# The subcommand is the FIRST non-option word after a git command word, not
# any occurrence of the word. "git help commit", "git log --grep commit", and
# "git rev-parse --verify commit" are read-only commands whose ARGUMENT is
# the watched word. A gate on one of them denies a commit that does not
# exist and tells the model to review a message that it never wrote. The
# matcher skips the global options that git accepts before its subcommand,
# with the value of each option that takes a separate token (-C, -c,
# --git-dir, and the rest of GIT_GLOBAL_OPTS_WITH_VALUE).
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
# before the comparison of words, and only a scanner that tracks the quote
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
# A line break separates commands, so a backslash continuation between the
# command word and its subcommand escapes the gate. This is accepted. Real
# commit commands, with the heredoc form, keep the two words on one line. A
# quoted string spans lines, and the scanner carries the quote state across
# them to match.
#
# The matcher reads the whole command before it gives the verdict. Thus no
# early exit can leave a writer upstream killed by SIGPIPE (141), with
# `set -o pipefail` as the cause of a failed pipeline. That is how a large
# command escaped the gate when this matcher was a `grep -q` at the end of a
# pipe.
GIT_GLOBAL_OPTS_WITH_VALUE="-C -c --git-dir --work-tree --namespace --exec-path --super-prefix --config-env"

is_git_subcommand() {
  awk -v want="$2" -v valued="$GIT_GLOBAL_OPTS_WITH_VALUE" -v FEED="$FEED_PATTERN" '
    # The token stream is TOK/KIND, 1..NT. KIND is "word" or "sep". A sep is
    # a shell separator. A word holds what the shell gives the program, with
    # the quotes removed.
    function emit_word(t) { if (t != "") { TOK[++NT] = t; KIND[NT] = "word" } }
    function emit_sep() { if (NT > 0 && KIND[NT] != "sep") { TOK[++NT] = ""; KIND[NT] = "sep" } }

    # tokenize(l, split_quotes): append one line to the stream. The quote
    # state Q and the partial word T are globals, because a quoted word can
    # span lines. A line that ends inside a quote therefore emits no
    # separator.
    function tokenize(l, split_quotes,   i, c, len) {
      len = length(l)
      for (i = 1; i <= len; i++) {
        c = substr(l, i, 1)
        if (c == "\\" && Q != SQ) { i++; T = T substr(l, i, 1); continue }
        if (Q != "") { if (c == Q) Q = ""; else T = T c; continue }
        # A dollar sign immediately before a quote opens ANSI-C or locale
        # quoting. That quotes its contents exactly as a bare quote does, so
        # the dollar is punctuation and not part of the word. When the
        # scanner read it as an ordinary character, the ANSI-C spelling of a
        # subcommand became one word with a leading dollar. That matched
        # nothing and ran with no gate.
        if (c == "$" && i < len && (substr(l, i + 1, 1) == SQ || substr(l, i + 1, 1) == DQ)) continue
        if (c == SQ || c == DQ) {
          if (split_quotes) { emit_word(T); T = "" } else Q = c
          continue
        }
        if (c == " " || c == "\t") { emit_word(T); T = ""; continue }
        if (index(SEPS, c)) { emit_word(T); T = ""; emit_sep(); continue }
        T = T c
      }
      if (Q == "") { emit_word(T); T = ""; emit_sep() } else T = T "\n"
    }

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
      split("", TOK); split("", KIND); split("", alias_expands_to); NT = 0; T = ""; Q = ""
      for (i = 1; i <= n; i++) tokenize(line[i], split_quotes)
      for (i = 1; i <= NT; i++)
        if (KIND[i] == "word" && is_git(TOK[i]) && subcommand_after(i) == want) return 1
      return 0
    }

    BEGIN {
      SQ = sprintf("%c", 39); DQ = "\""
      SEPS = ";&|()<>" sprintf("%c", 96)
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
