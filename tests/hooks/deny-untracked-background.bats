#!/usr/bin/env bats
# Tests of hooks/deny-untracked-background.sh, the PreToolUse hook that
# denies a Bash command which starts a process that nothing tracks. The
# header of the hook states the rule and its limits.

# shellcheck disable=SC2016,SC1003 # Each command under test is shell text in single quotes.
load helpers

setup() {
  HOOK="${HOOKS_DIR}/deny-untracked-background.sh"
}

payload() {
  jq -n --arg command "$1" '{tool_name: "Bash", tool_input: {command: $command}}'
}

decision() {
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

denies() {
  run_hook "$HOOK" "$(payload "$1")"
  { [ "$status" -eq 0 ] && [ "$(decision)" = "deny" ]; } || {
    echo "not denied: $1"; return 1; }
}

# asks <command>: the hook must ask the user, and not deny.
asks() {
  run_hook "$HOOK" "$(payload "$1")"
  { [ "$status" -eq 0 ] && [ "$(decision)" = "ask" ]; } || {
    echo "not asked: $1 -> $output"; return 1; }
}

permits() {
  run_hook "$HOOK" "$(payload "$1")"
  { [ "$status" -eq 0 ] && [ -z "$output" ]; } || {
    echo "not permitted: $1 -> $output"; return 1; }
}

# awk_starts <command>
#
# Prints the number of awk processes that the hook starts for the command.
# A stand-in on PATH adds a line to a log and then runs the real awk.
awk_starts() {
  local bin log
  bin="$(fixture_dir)/bin"; log="$(fixture_dir)/awk-starts"
  mkdir -p "$bin"; : > "$log"
  printf '#!/bin/sh\necho awk >> "%s"\nexec "%s" "$@"\n' "$log" "$(command -v awk)" > "${bin}/awk"
  chmod +x "${bin}/awk"
  PATH="${bin}:${PATH}" run_hook "$HOOK" "$(payload "$1")"
  wc -l < "$log"
}

# --- the cost of the hook -------------------------------------------------------
#
# The hook runs before each Bash call. Measured: the reading of an
# interpreter costs two awk processes, about 18 ms. It can match only when
# the command names an interpreter.

@test "a command with no & and no detach word starts no awk process" {
  [ "$(awk_starts 'ls -l | sort')" -eq 0 ]
}

@test "a command that names no interpreter does not get the reading of an interpreter" {
  [ "$(awk_starts 'cd /tmp && ls 2>&1')" -eq 2 ]
  [ "$(awk_starts $'cd /tmp &&\nls 2>&1')" -eq 2 ]
}

@test "a command that names an interpreter gets both readings" {
  [ "$(awk_starts 'sudo ls && ls')" -eq 4 ]
  [ "$(awk_starts $'ls &&\nenv ls')" -eq 4 ]
  asks $'echo x &&\nbash -c "server &"'
}

# --- the control operator "&" -------------------------------------------------

@test "denies a command that ends with the background operator" {
  denies 'sleep 100 &'
  denies 'sleep 100&'
}

@test "denies the background operator before a second command" {
  denies 'server & client'
  denies '{ server & }; client'
  denies '(server &) | cat'
  denies $'server &\nclient'
}

@test "permits an & that is part of a different operator" {
  permits 'make && make test'
  permits 'make 2>&1'
  permits 'make >&2'
  permits 'make &> log'
  permits 'make &>> log'
  permits 'make |& tee log'
  permits 'exec 3<&0'
}

@test "permits an & that the shell does not execute" {
  permits 'echo "a & b"'
  permits "echo 'a & b'"
  permits 'echo a \& b'
  permits 'ls # then run it &'
  permits $'cat > notes <<\'EOF\'\nserver &\nnohup server\nEOF'
  permits 'git commit -m "tests & hooks"'
}

@test "permits parallel work that waits in the same command" {
  permits 'make a & make b & wait'
  permits $'make a &\nmake b &\nwait'
}

@test "denies a background operator that comes after the last wait" {
  denies 'make a & wait; server &'
}

@test "a wait that is only an argument does not permit the command" {
  denies 'server & echo wait'
}

@test "a wait with an argument does not permit the command" {
  denies 'a & b & wait -n'
  denies 'server & wait $other_pid'
  denies 'server & wait %1'
}

@test "a wait with an argument on a continuation line does not permit the command" {
  denies $'make a & make b & wait \\\n  $pid'
  denies $'server & wait \\\n  -n'
}

@test "a line continuation joins two lines into one command" {
  permits $'make a & make b & \\\n  wait'
  permits $'make a & make b & wa\\\nit'
  permits $'make a & \\\n  wait\nmake b'
  denies $'no\\\nhup server'
  denies $'make a & wait\\\n; server &'
  permits $'echo "a \\\n& b"'
}

@test "a wait with an empty quoted argument does not permit the command" {
  denies 'server & wait ""'
  denies "server & wait ''"
}

@test "a wait before a quote that has no end does not permit the command" {
  denies 'make a & wait "'
  denies "make a & wait '"
  denies $'make a & wait \\\n"'
}

@test "a wait next to an operator that is not a pipe permits the command" {
  permits 'make a & make b & wait || echo failed'
  permits 'make a | tee log & wait'
  permits 'make a & wait; echo x | cat'
  permits '(make a & make b & wait) | tee log'
}

@test "a wait with no argument before an operator permits the command" {
  permits 'make a & make b & wait; echo done'
  permits 'make a & make b & wait && echo done'
}

@test "a wait with a redirection and then an argument does not permit the command" {
  denies 'a & b & wait >/dev/null -n'
  denies 'a & wait >/dev/null $pid'
  denies 'a & wait </dev/null -n'
  denies 'a & wait &>/dev/null -n'
}

@test "a continued empty quoted word stays an argument of the wait" {
  denies $'server & wait ""\\\n'
  denies $'server & wait ""\\\n; true'
}

@test "a continuation after a separator keeps the last character of that separator" {
  permits $'echo $(date)\\\nnohup'
  permits $'echo x >\\\nnohup'
}

@test "a command that starts with an empty pair of parentheses is denied for its nohup" {
  denies '() { nohup server; }'
}

@test "a wait inside the same subshell collects the background operator" {
  permits '(make a) & wait'
  permits '(make a & make b & wait)'
  permits 'echo $(make a & make b & wait)'
  permits '(make a & (make b); wait)'
  permits '(make a & wait); make b & wait'
  permits '{ make a & }; wait'
}

@test "a wait after a reserved word is a command word" {
  permits 'make a & make b & if true; then wait; fi'
  permits 'make a & make b & { wait; }'
  permits $'for t in a b; do make $t & done\nwait'
  permits 'for t in a b; do make $t & done; wait'
}

# --- nohup and disown ---------------------------------------------------------

@test "denies nohup and disown as command words" {
  denies 'nohup server'
  denies 'nohup server &'
  denies 'server; disown'
  denies 'cd /tmp && nohup server'
  denies 'FOO=1 nohup server'
  denies '/usr/bin/nohup server'
  denies '"nohup" server'
  denies 'no"hu"p server'
  denies "'disown'"
  denies '(nohup server)'
}

@test "denies nohup and disown after a reserved word that starts a command" {
  denies '{ nohup server; }'
  denies 'for i in 1 2; do nohup srv; done'
  denies 'if true; then nohup server; fi'
  denies 'if false; then true; else nohup server; fi'
  denies 'if false; then true; elif nohup server; then true; fi'
  denies 'if nohup server; then true; fi'
  denies 'while nohup server; do true; done'
  denies 'until nohup server; do true; done'
  denies '! nohup server'
  denies 'time nohup server'
  denies 'if ! time FOO=1 nohup server; then true; fi'
  denies 'server; { disown; }'
}

@test "denies nohup after a reserved word that comes after a closed compound command" {
  denies 'if (true) then nohup server; fi'
  denies 'while ((i<3)) do nohup server; done'
  denies 'if (true) then true; fi; server & if (true) then echo wait; fi'
  permits 'make a & if (true) then wait; fi'
}

@test "denies coproc as a command word" {
  denies 'coproc server'
  denies 'coproc nohup server'
  denies 'make; coproc SRV { server; }'
  denies 'if true; then coproc server; fi'
  permits 'echo coproc'
  permits 'cat coproc.log'
  asks 'sudo echo coproc'
  asks 'bash -c "coproc server"'
}

@test "the deny message names coproc" {
  denies 'coproc server'
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" == *"coproc"* ]]
}

@test "permits the case terminators that hold an &" {
  permits 'case x in a) echo hi ;& b) echo ;; esac'
  permits 'case x in a) echo hi ;;& b) echo ;; esac'
  denies 'case x in a) server & ;& b) echo ;; esac'
}

@test "denies nohup in the body of a function definition" {
  denies 'f() { nohup server; }; f'
  denies 'f () { nohup server; }; f'
  denies 'function f { nohup server; }; f'
  denies 'function f() { nohup server; }; f'
  denies $'f()\n{\n  nohup server\n}\nf'
  permits 'echo $() nohup'
  permits 'f() { make a & make b & wait; }; f'
}

@test "permits a background operator in a case that a later wait collects" {
  permits 'case $x in a) make a & ;; esac; wait'
  permits '(case $x in a) make a & ;; esac; wait)'
  permits '(make a & case x in esac; wait)'
}

@test "permits nohup and disown as arguments or as the target of a redirection" {
  permits 'grep -c do nohup.out'
  permits 'echo time -p nohup'
  permits 'echo time -p -- nohup'
  permits 'echo -p nohup'
  permits 'echo -- nohup'
  permits 'grep nohup script.sh'
  permits 'echo disown'
  permits 'echo x > nohup'
  permits 'cat nohup.out'
  permits "echo 'nohup server'"
}

# --- a quoted command line that an interpreter executes -------------------------

@test "asks about a background operator inside a string that a shell executes" {
  asks 'bash -c "server &"'
  asks "sh -c 'nohup server'"
  asks $'bash <<\'EOF\'\nserver &\nEOF'
}

@test "asks, and does not deny, when only the reading with split quotes matches" {
  asks 'sudo grep -r nohup /etc'
  asks 'source .venv/bin/activate && python -c "print(3 & 1)"'
  asks $'cat > notes.txt <<\'EOF\'\nuse bash here; R&D\nEOF'
}

@test "denies a match of the shell reading also when the command names an interpreter" {
  denies 'sudo make & true'
  denies 'bash -c "make" &'
  denies 'env FOO=1 true; nohup server'
  denies $'bash <<\'EOF\'\nmake\nEOF\nserver &'
}

@test "permits a string that a shell executes when it waits for its background work" {
  permits 'bash -c "make a & make b & wait"'
}

# --- the stated limits ----------------------------------------------------------
#
# Each test pins a limit that the header of the hook states. A change of the
# limit must show as a failure here. The false denies come first, then the
# escapes.

@test "limit: a wait after an option of the reserved word time is denied" {
  denies 'make a & time -p wait'
  denies 'make a & time -p -- wait'
}

@test "limit: a wait after the pattern of a case is denied" {
  denies 'make a & case $x in a) wait;; esac'
}

@test "limit: a wait that names each job is denied" {
  denies 'make a & wait %1'
}

@test "limit: a detach word that is only data behind an interpreter makes the hook ask" {
  asks 'sudo grep -r nohup /etc'
}

@test "limit: nohup after a reserved word that is only an argument is denied" {
  denies 'echo then nohup'
  denies 'echo { nohup server'
  denies 'echo time nohup'
  denies 'echo $(date) then nohup'
  denies 'echo function f { nohup server'
}

@test "limit: a wait after a reserved word that is only an argument collects" {
  permits 'server & echo then wait'
}

@test "limit: a wait that is an element of a pipeline collects" {
  permits 'server & wait | cat'
  permits 'server & echo x | wait'
  permits 'server & wait |& cat'
  permits $'server & echo x |\n  wait'
  permits 'server & echo x | FOO=1 wait'
  permits $'server & make a |\\\nwait'
  permits $'server & echo x | wa\\\nit'
  permits $'server & echo x | FOO=1 \\\nwait'
  permits $'server & wait \\\n| cat'
  permits 'server & { wait; } | cat'
  permits 'server & echo x | { wait; }'
  permits 'server & echo x | time wait'
  denies 'server & wait > log | cat'
}

@test "limit: a wait outside a subshell collects a background operator inside it" {
  permits '(server &); wait'
  permits 'echo $(server &); wait'
  permits 'x=$(server &); wait'
  permits '(make a & (make b &); wait)'
  permits '(make a &) & wait'
  permits '(server & case x in esac); wait'
  permits $'(server & case\\\ns); wait'
  permits '(case $x in a) true;; esac; server &); wait'
  permits 'echo `server &`; wait'
}

@test "limit: a wait inside a subshell collects a background operator outside it" {
  permits '(make a &); (wait)'
  permits 'make a & (wait)'
}

@test "limit: a wait in a branch or in a function that does not run collects" {
  permits 'server & if false; then wait; fi'
  permits 'server & f() { wait; }'
}

@test "limit: nohup after the pattern of a case is permitted" {
  permits 'case $x in a) nohup server;; esac'
  permits $'case $x in\n  a) true;;\n  b|c) nohup server;;\nesac'
  permits 'case $x in (a) nohup server;; esac'
}

@test "limit: nohup after an option of the reserved word time is permitted" {
  permits 'time -p nohup server'
  permits 'time -p FOO=1 nohup server'
  permits 'time -p -- nohup server'
  permits 'time -- nohup server'
  permits 'time -p -- FOO=1 nohup server'
}

@test "limit: an & in a double-quoted substitution is permitted" {
  permits 'echo "$(server &)"'
}

@test "limit: a process that an interpreter other than a shell starts is permitted" {
  permits 'python3 -c "import subprocess; subprocess.Popen([\"server\"])"'
}

@test "limit: an arithmetic & outside quotes is denied" {
  denies 'echo $((flags & 1))'
}

@test "limit: an & in a parameter expansion is denied" {
  denies 'echo ${url//&/%26}'
}

@test "limit: an & in the body of a heredoc that the shell expands is denied" {
  denies $'cat > f <<EOF\nHello $(whoami) & friends\nEOF'
  denies $'cat > f <<EOF\nHello ${USER} & friends\nEOF'
  denies $'cat > f <<EOF\nHello `whoami` & friends\nEOF'
  permits $'cat > f <<EOF\na & b\nnohup is a word\nEOF'
  permits $'cat > f <<\'EOF\'\nHello $(whoami) & friends\nEOF'
}

@test "limit: a wait with an argument from a backquote substitution collects" {
  permits 'a & b & wait `printf %s -n`'
  permits 'a & wait `cat pidfile`'
  denies 'a & wait $(cat pidfile)'
}

@test "limit: nohup behind a program that is not an interpreter is permitted" {
  permits 'nice nohup server'
}

@test "limit: a wait with a redirection is denied" {
  denies 'make a & make b & wait 2>/dev/null'
  denies 'make a & make b & wait > log'
  denies 'make a & wait >| log'
  denies 'make a & wait < /dev/null'
}

@test "limit: a wait before an operator and then a redirection is denied" {
  denies 'make a & wait; > log echo done'
}

@test "limit: a wait after a string that an interpreter executes collects its background operator" {
  permits 'bash -c "server &"; wait'
}

@test "limit: a wait before a backslash that ends the command collects" {
  permits 'make a & wait \'
}

@test "the hook asks about nohup behind a prefix that is in SHELL_FEEDS" {
  asks 'sudo nohup server'
  asks 'env nohup server'
}

# --- laws ---------------------------------------------------------------------

SEEDS="1 2 3 5 8 13 21 34 55 89"

# safe_command <seed>
#
# Prints a command of 2 to 6 simple commands with operators that start
# nothing in the background.
safe_command() {
  local words=(make "ls -l" "grep -r x ." "cat file" "echo done" true)
  local joins=(" && " " || " " ; " " | " " 2>&1 | ")
  local count i out
  RANDOM=$1
  count=$((RANDOM % 5 + 2))
  out="${words[RANDOM % ${#words[@]}]}"
  for ((i = 1; i < count; i++)); do
    out+="${joins[RANDOM % ${#joins[@]}]}${words[RANDOM % ${#words[@]}]}"
  done
  printf '%s' "$out"
}

@test "law: a command with no background operator, nohup, or disown is permitted" {
  local seed
  for seed in $SEEDS; do permits "$(safe_command "$seed")"; done
}

@test "law: a background operator after a permitted command makes it denied" {
  local seed
  for seed in $SEEDS; do denies "$(safe_command "$seed") & true"; done
}

@test "law: quotes around the denied token make the command permitted" {
  local seed
  for seed in $SEEDS; do
    permits "$(safe_command "$seed") \"&\" true"
    permits "$(safe_command "$seed") ; echo 'nohup'"
  done
}

# The parts of a generated command. A record is "<attribute>|<rule>|<text>".
#
# The attribute is what the part does to the one sequence that the rule
# reads:
#
#   detach      The part holds nohup, disown, or coproc in the command
#               position. The command is denied.
#   background  The part holds a background operator with no bare wait
#               after it.
#   wait        The part ends with a bare wait. It collects each
#               background operator before it.
#   collect     The part holds a bare wait before its end. It collects
#               also.
#   none        The part does nothing of these.
#
# The rule is the rule of the hook that the part exercises. The name of a
# rule about a wait holds "wait". The records with a wait that collects
# nothing start at FIRST_WAIT. The records with "wait" or "collect" start at
# FIRST_COLLECT. The records with "detach" start at FIRST_DETACH and are the
# last ones.
PARTS=(
  "none|plain|make"
  "none|plain|while false; do make; done"
  "none|plain|case x in a) make;; esac"
  "none|detach_word_as_argument|echo nohup"
  "none|detach_word_as_argument|echo 'disown'"
  "none|detach_word_as_argument|echo coproc"
  "none|detach_word_as_argument|echo time -p nohup"
  "none|redirection_target|echo x > nohup"
  "none|program_before_detach|nice nohup make"
  "none|time_option_before_detach|time -p nohup make"
  "none|time_option_before_detach|time -- nohup make"
  "none|case_pattern_before_detach|case x in a) nohup make;; esac"
  "none|case_pattern_before_detach|case x in *) disown;; esac"
  'none|quoted_ampersand|echo "&"'
  "none|other_ampersand_operator|make 2>&1"
  "none|other_ampersand_operator|make &> log"
  "none|other_ampersand_operator|case x in a) make ;& b) make ;;& c) make;; esac"
  "background|background_in_group|{ make & }"
  "background|background_in_group|if true; then make & fi"
  "none|wait_as_argument|echo wait"
  "none|wait_as_argument|echo make wait"
  "none|argument_wait|wait -n"
  'none|argument_wait|wait $pid'
  "none|argument_wait|wait %1"
  'none|empty_argument_wait|wait ""'
  "none|empty_argument_wait|wait ''"
  "none|redirection_wait|wait > log"
  "none|redirection_wait|wait >/dev/null -n"
  "none|time_option_before_wait|time -p wait"
  "none|case_pattern_before_wait|case x in a) wait;; esac"
  "none|redirection_after_wait_separator|wait; > log echo x"
  "wait|simple_wait|wait"
  "wait|assignment_before_wait|FOO=1 wait"
  "wait|reserved_word_before_wait|time wait"
  "collect|reserved_word_before_wait|if true; then wait; fi"
  "collect|reserved_word_before_wait|{ wait; }"
  "collect|reserved_word_as_argument_before_wait|echo then wait; make"
  "detach|detach_command_word|nohup make"
  "detach|detach_command_word|disown"
  "detach|path_before_detach|/usr/bin/nohup make"
  "detach|assignment_before_detach|FOO=1 nohup make"
  "detach|coproc_command_word|coproc make"
  "detach|coproc_command_word|coproc SRV { make; }"
  'detach|quoted_command_word|"nohup" make'
  "detach|quoted_command_word|'disown'"
  "detach|reserved_word_before_detach|if true; then nohup make; fi"
  "detach|reserved_word_before_detach|{ nohup make; }"
  "detach|reserved_word_before_detach|time nohup make"
  "detach|reserved_word_before_detach|for i in 1 2; do disown; done"
  "detach|reserved_word_before_detach|! nohup make"
  "detach|reserved_word_before_detach|if (true) then nohup make; fi"
  "detach|reserved_word_before_detach|f() { nohup make; }"
  "detach|else_before_detach|if false; then make; else nohup make; fi"
  "detach|elif_before_detach|if false; then make; elif nohup make; then make; fi"
  "detach|while_before_detach|while nohup make; do make; done"
  "detach|until_before_detach|until disown; do make; done"
  "detach|reserved_word_as_argument_before_detach|echo then nohup"
)
FIRST_WAIT=19
FIRST_COLLECT=31
FIRST_DETACH=37
# The count of the first "detach" records that start with the detach word.
LEADING_DETACH=8

# The oracle value of each part comes from THE RULE in the header of the
# hook, not from a run of the hook:
#
#   wait; > log echo x   The token after the wait is the separator "; >". It
#                        holds a ">". Part 1 of the rule calls that wait not
#                        bare, so the part collects nothing: "none".
#   else, elif, while,   Part 3 of the rule names each of these reserved
#   until                words. The word directly after it is in the command
#                        position. Part 2 denies a detach word there:
#                        "detach".

# Each rule that the generator must reach. The first two lines hold the
# rules that random_command records itself. The other rules come from PARTS.
LAW_RULES="uncollected_at_end pipeline_wait wait_in_other_subshell
  detach_after_newline detach_after_or
  detach_word_as_argument redirection_target program_before_detach
  time_option_before_detach case_pattern_before_detach quoted_ampersand
  other_ampersand_operator background_in_group wait_as_argument argument_wait
  empty_argument_wait redirection_wait time_option_before_wait
  case_pattern_before_wait redirection_after_wait_separator
  else_before_detach elif_before_detach while_before_detach until_before_detach
  simple_wait assignment_before_wait
  reserved_word_before_wait reserved_word_as_argument_before_wait
  detach_command_word path_before_detach assignment_before_detach
  coproc_command_word quoted_command_word reserved_word_before_detach
  reserved_word_as_argument_before_detach"

# decisive_rules <attribute> <rule> <piped> <pending> <other-subshell>
#
# Sets DECIDED to each rule that can decide the verdict at the selected
# part. random_command counts it only when the parts after it leave the
# decision to this part. See RULES there.
# A rule about a wait decides only when a background operator is pending.
# The rule of the hook reads one sequence. Thus a wait that is an element
# of a pipeline collects, and a wait in a different subshell collects also.
# Each of the two is a rule here. The result is a variable, because a
# command substitution for each part makes the coverage law slow.
decisive_rules() {
  local attribute=$1 rule=$2 piped=$3 pending=$4 other_subshell=$5
  if [[ "$rule" != *wait* ]]; then
    DECIDED=" $rule"
  elif ((pending)); then
    DECIDED=" $rule"
    if [ "$attribute" = wait ] && ((piped)); then DECIDED+=" pipeline_wait"; fi
    if [ "$attribute" != none ] && ((other_subshell)); then DECIDED+=" wait_in_other_subshell"; fi
  else
    DECIDED=""
  fi
}

# join_rule <join-before> <rule>
#
# Sets JOINED to the rule of the join that puts a detach word in the command
# position, or to "". Only a part that starts with its detach word gets its
# command position from the join before it. THE RULE of the hook, part 3: a
# word after a newline is in the command position, and a word after "|" also.
# The last character of "||" is "|".
join_rule() {
  JOINED=""
  case "$2" in
    detach_command_word | path_before_detach | assignment_before_detach | coproc_command_word | quoted_command_word)
      case "$1" in
        $'\n') JOINED=" detach_after_newline" ;;
        " || ") JOINED=" detach_after_or" ;;
        *) ;;
      esac
      ;;
    *) ;;
  esac
}

# random_command <seed>
#
# Prints a command of 1 to 6 parts, and sets EXPECTED to "deny" or "permit"
# from the rule. The parts and the joins hold each token that the rule
# names, in the command position and in the argument position, quoted and
# not quoted, and after a reserved word. A part can be in a subshell. The
# oracle reads only the attributes of each part, never the hook. Call it
# with a redirection, or the variables are lost. It sets these variables
# also:
#
#   BACKGROUND       1 when the command holds a background operator.
#   RULES            The rules of LAW_RULES that decide the verdict. A part
#                    with no effect, such as "echo nohup", counts only when
#                    the command is permitted: in a denied command, a deny
#                    of that part changes nothing. A rule about a wait
#                    counts only when no later part collects. A later wait
#                    collects the same background operator, so the wait
#                    before it decides nothing. A join counts when the part
#                    after it starts with a detach word.
#   MENTIONS         1 when a part holds a detach word that is only data.
#                    The reading of an interpreter matches that word.
#   SPLIT_SENSITIVE  1 when a part holds a quoted "&" or an empty quoted
#                    argument. Quotes that split words change such a part.
#
# The oracle is the rule: one flag for a pending background operator, and
# one flag for a detach part. A subshell and a pipe change neither flag.
# The oracle follows them only to know which rule decides.
#
# The generator selects a "detach" part for one part in five, so a
# sufficient number of commands stay permitted. For the same reason, one
# part in two after a background operator is a part that collects. Three
# parts in eight there are a wait that collects nothing, so the rules about
# such a wait decide in a sufficient number of commands. One command in
# eight ends with a background operator.
#
# The oracle value of each join comes from THE RULE also. "&&" and "||"
# hold no background operator: an "&" inside "&&" is a different operator,
# and "||" holds no "&". A newline, ";", and "|" end a command, so the first
# word of the next part is in the command position. None of the joins holds
# a "<" or a ">", so a wait before a join is bare. Only "&" sets the flag
# for a pending background operator.
random_command() {
  local joins=(" && " " || " " ; " $'\n' " | " " |& " " & ")
  local collect_count=$((FIRST_DETACH - FIRST_COLLECT)) detach_count=$((${#PARTS[@]} - FIRST_DETACH))
  local count i pick join trailing closes piped out="" denied=0 inside=0
  local after_background=0 after_pipe=0 pending=0 subshell=0 subshells=0 origin=0
  local attribute rule text before="" harmless="" waits=""
  RANDOM=$1
  BACKGROUND=0; RULES=""; MENTIONS=0; SPLIT_SENSITIVE=0
  count=$((RANDOM % 6 + 1))
  for ((i = 0; i < count; i++)); do
    piped=$after_pipe; after_pipe=0
    # After "(", the parenthesis gives the command position, not the join.
    if ((!inside)) && ((RANDOM % 4 == 0)); then out+="( "; inside=1; subshell=$((++subshells)); piped=0; before=""; fi
    pick=$((RANDOM % FIRST_DETACH))
    ((RANDOM % 5 == 0)) && pick=$((FIRST_DETACH + RANDOM % detach_count))
    # One part in four after a newline or "||" starts with a detach word.
    # Thus the two joins decide the verdict in a sufficient number of commands.
    if { [ "$before" = $'\n' ] || [ "$before" = " || " ]; } && ((RANDOM % 4 == 0)); then
      pick=$((FIRST_DETACH + RANDOM % LEADING_DETACH))
    fi
    if ((after_background)); then
      case $((RANDOM % 8)) in
        0 | 1 | 2 | 3) pick=$((FIRST_COLLECT + RANDOM % collect_count)) ;;
        4 | 5 | 6) pick=$((FIRST_WAIT + RANDOM % (FIRST_COLLECT - FIRST_WAIT))) ;;
        *) ;;
      esac
    fi
    after_background=0
    IFS='|' read -r attribute rule text <<< "${PARTS[pick]}"
    out+="$text"
    if [ "$attribute" != detach ] && [[ "$text" =~ nohup|disown|coproc ]]; then MENTIONS=1; fi
    case "$rule" in
      quoted_ampersand | empty_argument_wait) SPLIT_SENSITIVE=1 ;;
      *) ;;
    esac
    # The oracle must know what comes after the part before it reads the
    # attribute. Thus it selects the end of the subshell and the join first.
    closes=0; trailing=""; join=""
    if ((inside)) && { ((i == count - 1)) || ((RANDOM % 2 == 0)); }; then
      closes=1
      if ((RANDOM % 4 == 0)); then trailing=" &"; fi
    fi
    if ((i < count - 1)) || ((RANDOM % 8 == 0)); then
      join="${joins[RANDOM % ${#joins[@]}]}"
      ((i < count - 1)) || join=" &"
    fi
    if ((!closes)) && { [ "$join" = " | " ] || [ "$join" = " |& " ]; }; then piped=1; fi
    decisive_rules "$attribute" "$rule" "$piped" "$pending" "$((origin != subshell))"
    # A part that collects replaces the wait rules before it, because it
    # collects the same background operator.
    case "$attribute:$rule" in
      wait:* | collect:*) waits="$DECIDED" ;;
      none:*wait*) waits+="$DECIDED" ;;
      none:*) harmless+="$DECIDED" ;;
      detach:*) join_rule "$before" "$rule"; RULES+="$DECIDED$JOINED" ;;
      *) RULES+="$DECIDED" ;;
    esac
    case "$attribute" in
      detach) denied=1 ;;
      wait | collect) pending=0 ;;
      background) pending=1; origin=$subshell; BACKGROUND=1; after_background=1 ;;
      *) ;;
    esac
    # The end of a subshell. A background operator inside it stays pending.
    if ((closes)); then
      if [ -n "$trailing" ]; then out+="$trailing"; pending=1; origin=$subshell; BACKGROUND=1; after_background=1; fi
      out+=" )"; inside=0; subshell=0
    fi
    out+="$join"; before="$join"
    if [ "$join" = " & " ] || [ "$join" = " &" ]; then
      pending=1; origin=$subshell; BACKGROUND=1; after_background=1
    fi
    if [ "$join" = " | " ] || [ "$join" = " |& " ]; then after_pipe=1; fi
  done
  RULES+="$waits"
  if ((pending)); then denied=1; RULES+=" uncollected_at_end"; fi
  EXPECTED=permit; ((denied)) && EXPECTED=deny
  if [ "$EXPECTED" = permit ]; then RULES+="$harmless"; fi
  printf '%s' "$out"
}

# The coverage law starts no hook, so it reads LAW_SEEDS commands. A law
# that starts the hook for each command reads HOOK_SEEDS of them.
LAW_SEEDS=600
HOOK_SEEDS=80

@test "law: the hook denies exactly the commands that the rule names" {
  local seed file; file="$(fixture_dir)/command"
  for seed in $(seq 1 "$HOOK_SEEDS"); do
    random_command "$seed" > "$file"
    if [ "$EXPECTED" = "deny" ]; then denies "$(cat "$file")"; else permits "$(cat "$file")"; fi
  done
}

@test "law: a line continuation at each blank does not change the verdict" {
  local seed file command; file="$(fixture_dir)/command"
  for seed in $(seq 1 60); do
    random_command "$seed" > "$file"
    command="$(cat "$file")"
    command="${command// / $'\\\n'}"
    if [ "$EXPECTED" = "deny" ]; then denies "$command"; else permits "$command"; fi
  done
}

@test "law: the generated commands reach each rule of the law where it decides the verdict" {
  local seed file denied=0 permitted=0 collected=0 rule; file="$(fixture_dir)/command"
  local -A reached=()
  for seed in $(seq 1 "$LAW_SEEDS"); do
    random_command "$seed" > "$file"
    for rule in $RULES; do reached[$rule]=$((${reached[$rule]:-0} + 1)); done
    if [ "$EXPECTED" = "deny" ]; then denied=$((denied + 1)); else permitted=$((permitted + 1)); fi
    if [ "$EXPECTED" = "permit" ] && [ "$BACKGROUND" -eq 1 ]; then collected=$((collected + 1)); fi
  done
  [ "$denied" -ge 40 ]
  [ "$permitted" -ge 40 ]
  [ "$collected" -ge 10 ]
  for rule in $LAW_RULES; do
    [ "${reached[$rule]:-0}" -ge 5 ] || { echo "rule $rule decides in ${reached[$rule]:-0} commands"; return 1; }
  done
}

@test "law: each part of the generator names a rule that the coverage law reads" {
  local record attribute rule text known found
  for record in "${PARTS[@]}"; do
    IFS='|' read -r attribute rule text <<< "$record"
    found=0
    for known in $LAW_RULES plain; do if [ "$known" = "$rule" ]; then found=1; fi; done
    [ "$found" -eq 1 ] || { echo "no law rule: $rule ($attribute, $text)"; return 1; }
  done
}

@test "law: each part of the generator is in the group of its attribute" {
  local index attribute rule text group
  for index in "${!PARTS[@]}"; do
    IFS='|' read -r attribute rule text <<< "${PARTS[index]}"
    group="none background"
    if ((index >= FIRST_DETACH)); then group=detach
    elif ((index >= FIRST_COLLECT)); then group="wait collect"; fi
    [[ " $group " == *" $attribute "* ]] || { echo "part $index ($text, $rule) is not in: $group"; return 1; }
    if ((index >= FIRST_WAIT)) && ((index < FIRST_DETACH)); then [[ "$rule" == *wait* ]]; else [[ "$rule" != *wait* ]]; fi
    # Exactly the first LEADING_DETACH records of "detach" get a join rule.
    join_rule " || " "$rule"
    if ((index >= FIRST_DETACH)) && ((index < FIRST_DETACH + LEADING_DETACH)); then [ -n "$JOINED" ]; else [ -z "$JOINED" ]; fi
  done
}

@test "law: each part of the generator alone gets the verdict of its attribute" {
  local record attribute rule text
  for record in "${PARTS[@]}"; do
    IFS='|' read -r attribute rule text <<< "$record"
    case "$attribute" in
      detach | background) denies "$text" ;;
      *) permits "$text" ;;
    esac
  done
}

@test "law: each part of the generator after a background operator gets the verdict of its attribute" {
  local record attribute rule text
  for record in "${PARTS[@]}"; do
    IFS='|' read -r attribute rule text <<< "$record"
    case "$attribute" in
      wait | collect) permits "make & $text" ;;
      *) denies "make & $text" ;;
    esac
  done
}

# interpreter_command <seed>
#
# Prints a generated command, then a string that an interpreter executes,
# and sets EXPECTED to "deny", "ask", or "permit". The string is the last
# part: a wait after it can collect its "&", which is a stated limit. The
# oracle: deny when the outer command denies. If not, ask when the string
# or a data word of the outer command holds a denied token. One seed in
# four has a safe command as the outer command. Each form names one or two
# words of SHELL_FEEDS, and no string holds a quote.
interpreter_command() {
  local strings=(
    "permit|make" "permit|make a && make b" "permit|echo done | cat"
    "permit|make a & make b & wait" "permit|(make a & wait); make b"
    "permit|(server &); wait" "permit|server & wait | cat"
    "ask|server &" "ask|make a & wait -n" "ask|server & wait > log"
    "ask|nohup server" "ask|server; disown"
    "ask|coproc server" "ask|echo nohup"
  )
  local forms=(
    'bash -c "%s"' "sh -c '%s'" 'zsh -c "%s"' 'eval "%s"' "eval '%s'"
    "ssh host '%s'" 'su -c "%s"' "sudo bash -c '%s'" 'env FOO=1 sh -c "%s"'
  )
  local joins=(" ; " " && ")
  local inner_verdict string
  if (($1 % 4 == 0)); then
    safe_command "$1"; EXPECTED=permit; MENTIONS=0; SPLIT_SENSITIVE=0
  else
    random_command "$1"
  fi
  IFS='|' read -r inner_verdict string <<< "${strings[RANDOM % ${#strings[@]}]}"
  FORM="${forms[RANDOM % ${#forms[@]}]}"
  # shellcheck disable=SC2059 # The form is a printf format from the list above.
  printf "${joins[RANDOM % 2]}${FORM}" "$string"
  if [ "$EXPECTED" = permit ] && { ((MENTIONS)) || [ "$inner_verdict" = ask ]; }; then EXPECTED=ask; fi
}

# The oracle does not model quotes that split words in the outer command.
# Thus the law does not read a command with SPLIT_SENSITIVE set. The limit
# on the count of those seeds keeps the skip from growth with no notice.
# The fixed tests after the law read outer commands of the skipped kind.
@test "law: a generated string that an interpreter executes gives deny, then ask, then permit" {
  local seed file command denied=0 asked=0 permitted=0 skipped=0; file="$(fixture_dir)/command"
  local -A used=()
  for seed in $(seq 1 "$HOOK_SEEDS"); do
    interpreter_command "$seed" > "$file"
    if ((SPLIT_SENSITIVE)); then skipped=$((skipped + 1)); continue; fi
    used[${FORM%% *}]=1
    command="$(cat "$file")"
    case "$EXPECTED" in
      deny) denies "$command"; denied=$((denied + 1)) ;;
      ask) asks "$command"; asked=$((asked + 1)) ;;
      *) permits "$command"; permitted=$((permitted + 1)) ;;
    esac
  done
  echo "denied $denied, asked $asked, permitted $permitted, skipped $skipped, forms ${!used[*]}"
  [ "$denied" -ge 10 ]
  [ "$asked" -ge 10 ]
  [ "$permitted" -ge 5 ]
  [ "$skipped" -le 20 ]
  [ "${#used[@]}" -eq 8 ]
}

# The generated law above skips each outer command with a quoted "&" or with
# an empty quoted argument of a wait, because its oracle does not model
# quotes that split words. These fixed tests read such outer commands behind
# an interpreter. Each verdict comes from the header of the hook:
#
#   echo "&"       The shell does not execute a quoted "&", so no deny. The
#                  reading of an interpreter splits the quotes. Then the "&"
#                  is a background operator with no wait after it: ask.
#   & wait ""      In the reading of the shell, the empty quoted word is an
#                  argument, so the wait is not bare: deny. That reading has
#                  no override.
#   '...&'; wait ""   The shell reads no background operator. With split
#                  quotes, the "&" of the string is an operator, and the
#                  quotes of the empty word are only word boundaries. Thus
#                  the wait is bare and collects: permit.
@test "an interpreter before a quoted & makes the hook ask" {
  asks 'bash -c "make" ; echo "&"'
  asks 'echo "&" && sudo make'
  asks "sh -c 'make' ; echo '&' ; wait -n"
}

@test "an interpreter before a wait with an empty quoted argument does not change the deny" {
  denies 'bash -c "make" ; make a & wait ""'
  denies "sudo make && make a & wait ''"
}

@test "limit: a wait with an empty quoted argument collects the & of a string that an interpreter executes" {
  permits "sh -c 'make a &' ; wait \"\""
  permits 'bash -c "make a &" ; wait '"''"
}

@test "law: a denied command inside a string that a shell executes makes the hook ask" {
  local seed
  for seed in $SEEDS; do
    asks "bash -c '$(safe_command "$seed") & true'"
    asks "sh -c '$(safe_command "$seed") ; nohup make'"
    permits "bash -c '$(safe_command "$seed")'"
    permits "bash -c '$(safe_command "$seed") & wait'"
  done
}

@test "law: an interpreter word never turns a denied command into a question" {
  local seed
  for seed in $SEEDS; do
    denies "sudo true ; $(safe_command "$seed") & true"
    denies "env true ; nohup $(safe_command "$seed")"
  done
}

@test "law: the two masks agree when the command names no interpreter" {
  # shellcheck source=../../hooks/lib/shell-command.sh disable=SC1091
  source "${HOOKS_DIR}/lib/shell-command.sh"
  local seed command
  for seed in $SEEDS; do
    command="cat > notes <<'EOF'"$'\n'"$(safe_command "$seed") & # note"$'\n'"EOF"$'\n'"$(safe_command "$seed") # done &"
    [ "$(mask_shell_reading "$command")" = "$(mask_nonexecuting "$command")" ]
  done
}

@test "law: the mask of the shell reading keeps no body of a quoted heredoc" {
  # shellcheck source=../../hooks/lib/shell-command.sh disable=SC1091
  source "${HOOKS_DIR}/lib/shell-command.sh"
  local seed body
  for seed in $SEEDS; do
    body="$(safe_command "$seed") & bash"
    [ "$(mask_shell_reading "cat > notes <<'EOF'"$'\n'"$body"$'\n'"EOF")" = "cat > notes <<'EOF'"$'\n'"EOF" ]
    [ "$(mask_nonexecuting "cat > notes <<'EOF'"$'\n'"$body"$'\n'"EOF")" = "cat > notes <<'EOF'"$'\n'"$body"$'\n'"EOF" ]
  done
}

# --- the message and the payload ------------------------------------------------

@test "the question names the interpreter and gives the same two routes" {
  asks 'bash -c "server &"'
  local reason
  reason="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
  [[ "$reason" == *"interpreter"* ]]
  [[ "$reason" == *"quoted string"* ]]
  [ -x "$(printf '%s' "$reason" | grep -o '/[^ ]*background-run\.sh' | head -n 1)" ]
  [ -x "$(printf '%s' "$reason" | grep -o '/[^ ]*background-watch\.sh' | head -n 1)" ]
  [[ "$reason" == *"wait"* ]]
}

@test "a new word in DETACH_WORDS reaches the verdict and the two messages with no other edit" {
  local script='source "$1"; DETACH_WORDS="$DETACH_WORDS setsid"; main'
  run bash -c "$script" _ "$HOOK" <<< "$(payload 'setsid server')"
  [ "$(decision)" = "deny" ]
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" == *"setsid"* ]]
  run bash -c "$script" _ "$HOOK" <<< "$(payload 'sudo echo setsid')"
  [ "$(decision)" = "ask" ]
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" == *"setsid"* ]]
}

@test "the hook finds its library when its path holds no slash" {
  cd "$HOOKS_DIR"
  run bash deny-untracked-background.sh <<< "$(payload 'sleep 100 &')"
  [ "$status" -eq 0 ]
  [ "$(decision)" = "deny" ]
}

@test "the deny message does not tell about a subshell, which the rule does not follow" {
  denies 'sleep 100 &'
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" != *"subshell"* ]]
}

@test "the deny message tells that the wait must have no argument" {
  denies 'sleep 100 &'
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" == *"wait command with no argument"* ]]
}

@test "the deny message gives the absolute path of the wrapper and of the watcher" {
  denies 'sleep 100 &'
  local reason wrapper watcher
  reason="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
  wrapper="$(printf '%s' "$reason" | grep -o '/[^ ]*background-run\.sh' | head -n 1)"
  watcher="$(printf '%s' "$reason" | grep -o '/[^ ]*background-watch\.sh' | head -n 1)"
  [ -x "$wrapper" ]
  [ -x "$watcher" ]
}

@test "a payload with no command, or one that the hook cannot parse, is permitted" {
  run_hook "$HOOK" '{"tool_input": {}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run_hook "$HOOK" 'not json'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run_hook "$HOOK" ''
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
