---
description: Inspect the user's global Claude Code settings (~/.claude/settings.json) for JSON errors, unknown keys, conflicting or redundant permission rules, stale plugin/marketplace references, insecure file permissions, and overly broad rules. Use when the user asks to check, audit, debug, or troubleshoot their global Claude Code settings.
allowed-tools: Read, Grep, Glob, Bash(claude plugin list:*), Bash(stat:*)
---

# Check global Claude Code settings

Goal: diagnose problems in `~/.claude/settings.json` and report them. Never edit the file — the user decides what to fix.

## Scope

Primary target: `~/.claude/settings.json`.

This is the lowest-precedence settings scope: enterprise managed settings, CLI flags, `.claude/settings.local.json`, `.claude/settings.json`, then `~/.claude/settings.json` last. Everything in this file is a default that any project can override — do not flag a rule as wrong just because a project-level file overrides it; that is expected. If a current project directory is available, read its `.claude/settings.json` and `.claude/settings.local.json` for context only, not as something the global file must match.

## Checks

1. **Parse errors** — read the file and confirm it is syntactically valid JSON (trailing commas, unescaped backslashes inside `Bash(...)` patterns, mismatched braces).
2. **Unknown top-level keys** — flag any key that is not one of the known settings keys: `permissions`, `model`, `hooks`, `enabledPlugins`, `enabledMcpjsonServers`, `enableAllProjectMcpServers`, `mcpServers`, `extraKnownMarketplaces`, `askUserQuestionTimeout`, `voice`, `voiceEnabled`, `skipWorkflowUsageWarning`, `theme`, `editorMode`, `switchModelsOnFlag`, `remoteControlAtStartup`, `agentPushNotifEnabled`, `statusLine`, `outputStyle`, `env`. This list may be incomplete — flag anything unfamiliar as "verify this is a real key," not as a confirmed error.
3. **Permission rule conflicts** — within `permissions.allow` / `permissions.deny`, flag: the identical rule listed twice; the identical rule present in both `allow` and `deny`; a rule already implied by a broader rule in the same array (e.g. `Bash(git status:*)` next to a bare `Bash`).
4. **Overly broad rules** — bare tool names with no argument scoping in `allow` (e.g. `Bash`, `Edit`, `Read` with no pattern) or wildcard patterns (`Bash(*)`) that defeat least privilege. This file applies to every project by default, so flag these more assertively than in a project-scoped file.
5. **Stale plugin references** — if `enabledPlugins` appears, cross-check each key against `claude plugin list --json` and flag entries for plugins that are no longer installed.
6. **Stale marketplace references** — if `extraKnownMarketplaces` appears, check that each entry's `source.path` (for `"source": "directory"` entries) still exists on disk. Flag any that don't.
7. **Hook exposure** — for each entry under `hooks`, surface the command verbatim in the report. These commands run automatically and unattended for every matching tool call across every project; call out anything that looks like it embeds a credential, token, or overly permissive shell logic (e.g. missing quoting around `$(...)` substitutions).
8. **File permissions** — run `stat -c '%a %U:%G' ~/.claude/settings.json` (or `stat -f '%Lp %Su:%Sg'` on macOS). Flag the file if it is group- or world-writable: anyone else with access to the machine could alter auto-executing hooks.
9. **Repository hook wiring** — for each `extraKnownMarketplaces` entry whose `source.path` contains a `hooks/` directory, check for `enforce-prose-review.sh`, `enforce-code-review.sh`, and `confirm-git-commit-push.sh`. For each one present on disk, confirm it is wired into the top-level `hooks` key: `enforce-prose-review.sh` and `enforce-code-review.sh` must appear as a `command` under `hooks.Stop`; `confirm-git-commit-push.sh` must appear under `hooks.PreToolUse` with a `matcher` of `Bash`. Flag any script found on disk but missing from `hooks`, wired under the wrong event, or missing the expected matcher. Skip silently if no marketplace path contains a `hooks/` directory with these scripts.

## Steps

1. Read `~/.claude/settings.json`. If a project directory is available, also read its `.claude/settings.json` and `.claude/settings.local.json` for cross-scope context.
2. Walk each check above against the file's contents, running `claude plugin list --json` and `stat` only when a check needs them.
3. Report findings grouped by check, each with the offending key/entry, what's wrong, and why it matters. If nothing is wrong, say so plainly — do not invent issues to fill the report.
