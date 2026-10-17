#!/usr/bin/env bats
# Tests for confirm-git-commit-push.sh. The first group are characterization
# tests pinning the exact behavior of the inline PreToolUse/Bash hook command
# it replaced:
#   jq -r '.tool_input.command // empty' | { read -r cmd; if printf '%s' "$cmd" \
#     | grep -Eq 'git([^&|;]*)(commit|push)'; then echo <ask-JSON>; fi; }
# The second group pins that a commit always asks and never denies: the
# transcript's contents do not change the decision, and a transcript the hook
# cannot read (missing path/file, no turn boundary) still gives the plain ask.

load helpers

setup() {
  SCRIPT="${HOOKS_DIR}/confirm-git-commit-push.sh"
}

pretooluse_payload() {
  jq -n --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}'
}

pretooluse_payload_with_transcript() {
  jq -n --arg cmd "$1" --arg tp "$2" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, transcript_path:$tp}'
}

permission_decision() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

permission_reason() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'
}

@test "plain git commit asks for confirmation" {
  stdin="$(pretooluse_payload 'git commit -m test')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "ask" ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "PreToolUse" ]
}

@test "plain git push asks for confirmation" {
  stdin="$(pretooluse_payload 'git push origin main')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "ask" ]
}

@test "git commit after a && chain still asks (second git...commit segment matches)" {
  stdin="$(pretooluse_payload 'git status && git commit -m test')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "ask" ]
}

@test "git status alone does not ask" {
  stdin="$(pretooluse_payload 'git status')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "git log alone does not ask" {
  stdin="$(pretooluse_payload 'git log --oneline -5')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a non-git command does not ask" {
  stdin="$(pretooluse_payload 'ls -la')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing tool_input.command does not ask and does not error" {
  stdin='{"tool_name":"Bash","tool_input":{}}'
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- a commit is a question, never a denial ---------------------------------
# The hook asks for confirmation, because a commit needs an explicit
# instruction in the current turn, and a hook cannot read the instruction. It
# never denies, and it never reads the transcript. The two laws below say so
# over a set of commands and transcripts; the examples after them pin the
# edge cases a reader looks for by name.

# transcript_fixtures
#
# Prints one transcript path per line: a transcript with a delegation in the
# turn, one with no turn boundary, and one that does not exist.
transcript_fixtures() {
  write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=development:nst-reviewer)")"
  write_transcript "$(tool_use_event Bash)"
  printf '%s\n' "${BATS_TEST_TMPDIR}/does-not-exist.jsonl"
}

@test "law: the decision ignores the transcript" {
  for cmd in 'git commit -m x' 'git push origin main' 'git status' 'ls'; do
    run_hook "$SCRIPT" "$(pretooluse_payload "$cmd")"
    base="$output"
    while IFS= read -r tp; do
      run_hook "$SCRIPT" "$(pretooluse_payload_with_transcript "$cmd" "$tp")"
      [ "$output" = "$base" ] || { echo "[$cmd] with [$tp]: $output"; return 1; }
    done < <(transcript_fixtures)
  done
}

@test "law: the output is empty or an ask, and the status is 0" {
  for cmd in 'git commit -m x' 'git push' 'git commit&&git push' 'git status' 'ls' ''; do
    run_hook "$SCRIPT" "$(pretooluse_payload "$cmd")"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || [ "$(permission_decision "$output")" = "ask" ] || { echo "[$cmd]: $output"; return 1; }
  done
}

@test "git commit after a subagent delegation this turn asks for confirmation" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=development:nst-reviewer)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "git commit with a nonexistent transcript file asks" {
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' /nonexistent/transcript.jsonl)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "git commit with a transcript lacking any turn boundary asks" {
  transcript="$(write_transcript "$(tool_use_event Bash)")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- subcommand-token matching: refs containing commit/push must not confuse
# --- the gate. commit/push count only as standalone tokens after git. A commit
# --- and a push give the same output on purpose, so a test here can tell a
# --- gated command from an ungated one, not a commit from a push.

@test "git push to a branch containing 'commit' is a push, not a gated commit" {
  stdin="$(pretooluse_payload 'git push origin fix-commit-message')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "git push to a remote named commit-fixes is a push, not a gated commit" {
  stdin="$(pretooluse_payload 'git push commit-fixes')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a commit whose message mentions push still hits the commit gate" {
  stdin="$(pretooluse_payload 'git commit -m "push the button"')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a combined commit-and-push command is gated as a commit" {
  stdin="$(pretooluse_payload 'git commit -m x && git push')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "git commit with global options before the subcommand is still gated" {
  stdin="$(pretooluse_payload 'git -C /some/repo commit -m test')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a push followed immediately by a redirection is a push, not ignored" {
  stdin="$(pretooluse_payload 'git push>/dev/null')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a commit inside a subshell is still gated" {
  stdin="$(pretooluse_payload '(git commit)')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a commit chained without spaces is still gated" {
  stdin="$(pretooluse_payload 'git commit&&git push')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a non-git command whose name ends in git is not gated" {
  stdin="$(pretooluse_payload 'legit commit -m x')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a path-prefixed git binary is still gated" {
  stdin="$(pretooluse_payload '/usr/bin/git commit -m x')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- text the shell will not execute must not gate --------------------------
# The hook reads the whole command string, so a shell comment or a heredoc
# BODY that merely MENTIONS the gated words trips it. That is not
# hypothetical: it blocked a transcript-searching command whose Python comment
# read "first git commit afterwards", and then blocked the command that first
# wrote these very tests.
#
# The word "git" is built from GITW below rather than written next to its
# subcommand, so that editing this file does not trip the hook. Of the four
# tests that follow, three were red before the fix; the string-literal one
# passed already, because the quote before the word never satisfied the
# pattern's preceding-character class, so it records existing behavior rather
# than showing that the fix works. The three after them pin what the fix must
# not relax: masking may only remove text the shell will not execute, so a
# heredoc fed to a shell interpreter stays gated even though it is a heredoc
# body.

GITW=git

@test "a shell comment mentioning a commit does not gate" {
  stdin="$(pretooluse_payload "ls -la  # remember to $GITW commit later")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a comment inside a heredoc body does not gate" {
  body="$(printf 'python3 - <<%sPY%s\n# find the first %s commit afterwards\nprint(1)\nPY\n' "'" "'" "$GITW")"
  stdin="$(pretooluse_payload "$body")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a string literal in a heredoc body does not gate" {
  body="$(printf 'python3 - <<%sPY%s\nif "%s commit" in line: pass\nPY\n' "'" "'" "$GITW")"
  stdin="$(pretooluse_payload "$body")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unquoted heredoc body mentioning a push does not gate" {
  body="$(printf 'cat > notes.txt <<EOF\ntodo: %s push origin main\nEOF\n' "$GITW")"
  stdin="$(pretooluse_payload "$body")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "REGRESSION: a real commit whose message is a heredoc is still gated" {
  body="$(printf '%s commit -m "$(cat <<%sEOF%s\nfix: the thing\nEOF\n)"\n' "$GITW" "'" "'")"
  stdin="$(pretooluse_payload "$body")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -n "$(permission_decision "$output")" ]
}

@test "REGRESSION: a commit piped into a shell interpreter is still gated" {
  body="$(printf 'bash <<EOF\n%s commit -m sneaky\nEOF\n' "$GITW")"
  stdin="$(pretooluse_payload "$body")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -n "$(permission_decision "$output")" ]
}

@test "REGRESSION: a real commit with a trailing comment is still gated" {
  stdin="$(pretooluse_payload "$GITW commit -m test  # finally")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- masking must fail CLOSED --------------------------------------------
# A first attempt at the masking above deleted text whenever it looked like a
# comment or a heredoc body, and that opened the gate on all eight commands
# below: each runs a real git command, and each was reported as not gated.
# The lesson is that ambiguity must resolve toward gating, never away from
# it — a false positive costs a confirmation prompt, a false negative costs
# the guarantee. Every case here is a genuine bypass found in review.

@test "BYPASS: a hash inside a quoted string does not hide a later commit" {
  stdin="$(pretooluse_payload "echo \"issue #42\" && $GITW commit -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a hash inside a sed script does not hide a later commit" {
  stdin="$(pretooluse_payload "sed 's/ #.*//' f && $GITW commit -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a here-string is not a heredoc introducer" {
  stdin="$(pretooluse_payload "$(printf 'cat <<<"x"\n%s commit -m y\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an arithmetic left shift is not a heredoc introducer" {
  stdin="$(pretooluse_payload "$(printf 'echo $((1 << N))\n%s commit -m y\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an unterminated heredoc does not swallow a later commit" {
  stdin="$(pretooluse_payload "$(printf 'cat <<EOF\nbody\n%s commit -m x\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a heredoc introducer inside a string literal is not one" {
  stdin="$(pretooluse_payload "$(printf 'echo "use <<EOF here"\n%s commit -m x\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a path-prefixed shell interpreter still keeps its heredoc body" {
  stdin="$(pretooluse_payload "$(printf '/bin/bash <<EOF\n%s commit -m sneaky\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a remote shell still keeps its heredoc body" {
  stdin="$(pretooluse_payload "$(printf 'ssh host <<EOF\n%s push --force\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- SIGPIPE: the matcher must not report "no match" merely because grep -q
# --- exited before the producer finished writing. Under `set -o pipefail` a
# --- producer killed by SIGPIPE (141) fails the whole pipeline, so a large
# --- command silently escapes the gate.

@test "BYPASS: a large command containing a commit is still gated" {
  # The commit is on line 1 so the matcher finds it immediately; the padding
  # keeps the producer writing well past that point. It is executable text,
  # not a comment, so masking cannot shrink it away.
  padding="$(yes 'echo yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy' | head -2000)"
  stdin="$(pretooluse_payload "$(printf '%s commit -m x\n%s\n' "$GITW" "$padding")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- BYPASS classes found by the second review round. Each command below
# --- runs a real git command, verified with an execution oracle, and each
# --- was reported as not gated before the fix. The masker's fail-closed
# --- claim is only true if every one of these gates.

@test "BYPASS: a terminated here-string does not mask what follows" {
  stdin="$(pretooluse_payload "$(printf 'cat <<<"EOF"\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an unquoted heredoc body expands command substitution" {
  stdin="$(pretooluse_payload "$(printf 'cat > f <<EOF\n$(%s push --force)\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an unquoted heredoc body expands a backtick substitution" {
  stdin="$(pretooluse_payload "$(printf 'cat > f <<EOF\n`%s push --force`\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a shell feed with no space before the redirect keeps its body" {
  stdin="$(pretooluse_payload "$(printf 'bash<<EOF\n%s commit -m sneaky\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an interpreter named by a variable keeps its body" {
  stdin="$(pretooluse_payload "$(printf '$SHELL <<EOF\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a heredoc piped into a shell after its terminator keeps its body" {
  stdin="$(pretooluse_payload "$(printf '{ cat <<EOF\n%s commit -m x\nEOF\n} | bash\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a heredoc captured and evaluated later keeps its body" {
  stdin="$(pretooluse_payload "$(printf 'cmds=$(cat <<EOF\n%s commit -m x\nEOF\n)\neval "$cmds"\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a quoted introducer lookalike with a terminator masks nothing" {
  stdin="$(pretooluse_payload "$(printf 'grep -n "cat <<EOF" notes\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an introducer lookalike in a comment on a quoted line masks nothing" {
  stdin="$(pretooluse_payload "$(printf 'echo "hi" # like cat <<EOF\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an arithmetic command shift is not a heredoc introducer" {
  stdin="$(pretooluse_payload "$(printf 'if (( 1 << N )); then :; fi\n%s commit -m x\nN\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a C++ shift written to a file is not a heredoc introducer" {
  stdin="$(pretooluse_payload "$(printf 'echo std::cout << x > a.cpp\n%s commit -m y\nx\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: su keeps its heredoc body" {
  stdin="$(pretooluse_payload "$(printf 'su user <<EOF\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: sudo -s keeps its heredoc body" {
  stdin="$(pretooluse_payload "$(printf 'sudo -s <<EOF\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- idempotence: masking already-masked text must decide the same. A
# --- terminator line carrying a trailing comment is not a terminator to
# --- bash, so the heredoc is unterminated and nothing may be masked - and
# --- re-masking the output must not turn it into a terminator.

@test "BYPASS: a commented terminator lookalike does not mask on re-application" {
  stdin="$(pretooluse_payload "$(printf 'cat <<EOF\n%s commit -m x\nEOF # done\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- Third review round. The quote scanner tracked quote state per line and
# --- knew nothing of backslash escapes, so text bash keeps inside a string
# --- was read as being outside one - fabricating comments and heredoc
# --- introducers that swallow real commands. Each case below was confirmed
# --- fail-open with an execution oracle.

@test "BYPASS: an escaped quote inside a string does not hide a later commit" {
  stdin="$(pretooluse_payload "$(printf 'echo "a\\" #b" && %s commit -m x' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an escaped quote does not fabricate a heredoc introducer" {
  stdin="$(pretooluse_payload "$(printf 'echo "a\\" <<EOF"\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an escaped redirect is not a heredoc introducer" {
  stdin="$(pretooluse_payload "$(printf 'echo \\<<EOF\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a quote spanning lines does not fabricate a heredoc introducer" {
  stdin="$(pretooluse_payload "$(printf 'echo "\ncat <<EOF\n"\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a fabricated comment does not hide a shell feed from the guard" {
  stdin="$(pretooluse_payload "$(printf 'cat <<EOF | { echo "z\\" #" ; bash ; }\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- Two heredocs sharing a delimiter is the commonest multi-heredoc shape.
# --- Masking must handle the second one, or writing a file whose body merely
# --- mentions a commit reaches the commit branch and asks for a commit that
# --- does not exist.

@test "two heredocs sharing a delimiter: the second body is masked too" {
  stdin="$(pretooluse_payload "$(printf 'cat <<EOF\nhello\nEOF\ncat > f <<EOF\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Fourth review round, and the matcher rather than the masker. Every
# --- command below is fully intact - no comment, no heredoc, nothing that
# --- masking touches at all - and the pattern still failed to see it,
# --- because a quote character sat where it demanded whitespace, or a
# --- separator inside a quoted path ended a segment that the shell never
# --- ends. Each one runs a real gated command.

@test "BYPASS: a gated command inside bash -c is still gated" {
  stdin="$(pretooluse_payload "bash -c \"$GITW commit -m x\"")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a gated command inside sh -c is still gated" {
  stdin="$(pretooluse_payload "sh -c '$GITW commit -m x'")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a double-quoted subcommand is still gated" {
  stdin="$(pretooluse_payload "$GITW \"commit\" -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a single-quoted subcommand is still gated" {
  stdin="$(pretooluse_payload "$GITW 'commit' -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a quoted command name is still gated" {
  stdin="$(pretooluse_payload "\"$GITW\" commit -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a separator quoted inside a -C path does not end the segment" {
  stdin="$(pretooluse_payload "$GITW -C \"/a;b\" commit -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a push inside a quoted interpreter argument is still gated" {
  stdin="$(pretooluse_payload "bash -c \"$GITW push --force\"")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- the two below split the COMMAND WORD itself with a quote. The shell
# --- reads g"it" as git and runs it, and is_git_subcommand tokenizes it as
# --- git too - but main's fast path tests the raw string for the substring
# --- "git", which g"it" does not contain, so the matcher was never reached.
# --- A prefilter that is not quote-aware must not be able to overrule a
# --- matcher that is.

@test "BYPASS: a quote inside the command word is still gated" {
  stdin="$(pretooluse_payload "${GITW:0:1}\"${GITW:1}\" commit -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a single quote inside the command word is still gated" {
  stdin="$(pretooluse_payload "${GITW:0:1}'${GITW:1}' push origin main")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- the subcommand is the FIRST non-option word after the command word and
# --- its global options. Anywhere else the same word is data: a manual page,
# --- a search pattern, a ref name. All three below were gated before this
# --- rule, asking the user to confirm a commit that does not exist.

@test "help for the commit subcommand is not itself a commit" {
  stdin="$(pretooluse_payload "$GITW help commit")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a log search for the word commit is not a commit" {
  stdin="$(pretooluse_payload "$GITW log --grep commit")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "rev-parse verifying a ref named commit is not a commit" {
  stdin="$(pretooluse_payload "$GITW rev-parse --verify commit")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a log search for the word push is not a push" {
  stdin="$(pretooluse_payload "$GITW log --grep push")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- a payload the hook cannot parse must not open the gate. To a PreToolUse
# --- hook every exit status but 2 is a non-blocking error, so a jq assignment
# --- failing under `set -e` lets the tool call through with no gate at all.

@test "malformed stdin asks rather than failing open" {
  run_hook "$SCRIPT" 'not json'
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "stdin that is valid JSON but not an object asks rather than failing open" {
  run_hook "$SCRIPT" '[1,2,3]'
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "empty stdin asks rather than failing open" {
  run_hook "$SCRIPT" ''
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- the splitting pass reaches inside a quoted string, and must reach only
# --- where the quoted string is a command line. A search pattern or an echo
# --- argument that MENTIONS the watched words is the very case the masker
# --- above exists to let through; the interpreter list is what separates a
# --- mention from an interpreter's argument.

@test "a quoted mention in a search pattern is not gated" {
  stdin="$(pretooluse_payload "grep -rn \"$GITW commit\" hooks/")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a quoted mention echoed to the terminal is not gated" {
  stdin="$(pretooluse_payload "echo \"$GITW push origin main\"")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "BYPASS: a quoted command line handed to a remote shell is still gated" {
  stdin="$(pretooluse_payload "ssh host \"$GITW push --force\"")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# BYPASS: shapes that survived the tokenizer rewrite. Both put the watched
# word where the scanner could not read it: ANSI-C quoting ($'...') hides it
# behind a "$" the scanner treated as an ordinary word character, and an
# inline alias definition (-c alias.ci=commit) names the subcommand in the
# value of a global option the scanner skipped without reading.

@test "BYPASS: ANSI-C quoting around the subcommand is still gated" {
  stdin="$(pretooluse_payload "$GITW \$'commit' -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: ANSI-C quoting around the command word is still gated" {
  stdin="$(pretooluse_payload "\$'$GITW' commit -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: ANSI-C quoting around a push subcommand is still gated" {
  stdin="$(pretooluse_payload "$GITW \$'push' origin main")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an inline alias defining commit is gated" {
  stdin="$(pretooluse_payload "$GITW -c alias.ci=commit ci -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an inline alias defining push is gated" {
  stdin="$(pretooluse_payload "$GITW -c alias.pp=push pp")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an inline alias whose body starts with commit is gated" {
  stdin="$(pretooluse_payload "$GITW -c alias.save='commit -a -m wip' save")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "an inline alias unrelated to a gated subcommand is not gated" {
  stdin="$(pretooluse_payload "$GITW -c alias.st=status st")"
  run_hook "$SCRIPT" "$stdin"
  [ -z "$output" ]
}

@test "a dollar sign that is not ANSI-C quoting is still an ordinary character" {
  stdin="$(pretooluse_payload "$GITW log --grep \$'commit'")"
  run_hook "$SCRIPT" "$stdin"
  [ -z "$output" ]
}
