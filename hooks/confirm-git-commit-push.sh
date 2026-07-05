#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): asks for confirmation before letting a
# git commit or push run, per the standing instruction that commits and
# pushes require an explicit instruction in the current turn.
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

if printf '%s' "$cmd" | grep -Eq 'git([^&|;]*)(commit|push)'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: "git commit/push requires an explicit instruction in this turn - confirm to proceed."
    }
  }'
fi
