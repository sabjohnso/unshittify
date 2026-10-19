#!/usr/bin/env bats
# Tests for confirm-git-commit-push.sh. The first group holds the
# characterization tests. They pin the exact behavior of the inline
# PreToolUse/Bash hook command that the script replaced:
#   jq -r '.tool_input.command // empty' | { read -r cmd; if printf '%s' "$cmd" \
#     | grep -Eq 'git([^&|;]*)(commit|push)'; then echo <ask-JSON>; fi; }
# The second group covers the prose-review gate. The hook denies a git
# commit until the communication:prose-reviewer agent has run this turn.
# When the hook cannot judge the transcript (no path, no file, or no turn
# boundary), the gate degrades to the plain ask.

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

@test "a plain git commit asks for confirmation" {
  stdin="$(pretooluse_payload 'git commit -m test')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "ask" ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "PreToolUse" ]
}

@test "a plain git push asks for confirmation" {
  stdin="$(pretooluse_payload 'git push origin main')"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "ask" ]
}

@test "a git commit after a && chain asks (the second git...commit segment matches)" {
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

@test "a missing tool_input.command does not ask and gives no error" {
  stdin='{"tool_name":"Bash","tool_input":{}}'
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- prose-review gate on git commit ---

@test "the hook denies a git commit when the prose-reviewer did not run this turn" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
  [[ "$(permission_reason "$output")" == *"communication:prose-reviewer"* ]]
}

@test "a git commit after a prose-reviewer call this turn asks for confirmation" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a prose review from an earlier turn does not satisfy the commit gate" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(user_prompt_event)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "the review-prose skill does not satisfy the commit gate (the agent is necessary)" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Skill skill=communication:review-prose)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "a near-miss agent name does not satisfy the commit gate" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer-preview)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "git push needs no prose review" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git push origin main' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a git commit with a transcript file that does not exist degrades to ask" {
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' /nonexistent/transcript.jsonl)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a git commit with a transcript that has no turn boundary degrades to ask" {
  transcript="$(write_transcript "$(tool_use_event Bash)")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- subcommand-token matching: a ref that holds commit or push must not
# --- confuse the gate. commit and push count only as separate tokens after
# --- git.

@test "a git push to a branch that holds 'commit' is a push, not a gated commit" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git push origin fix-commit-message' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a git push to a remote named commit-fixes is a push, not a gated commit" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git push commit-fixes' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a commit whose message mentions push reaches the commit gate" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m "push the button"' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "a combined commit-and-push command is gated as a commit" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m x && git push' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "a git commit with global options before the subcommand is gated" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git -C /some/repo commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "a push with a redirection immediately after it is a push, not ignored" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git push>/dev/null' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a commit inside a subshell is gated" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript '(git commit)' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "a commit chained with no spaces is gated" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit&&git push' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "a non-git command whose name ends in git is not gated" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'legit commit -m x' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a git binary with a path prefix is gated" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript '/usr/bin/git commit -m x' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

# --- laws of the commit gate, pinned as the decision function of
# --- enforce-code-review pins its own (monotonicity, insensitivity to
# --- duplicates, invariance of the boundary).

@test "monotonicity: a reviewer call added at the end turns deny into ask" {
  base="$(printf '%s\n%s' "$(user_prompt_event)" "$(tool_use_event Bash)")"
  transcript="$(write_transcript "$base")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "deny" ]

  grown="$(write_transcript "$(printf '%s\n%s' "$base" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$grown")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "duplicate reviewer calls give the same decision as one" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a skill with exactly the name of the agent does not satisfy the gate" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Skill skill=communication:prose-reviewer)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "a tool_result after the review does not turn ask back into deny" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(tool_result_event)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a meta injection after the review does not turn ask back into deny" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(meta_injection_event)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a late last-prompt marker after the review does not turn ask back into deny" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(last_prompt_marker)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- text that the shell will not execute must not gate --------------------
# The hook reads the whole command string. So a shell comment or a heredoc
# BODY that only MENTIONS the gated words trips it. That is not
# hypothetical. It blocked a transcript-search command whose Python comment
# read "first git commit afterwards", and then it blocked the command that
# first wrote these tests.
#
# The word "git" comes from GITW below. It is not written beside its
# subcommand. Thus an edit of this file does not trip the hook. Of the four
# tests that follow, three were red before the fix. The string-literal test
# passed already, because the quote before the word never satisfied the
# preceding-character class of the pattern. So it records the earlier
# behavior and does not show that the fix works. The three tests after them
# pin what the fix must not relax. The mask can only remove text that the
# shell will not execute, so a heredoc that feeds a shell interpreter stays
# gated, although it is a heredoc body.

GITW=git

@test "a shell comment that mentions a commit does not gate" {
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

@test "an unquoted heredoc body that mentions a push does not gate" {
  body="$(printf 'cat > notes.txt <<EOF\ntodo: %s push origin main\nEOF\n' "$GITW")"
  stdin="$(pretooluse_payload "$body")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "REGRESSION: a real commit whose message is a heredoc is gated" {
  body="$(printf '%s commit -m "$(cat <<%sEOF%s\nfix: the thing\nEOF\n)"\n' "$GITW" "'" "'")"
  stdin="$(pretooluse_payload "$body")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -n "$(permission_decision "$output")" ]
}

@test "REGRESSION: a commit piped into a shell interpreter is gated" {
  body="$(printf 'bash <<EOF\n%s commit -m sneaky\nEOF\n' "$GITW")"
  stdin="$(pretooluse_payload "$body")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -n "$(permission_decision "$output")" ]
}

@test "REGRESSION: a real commit with a comment at the end is gated" {
  stdin="$(pretooluse_payload "$GITW commit -m test  # finally")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- the mask must fail CLOSED -------------------------------------------
# A first version of the mask above deleted text whenever the text looked
# like a comment or a heredoc body. That opened the gate on all eight
# commands below. Each one runs a real git command, and the hook reported
# each one as not gated. The lesson: an ambiguity must resolve toward the
# gate, never away from it. A false positive costs a confirmation prompt. A
# false negative costs the guarantee. Every case here is a genuine bypass
# found in a review.

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

# --- SIGPIPE: the matcher must not report "no match" only because grep -q
# --- exited before the producer finished. Under `set -o pipefail`, a
# --- producer that SIGPIPE (141) killed fails the whole pipeline. So a large
# --- command escapes the gate with no error.

@test "BYPASS: a large command that holds a commit is gated" {
  # The commit is on line 1, so the matcher finds it at once. The padding
  # keeps the producer busy well past that point. It is executable text, not
  # a comment, so the mask cannot remove it.
  padding="$(yes 'echo yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy' | head -2000)"
  stdin="$(pretooluse_payload "$(printf '%s commit -m x\n%s\n' "$GITW" "$padding")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- BYPASS classes that the second review round found. Each command below
# --- runs a real git command. An execution oracle confirmed that. Before the
# --- fix, the hook reported each one as not gated. The fail-closed claim of
# --- the masker is true only if every one of these gates.

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

# --- idempotence: a second mask of masked text must give the same
# --- decision. A terminator line with a comment at the end is not a
# --- terminator to bash. So the heredoc is unterminated, and the hook must
# --- mask nothing. A second mask of the output must not turn that line into
# --- a terminator.

@test "BYPASS: a terminator lookalike with a comment does not mask on a second application" {
  stdin="$(pretooluse_payload "$(printf 'cat <<EOF\n%s commit -m x\nEOF # done\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- Third review round. The quote scanner tracked the quote state per line
# --- and knew nothing of backslash escapes. So it read text that bash keeps
# --- inside a string as text outside a string. That fabricated comments and
# --- heredoc introducers that hid real commands. An execution oracle
# --- confirmed that each case below failed open.

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

# --- Two heredocs with one delimiter is the most common multi-heredoc
# --- shape. The mask must handle the second one. Otherwise a write of a file
# --- whose body only mentions a commit reaches the commit branch and is
# --- DENIED, not prompted.

@test "two heredocs with one delimiter: the mask covers the second body too" {
  stdin="$(pretooluse_payload "$(printf 'cat <<EOF\nhello\nEOF\ncat > f <<EOF\n%s commit -m x\nEOF\n' "$GITW")")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Fourth review round, and the matcher, not the masker. Every command
# --- below is intact. It has no comment, no heredoc, and nothing that the
# --- mask touches. The pattern still failed to see it, because a quote
# --- character sat where the pattern demanded whitespace, or a separator
# --- inside a quoted path ended a segment that the shell never ends. Each
# --- one runs a real gated command.

@test "BYPASS: a gated command inside bash -c is gated" {
  stdin="$(pretooluse_payload "bash -c \"$GITW commit -m x\"")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a gated command inside sh -c is gated" {
  stdin="$(pretooluse_payload "sh -c '$GITW commit -m x'")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a double-quoted subcommand is gated" {
  stdin="$(pretooluse_payload "$GITW \"commit\" -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a single-quoted subcommand is gated" {
  stdin="$(pretooluse_payload "$GITW 'commit' -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a quoted command name is gated" {
  stdin="$(pretooluse_payload "\"$GITW\" commit -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a separator quoted inside a -C path does not end the segment" {
  stdin="$(pretooluse_payload "$GITW -C \"/a;b\" commit -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a push inside a quoted interpreter argument is gated" {
  stdin="$(pretooluse_payload "bash -c \"$GITW push --force\"")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- the two tests below split the COMMAND WORD itself with a quote. The
# --- shell reads g"it" as git and runs it, and is_git_subcommand tokenizes
# --- it as git too. But the fast path of main tests the raw string for the
# --- substring "git", and g"it" does not hold it, so the matcher never ran.
# --- A prefilter that does not know quotes must not overrule a matcher that
# --- does.

@test "BYPASS: a quote inside the command word is gated" {
  stdin="$(pretooluse_payload "${GITW:0:1}\"${GITW:1}\" commit -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: a single quote inside the command word is gated" {
  stdin="$(pretooluse_payload "${GITW:0:1}'${GITW:1}' push origin main")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- the subcommand is the FIRST non-option word after the command word and
# --- its global options. At every other position, the same word is data: a
# --- manual page, a search pattern, a ref name. Before this rule, the hook
# --- DENIED all three commands below and told the model to review a message
# --- that does not exist.

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

@test "a rev-parse check of a ref named commit is not a commit" {
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

# --- a payload that the hook cannot parse must not open the gate. To a
# --- PreToolUse hook, every exit status but 2 is a non-blocking error. So a
# --- jq assignment that fails under `set -e` lets the tool call through
# --- with no gate at all.

@test "malformed stdin asks and does not fail open" {
  run_hook "$SCRIPT" 'not json'
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "stdin that is valid JSON but not an object asks and does not fail open" {
  run_hook "$SCRIPT" '[1,2,3]'
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "empty stdin asks and does not fail open" {
  run_hook "$SCRIPT" ''
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- the splitting pass reaches inside a quoted string. It must reach only
# --- where the quoted string is a command line. A search pattern or an echo
# --- argument that MENTIONS the watched words is the exact case that the
# --- masker above lets through. The interpreter list separates a mention
# --- from the argument of an interpreter.

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

@test "BYPASS: a quoted command line given to a remote shell is gated" {
  stdin="$(pretooluse_payload "ssh host \"$GITW push --force\"")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

# BYPASS: shapes that survived the rewrite of the tokenizer. Both put the
# watched word where the scanner could not read it. ANSI-C quoting ($'...')
# hides it behind a "$" that the scanner treated as an ordinary word
# character. An inline alias definition (-c alias.ci=commit) names the
# subcommand in the value of a global option that the scanner skipped and
# did not read.

@test "BYPASS: ANSI-C quoting around the subcommand is gated" {
  stdin="$(pretooluse_payload "$GITW \$'commit' -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: ANSI-C quoting around the command word is gated" {
  stdin="$(pretooluse_payload "\$'$GITW' commit -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: ANSI-C quoting around a push subcommand is gated" {
  stdin="$(pretooluse_payload "$GITW \$'push' origin main")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an inline alias that defines commit is gated" {
  stdin="$(pretooluse_payload "$GITW -c alias.ci=commit ci -m x")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an inline alias that defines push is gated" {
  stdin="$(pretooluse_payload "$GITW -c alias.pp=push pp")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "BYPASS: an inline alias whose body starts with commit is gated" {
  stdin="$(pretooluse_payload "$GITW -c alias.save='commit -a -m wip' save")"
  run_hook "$SCRIPT" "$stdin"
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "an inline alias with no relation to a gated subcommand is not gated" {
  stdin="$(pretooluse_payload "$GITW -c alias.st=status st")"
  run_hook "$SCRIPT" "$stdin"
  [ -z "$output" ]
}

@test "a dollar sign that is not ANSI-C quoting is an ordinary character" {
  stdin="$(pretooluse_payload "$GITW log --grep \$'commit'")"
  run_hook "$SCRIPT" "$stdin"
  [ -z "$output" ]
}
