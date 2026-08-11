#!/usr/bin/env bats
# Tests for confirm-git-commit-push.sh. The first group are characterization
# tests pinning the exact behavior of the inline PreToolUse/Bash hook command
# it replaced:
#   jq -r '.tool_input.command // empty' | { read -r cmd; if printf '%s' "$cmd" \
#     | grep -Eq 'git([^&|;]*)(commit|push)'; then echo <ask-JSON>; fi; }
# The second group covers the prose-review gate: a git commit is denied until
# the communication:prose-reviewer agent has been invoked this turn; when the
# transcript cannot be judged (missing path/file, no turn boundary) the gate
# degrades to the plain ask.

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

# --- prose-review gate on git commit ---

@test "git commit with no prose-reviewer invocation this turn is denied" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
  [[ "$(permission_reason "$output")" == *"communication:prose-reviewer"* ]]
}

@test "git commit after a prose-reviewer invocation this turn asks for confirmation" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a prose review from a previous turn does not satisfy the commit gate" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(user_prompt_event)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "the review-prose skill does not satisfy the commit gate (agent required)" {
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

@test "git commit with a nonexistent transcript file degrades to ask" {
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' /nonexistent/transcript.jsonl)"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "git commit with a transcript lacking any turn boundary degrades to ask" {
  transcript="$(write_transcript "$(tool_use_event Bash)")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

# --- subcommand-token matching: refs containing commit/push must not confuse
# --- the gate. commit/push count only as standalone tokens after git.

@test "git push to a branch containing 'commit' is a push, not a gated commit" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git push origin fix-commit-message' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "git push to a remote named commit-fixes is a push, not a gated commit" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git push commit-fixes' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a commit whose message mentions push still hits the commit gate" {
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

@test "git commit with global options before the subcommand is still gated" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git -C /some/repo commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "a push followed immediately by a redirection is a push, not ignored" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript 'git push>/dev/null' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a commit inside a subshell is still gated" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript '(git commit)' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "a commit chained without spaces is still gated" {
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

@test "a path-prefixed git binary is still gated" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Bash)")")"
  stdin="$(pretooluse_payload_with_transcript '/usr/bin/git commit -m x' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

# --- laws of the commit gate, pinned the way enforce-code-review's decision
# --- function pins its own (monotonicity, duplicate-insensitivity, boundary
# --- invariance).

@test "monotonicity: appending the reviewer invocation flips deny to ask" {
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

@test "duplicate reviewer invocations decide the same as one" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a skill named exactly like the agent does not satisfy the gate" {
  transcript="$(write_transcript "$(printf '%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Skill skill=communication:prose-reviewer)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "deny" ]
}

@test "a tool_result after the review does not flip ask back to deny" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(tool_result_event)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a meta injection after the review does not flip ask back to deny" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(meta_injection_event)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
  run_hook "$SCRIPT" "$stdin"
  [ "$status" -eq 0 ]
  [ "$(permission_decision "$output")" = "ask" ]
}

@test "a late last-prompt marker after the review does not flip ask back to deny" {
  transcript="$(write_transcript "$(printf '%s\n%s\n%s\n' \
    "$(user_prompt_event)" \
    "$(tool_use_event Task subagent_type=communication:prose-reviewer)" \
    "$(last_prompt_marker)")")"
  stdin="$(pretooluse_payload_with_transcript 'git commit -m test' "$transcript")"
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
