#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). It denies a command that starts a process
# which nothing tracks: a command with the background operator "&", or with
# nohup, disown, or coproc. When such a process dies, the model gets no
# signal and waits for work that does not run. The message names the two
# tracked routes: scripts/background-run.sh with the run_in_background
# parameter of the Bash tool, and a `wait` in the same command.
#
# The hook is a guard for a model that cooperates. It is not a security
# boundary. Thus it approximates "the command starts a process that nothing
# tracks" with THE RULE below, on the words and the separators of the
# command. It does not follow the grammar of the shell. The rule reads the
# whole command as one sequence. It does not follow a subshell, a pipeline,
# a case command, or a function definition.
#
# THE RULE.
#
#   1. Deny when the command holds a background operator "&" and no bare
#      wait comes after the last one. A bare wait is the word "wait" in the
#      command position with no argument and no redirection: the next token
#      is the end of the command, or a separator that holds no "<" and no
#      ">". An "&" inside "&&", ">&", "<&", "&>", "|&", ";&", or ";;&" is a
#      different operator.
#   2. Deny when nohup, disown, or coproc is a word in the command position.
#      A path prefix counts: /usr/bin/nohup.
#   3. A word is in the command position when it is one of these:
#        - the first word of the command;
#        - a word after a separator that ends a command: ";", "&", "|", "(",
#          a backquote, or a newline;
#        - a word directly after one of the reserved words then, do, else,
#          elif, if, while, until, "{", "!", and time.
#      Variable assignments before the word are skipped. The rule does not
#      examine the position of the reserved word.
#
# A separator is a sequence of separator characters with no word between
# them, as in ");" or "; >". Its last character decides the command
# position. A backslash at the end of a line joins the next line. An empty
# quoted word is an argument: wait "".
#
# TWO READINGS, TWO DECISIONS. The hook reads the command as the git gate
# does, with the maskers and the tokenizer of lib/shell-command.sh.
#
#   deny   The rule matches in the reading of the shell. Quotes group words.
#          A quoted "&", a comment, and the body of a heredoc that the shell
#          does not expand do not count, because the shell that reads the
#          command does not execute them. The shell expands a body that has
#          an unquoted delimiter and holds "$(", "${", or a backquote. The
#          hook reads each line of such a body as a command line. This
#          reading has no override.
#   ask    The rule matches only in the reading of an interpreter. It
#          applies when the command names an interpreter (SHELL_FEEDS: bash,
#          sudo, env, source, and more). Then a quoted string or a heredoc
#          body can be a command line, as in bash -c "server &". In this
#          reading, quotes also split words, and nohup, disown, or coproc
#          counts in ANY position, because the reading cannot tell where a
#          command starts inside the string. This reading is a guess. Thus
#          the hook asks the user, and it does not deny.
#
# STATED LIMITS. Each line is one case that the rule gets wrong, with the
# result of the hook. A test with a "limit:" name pins each one.
#
#   False deny or false question:
#     deny    echo $((flags & 1))               An arithmetic "&".
#     deny    echo ${url//&/%26}                An "&" in an expansion.
#     deny    cat <<EOF, body "$(whoami) & x"   Text in an expanded heredoc.
#     deny    make a & wait > log               A wait with a redirection.
#     deny    make a & wait; > log echo done    An operator, then a redirection.
#     deny    make a & wait %1                  A wait that names each job.
#     deny    make a & time -p wait             A wait after an option of time.
#     deny    make a & case $x in a) wait;; esac    A wait after a case pattern.
#     deny    echo then nohup                   A reserved word as an argument.
#     ask     sudo grep -r nohup /etc           Data behind an interpreter.
#
#   Escape:
#     permit  (server &); wait                  The wait is outside the subshell.
#     permit  x=$(server &); wait               The same, for a substitution.
#     permit  make a & (wait)                   The wait is inside a subshell.
#     permit  server & wait | cat               The wait is in a pipeline.
#     permit  server & if false; then wait; fi  The wait does not run.
#     permit  server & f() { wait; }            The same, for a function.
#     permit  server & echo then wait           A reserved word as an argument.
#     permit  make a & wait `cat pidfile`       A backquote ends the wait.
#     permit  make a & wait \                   A last backslash is an argument.
#     permit  case $x in a) nohup server;; esac     nohup after a case pattern.
#     permit  time -p nohup server              nohup after an option of time.
#     permit  nice nohup server                 nohup behind a program.
#     permit  bash -c "server &"; wait          A wait after the string.
#     permit  echo "$(server &)"                A quoted substitution.
#     permit  python3 -c "<starts a process>"   An interpreter that is no shell.
#
# The watcher and the report hook cannot see an escaped process, because it
# has no entry in the job registry.
set -euo pipefail

# The directory of this script. The expansion starts no process. A path with
# no slash is a file in the current directory.
if [[ "${BASH_SOURCE[0]}" == */* ]]; then HOOK_DIR="${BASH_SOURCE[0]%/*}"; else HOOK_DIR=.; fi

# shellcheck source=lib/shell-command.sh disable=SC1091
source "${HOOK_DIR}/lib/shell-command.sh"

main() {
  local input cmd
  input=$(cat)
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || return 0

  # The tokenizer is an awk program. This test keeps it off the path of
  # each command that cannot hold a denied token.
  can_hold_denied_token "$cmd" || return 0

  case "$(verdict "$cmd")" in
    permit) ;;
    ask) reply ask "$ASK_FINDING" ;;
    *) reply deny "$DENY_FINDING" ;;
  esac
}

# The command words that start a process which nothing tracks. To add one,
# add it here. The pre-check, the rule, and the two messages read this list.
# No other code change is necessary.
DETACH_WORDS="nohup disown coproc"

DENY_FINDING="This command starts a process that nothing tracks."
ASK_FINDING="A quoted string or a heredoc body that an interpreter executes seems to start a process that nothing tracks. The hook cannot read that text as the interpreter does, so you must decide. If the text is only data, approve the command."

# can_hold_denied_token <command-string>
#
# Succeeds when the text holds an "&" or one of DETACH_WORDS. The removal
# of the quote characters first makes the test agree with the tokenizer,
# which reads no"hu"p as nohup. For the same reason, a backslash at the end
# of a line goes first, with the end of that line.
can_hold_denied_token() {
  local joined=${1//$'\\\n'/} word
  joined=${joined//[\'\"\\]/}
  for word in '&' $DETACH_WORDS; do
    if [[ "$joined" == *"$word"* ]]; then return 0; fi
  done
  return 1
}

# verdict <command-string>
#
# Prints "deny", "ask", or "permit". The reading of the shell decides first.
# A match only in the reading of an interpreter is a guess about text that
# the shell gives to a program.
verdict() {
  if rule_matches shell "$(mask_shell_reading "$1")"; then
    printf 'deny'
  elif names_interpreter "$1" && rule_matches interpreter "$(mask_nonexecuting "$1")"; then
    printf 'ask'
  else
    printf 'permit'
  fi
}

# names_interpreter <command-string>
#
# Succeeds when a line of the text can name an interpreter (FEED_PATTERN).
# The reading of an interpreter matches only such a text, and it costs two
# awk processes. Measured: about 18 ms of the 36 ms for "cd /tmp && ls
# 2>&1". This test is a bash pattern match, so most commands do not pay
# that cost. It reads the text before the mask. A mask only removes text,
# so the test can succeed too often, and it cannot fail for a text that
# the reading matches. The pattern is for one line, so each end of a line
# becomes a space first.
names_interpreter() {
  [[ "${1//$'\n'/ }" =~ $FEED_PATTERN ]]
}

# rule_matches <reading> <masked-command-string>
#
# The decision. It succeeds when THE RULE of the header matches the text.
# The second argument is masked text, so this is a pure matcher.
#
#   shell        Quotes group words, as the shell reads them.
#   interpreter  The text must name an interpreter. Then quotes group words
#                or split them, and each of DETACH_WORDS counts in each
#                position.
#
# The program is the tokenizer, then the command tracker, then the matcher.
# The tracker gives BG, REDIRECTS, and command_position. Only this hook
# loads it. In the matcher, read_tokens makes the token stream for one mode
# of the tokenizer, and rule_holds decides on that stream.
rule_matches() {
  awk -v FEED="$FEED_PATTERN" -v READING="$1" -v DETACH_WORDS="$DETACH_WORDS" \
    "${SHELL_TOKENIZER_AWK}${SHELL_COMMAND_TRACKER_AWK}"'
    # Quotes that split words cannot tell where a command starts. Thus a
    # detach word counts in each position of that token stream.
    function found() {
      read_tokens(0)
      if (READING == "shell") return rule_holds(0)
      if (!feeds_present) return 0
      if (rule_holds(0)) return 1
      read_tokens(1)
      return rule_holds(1)
    }

    # Reads the stored lines into the token stream. With split_quotes at 0,
    # quotes group words. With split_quotes at 1, quotes split words.
    function read_tokens(split_quotes,   i) {
      reset_tokens()
      for (i = 1; i <= n; i++) tokenize(line[i], split_quotes)
    }

    # The decision, in one pass over the token stream. It reads only the
    # tokens. With detach_in_each_position at 1, a detach word counts also
    # outside the command position. pending is 1 from a background operator
    # until a bare wait.
    function rule_holds(detach_in_each_position,   i, pending) {
      for (i = 1; i <= NT; i++) {
        if (KIND[i] == "sep") { if (i in BG) pending = 1 }
        else if (detaches(TOK[i]) && (detach_in_each_position || command_position(i))) return 1
        else if (bare_wait(i) && command_position(i)) pending = 0
      }
      return pending
    }

    # True when word t, with no path prefix, is one of DETACH_WORDS.
    function detaches(t) { sub(/^.*\//, "", t); return t in DETACHES }

    # True when word i is "wait", and the token after it is a separator
    # with no redirection. The end of a line is a separator. A wait that is
    # the last token has no separator after it: the command ends in a quote
    # that has no end, and that quote is an argument. The tokens above NT
    # are not valid, so the function does not read them.
    function bare_wait(i) {
      return TOK[i] == "wait" && i < NT && KIND[i + 1] == "sep" && !((i + 1) in REDIRECTS)
    }

    BEGIN {
      split(DETACH_WORDS, detach_words, " ")
      for (detach_index in detach_words) DETACHES[detach_words[detach_index]] = 1
    }
    { line[++n] = $0; if ($0 ~ FEED) feeds_present = 1 }
    END { exit found() ? 0 : 1 }
  ' <<<"$2"
}

# reply <permission-decision> <finding>
#
# Prints the hook output. The list of the denied tokens and the two routes
# are the same for each decision.
reply() {
  local scripts_dir
  scripts_dir="$(cd "${HOOK_DIR}/../scripts" && pwd)"
  jq -n --arg decision "$1" --arg finding "$2" --arg words "${DETACH_WORDS// /, }" \
    --arg run "${scripts_dir}/background-run.sh" --arg watch "${scripts_dir}/background-watch.sh" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $decision,
      permissionDecisionReason: "\($finding) The hook looks for the operator & and for these command words: \($words). If that process dies, you get no signal. Use one of these routes. (1) For a job that continues after this call: run \($run) <command> with the run_in_background parameter of the Bash tool, then run \($watch) with the same parameter. The watcher exits when the job ends or its heartbeat stops, and the harness then starts you. (2) For parallel work that ends in this call: put a wait command with no argument and no redirection after the last &."
    }
  }'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
