#!/usr/bin/env bash
# Shared readers of a shell command string for the PreToolUse hooks. A hook
# sources this file. Nothing executes it on its own. It is the single place
# that knows which text of a command the shell executes and how that text
# divides into words and separators. confirm-git-commit-push.sh and
# deny-untracked-background.sh both depend on it. Thus the quote rules, the
# heredoc rules, and the list of interpreters cannot drift between them.

# Commands that can execute text given to them. A heredoc body near one of
# them can run, not only be written. To widen the refusal of the masker, add
# a name here. No other code change is necessary. The match is on a whole
# word, with an optional path prefix (/bin/bash counts).
SHELL_FEEDS="bash sh zsh ksh dash fish csh tcsh busybox eval source ssh su sudo env xargs parallel"

# SHELL_FEEDS as one ERE. The match is on a whole word, with an optional path
# prefix. It is built here and not inside either awk program. Thus the masker
# and the matcher cannot disagree about what counts as an interpreter.
FEED_PATTERN="(^|[[:space:];&|(])([^[:space:];&|(]*/)?(${SHELL_FEEDS// /|})([[:space:]<;&|)]|\$)"

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
#                 backslash. It also requires the delimiter adjacent to the
#                 introducer (<<EOF, <<-EOF, <<'EOF', <<"EOF", never << EOF
#                 with a space). It requires a matching terminator line
#                 AFTER the introducer. Adjacency
#                 separates a heredoc from a here-string (<<<), an
#                 arithmetic shift (1 << N), and a C++ stream insertion.
#   expansions    An UNQUOTED delimiter (<<EOF) means that the shell expands
#                 the body. A body that holds $(, ` or ${ keeps every line.
#                 The shell runs what is in there. A quoted delimiter
#                 (<<'EOF') stops the expansion, so its body is inert data.
#   shell feeds   The function masks nothing when the command names a shell
#                 interpreter anywhere (SHELL_FEEDS below), pipes into one,
#                 or calls eval. The body can run somewhere other than its
#                 own introducer line. Examples are "{ cat <<EOF ... } | bash"
#                 and a heredoc captured into a variable and passed to eval
#                 later.
#   indirection   A command word that is a variable ($SHELL <<EOF) can name
#                 any interpreter, so such a line masks nothing.
#
# ACCEPTED HOLE, stated and not hidden: the function masks a heredoc that
# feeds a NON-shell interpreter (python3, perl, node, ruby). That
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
# mask of the output cannot turn a commented terminator lookalike into a
# real one. An example is "EOF # done", which bash does not accept as a
# terminator.
mask_nonexecuting() {
  mask_command "$1" 1
}

# mask_shell_reading <command-string>
#
# Prints the command without the text that THIS shell does not execute. It
# is mask_nonexecuting with one rule less: the name of an interpreter does
# not keep the body of a heredoc. An interpreter can execute that body, but
# the shell that reads the command does not. Each other rule stays. The two
# functions print the same text when the command names no interpreter.
#
# A hook that uses this function must also read the output of
# mask_nonexecuting. If not, a body that feeds a shell runs with no check.
mask_shell_reading() {
  mask_command "$1" 0
}

# mask_command <command-string> <feeds-keep-bodies>
#
# The one implementation of the two masks above. The second argument is 1
# when the name of an interpreter must keep each heredoc body, and 0 if not.
mask_command() {
  printf '%s' "$1" | awk -v FEED="$FEED_PATTERN" -v FEEDS_KEEP_BODIES="$2" '
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
      for (i = 1; FEEDS_KEEP_BODIES && i <= n; i++)
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

# The tokenizer, as the text of awk functions in three strings. A hook puts
# two of them in front of its own awk program, because an awk program is one
# string and awk has no include.
#
#   SHELL_TOKENIZER_AWK        Both hooks load it. It divides the text into
#                              words and separators.
#   SHELL_COMMAND_TRACKER_AWK  Only deny-untracked-background.sh loads it.
#                              It records the background operators, the
#                              redirections, and the last character of each
#                              separator. It gives the command position.
#   SHELL_NO_TRACKER_AWK       Only confirm-git-commit-push.sh loads it. It
#                              holds empty versions of the tracker functions.
#
# A hook must load the tokenizer with exactly one of the other two strings.
# The tokenizer calls two functions that it does not define. They are the
# only route from the tokenizer into a tracker:
#
#   tracker_reset()                   reset_tokens() calls it.
#   tracker_after_separator(c, l, i)  The tokenizer read the separator
#                                     character c, which is at index i of
#                                     line l. The separator is token NT. NT
#                                     is 0 when no word came before c. At
#                                     the end of a line, c is a newline and
#                                     i is after the last character. The
#                                     tokenizer does not call it for the end
#                                     of a line that a backslash continues.
#
# Thus a change of a rule of the deny hook changes only the tracker, and the
# program of the git gate stays the same.
#
# The hook stores each input line. Then it calls reset_tokens() one time,
# and tokenize(line, split_quotes) for each line. See is_git_subcommand in
# confirm-git-commit-push.sh for the two passes (quotes group, and quotes
# split).
#
# The token stream is TOK and KIND, from 1 to NT. A hook reads only that
# from the tokenizer. The tokenizer also keeps scanner state between lines:
# the partial word T, the quote state Q, QUOTED, and HELD with its three
# saved values. That state is private to the tokenizer. Each other value of
# a token belongs to a tracker.
#
# A word can be empty: the shell gives an empty argument for "" or ''. The
# pass with quotes that group words emits it. The pass with quotes that
# split words does not, because there each quote is only a word boundary.
#
# A backslash at the end of a line joins the next line. The scanner cannot
# know that a next line comes. Thus it emits the end of the line, and it
# takes that back when the next line comes. A caller that stops after the
# last line therefore sees each word, also before a last backslash. HELD is
# 1 from such an end of a line until the next line comes. The tokenizer
# adds the separator token for that end of a line, but it does not call the
# tracker. Thus the tracker has nothing to take back.

# shellcheck disable=SC2016,SC2034 # The text is awk code, and the hooks that source this file use it.
SHELL_TOKENIZER_AWK='
    # confirm-git-commit-push.sh and deny-untracked-background.sh use this
    # text.
    #
    # The token stream is TOK/KIND, 1..NT. KIND is "word" or "sep". A sep is
    # a shell separator. A word holds what the shell gives the program, with
    # the quotes removed.
    # QUOTED is 1 when the word under construction holds a quote. Only then
    # is an empty word an argument.
    function emit_word(t) {
      if (t == "" && !QUOTED) return
      QUOTED = 0
      TOK[++NT] = t; KIND[NT] = "word"
    }
    function emit_sep(c, l, i) {
      if (NT > 0 && KIND[NT] != "sep") { TOK[++NT] = ""; KIND[NT] = "sep" }
      if (!HELD) tracker_after_separator(c, l, i)
    }

    # Clears the token stream and the scanner state before a pass.
    function reset_tokens() {
      split("", TOK); split("", KIND)
      NT = 0; T = ""; Q = ""; QUOTED = 0; HELD = 0
      tracker_reset()
    }

    # hold_line_end() stores the scanner state before the end of a line that
    # a backslash continues. take_back_line_end() puts that state back. The
    # tokens that the end of the line added are above NT then, and the next
    # token replaces each of them. A caller must read no token above NT.
    function hold_line_end() {
      HELD = 1; HELD_NT = NT; HELD_WORD = T; HELD_QUOTED = QUOTED
    }
    function take_back_line_end() {
      if (HELD) { HELD = 0; NT = HELD_NT; T = HELD_WORD; QUOTED = HELD_QUOTED }
    }

    # tokenize(l, split_quotes): append one line to the stream. The quote
    # state Q and the partial word T are globals, because a quoted word can
    # span lines. A line that ends inside a quote therefore emits no
    # separator. A backslash at the end of a line joins the next line.
    function tokenize(l, split_quotes,   i, c, len, continued) {
      take_back_line_end()
      len = length(l)
      for (i = 1; i <= len; i++) {
        c = substr(l, i, 1)
        if (c == "\\" && Q != SQ && i == len) { continued = 1; break }
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
          if (split_quotes) { emit_word(T); T = "" } else { Q = c; QUOTED = 1 }
          continue
        }
        if (c == " " || c == "\t") { emit_word(T); T = ""; continue }
        if (index(SEPS, c)) { emit_word(T); T = ""; emit_sep(c, l, i); continue }
        T = T c
      }
      if (Q != "") { if (!continued) T = T "\n"; return }
      if (continued) hold_line_end()
      emit_word(T); T = ""; emit_sep("\n", l, len + 1)
    }

    BEGIN {
      SQ = sprintf("%c", 39); DQ = "\""; BQ = sprintf("%c", 96)
      SEPS = ";&|()<>" BQ
    }
'

# The tracker of deny-untracked-background.sh. For each separator, it
# records these values:
#
#   LAST[i]  the last separator character of token i, or a newline when the
#            end of a line made the separator. A word after ";", "&", "|",
#            "(", a backquote, or a newline is in the command position. A
#            word after "<" or ">" is the target of a redirection. The end
#            of a line that a backslash continues writes no LAST, because
#            the tokenizer does not call the tracker for it.
#   BG[i]    1 when the separator holds the control operator "&", which
#            starts the command before it in the background. An "&" next to
#            a second "&", or next to "<", ">", or "|", is part of a
#            different operator ("&&", ">&", "<&", "&>", "|&"). An "&"
#            after ";" is part of a case terminator (";&", ";;&").
#   REDIRECTS[i]  1 when the separator holds a "<" or a ">". The word
#            before it has a redirection, or a redirection starts the
#            next command, as in "wait; > log echo".
#
# The tracker follows no subshell, no pipeline, no case command, and no
# function definition. The header of deny-untracked-background.sh lists the
# results of that as limits.

# RESERVED_BEFORE_COMMAND lists the reserved words after which a command
# starts. The word after one of them is in the command position. The
# tracker does not examine the position of the reserved word itself. "time"
# is in the list because the shell reads it as a reserved word. "nice" is a
# program, and the tracker cannot know which arguments of a program are a
# command. To change the list, change the string. No other change is
# necessary.
RESERVED_BEFORE_COMMAND="then do else elif if while until { ! time"

# shellcheck disable=SC2016,SC2034 # The text is awk code, and the hook that sources this file uses it.
SHELL_COMMAND_TRACKER_AWK='
    # Only deny-untracked-background.sh uses this text. The hook puts it
    # after SHELL_TOKENIZER_AWK. The two tracker functions come first. The
    # rules that they apply come after them.

    # Clears the tracker state before a pass.
    function tracker_reset() {
      split("", LAST); split("", BG); split("", REDIRECTS)
    }

    # Records the separator character c in separator NT. With NT at 0, no
    # word came before c, and no separator token holds it.
    function tracker_after_separator(c, l, i) {
      if (NT > 0) {
        LAST[NT] = c
        if (c == "<" || c == ">") REDIRECTS[NT] = 1
        if (c == "&" && background_operator(l, i)) BG[NT] = 1
      }
    }

    # True when the "&" at index i of line l is the control operator that
    # starts a command in the background. The "&" of "&&", of a redirection
    # (">&", "<&", "&>"), of the pipe "|&", and of a case terminator (";&",
    # ";;&") is not that operator.
    function background_operator(l, i,   before, after) {
      before = (i > 1) ? substr(l, i - 1, 1) : " "
      after = substr(l, i + 1, 1)
      return index("&;<>|", before) == 0 && after != "&" && after != ">"
    }

    # True when word i is in the command position. Variable assignments
    # before it are skipped, so the "nohup" in "FOO=1 nohup server" is in
    # the command position. The token before the word decides: no token, a
    # separator after which a command starts, or a reserved word.
    function command_position(i,   j) {
      for (j = i - 1; j >= 1 && KIND[j] == "word" && TOK[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/; j--) ;
      if (j < 1) return 1
      if (KIND[j] == "sep") return index(";&|(\n" BQ, LAST[j]) > 0
      return TOK[j] in STARTS_COMMAND
    }

    BEGIN {
      split("'"$RESERVED_BEFORE_COMMAND"'", reserved_words, " ")
      for (reserved_index in reserved_words) STARTS_COMMAND[reserved_words[reserved_index]] = 1
    }
'

# The tracker of confirm-git-commit-push.sh: it follows nothing. The git
# gate reads only the words and the separators, so each function is empty.
# shellcheck disable=SC2016,SC2034 # The text is awk code, and the hook that sources this file uses it.
SHELL_NO_TRACKER_AWK='
    # Only confirm-git-commit-push.sh uses this text. The hook puts it after
    # SHELL_TOKENIZER_AWK.
    function tracker_reset() { }
    function tracker_after_separator(c, l, i) { }
'
