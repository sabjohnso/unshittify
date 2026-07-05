#!/usr/bin/env bats
# Characterization tests for confirm-git-commit-push.sh, pinning the exact
# behavior of the inline PreToolUse/Bash hook command it replaces:
#   jq -r '.tool_input.command // empty' | { read -r cmd; if printf '%s' "$cmd" \
#     | grep -Eq 'git([^&|;]*)(commit|push)'; then echo <ask-JSON>; fi; }

load helpers

setup() {
  SCRIPT="${HOOKS_DIR}/confirm-git-commit-push.sh"
}

pretooluse_payload() {
  jq -n --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}'
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
