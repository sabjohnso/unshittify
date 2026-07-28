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

# shellcheck source=lib/transcript.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/transcript.sh"

# is_git_subcommand <command-string> <subcommand>
#
# Succeeds when <subcommand> appears as a standalone token after a git
# invocation within the same shell-separator segment. Token matching on both
# words, not substring: a ref such as fix-commit-message or a remote named
# commit-fixes must never count as a commit, and a command like "legit" is
# not git (though a path-prefixed /usr/bin/git is). The subcommand token may
# end at whitespace, a separator, a redirection, a closing paren, or the end
# of the command. Matching is per line, so a backslash-continuation between
# git and its subcommand escapes the gate - accepted, since real commit
# commands (including the heredoc form) keep "git commit" on one line.
is_git_subcommand() {
  printf '%s' "$1" | grep -Eq "(^|[[:space:];&|(/])git[^&|;]*[[:space:]]$2([[:space:]&|;><)]|\$)"
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
