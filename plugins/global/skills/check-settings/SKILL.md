---
description: Inspect the global, user-level Claude Code settings of the user (~/.claude/settings.json) for JSON errors, unknown keys, permission rules that conflict or repeat, stale plugin or marketplace references, unsafe hook commands, insecure file permissions, missing repository hook wiring, and rules that are too broad. Reports only. Never edits the file. Use when the user asks you to check, audit, debug, or troubleshoot their global or user-level Claude Code settings. For the .claude/settings.local.json of a project, use local:check-settings instead.
allowed-tools: Read, Grep, Glob, Bash(claude plugin list:*), Bash(stat:*)
---

# Check the global Claude Code settings

Goal: find the problems in `~/.claude/settings.json` and report them. Never edit the file. The user decides what to fix.

This skill holds no tool that can write to the file. That is deliberate. The one repair that it knows, missing hook wiring, is in `/global:repair-hook-wiring`, a separate slash-command-only skill. This split lets this audit stay model-invocable, so it is safe to trigger from a description alone. The write to the file that decides which commands run automatically in every project stays behind an explicit user instruction.

## Scope

Primary target: `~/.claude/settings.json`.

This is the settings scope with the lowest precedence. The order is: enterprise managed settings, CLI flags, `.claude/settings.local.json`, `.claude/settings.json`, and then `~/.claude/settings.json` last. Everything in this file is a default that every project can override. Do not flag a rule as wrong only because a project-level file overrides it. That is expected. If a current project directory is available, read its `.claude/settings.json` and `.claude/settings.local.json` for context only, not as something that the global file must match.

## Checks

1. **Parse errors.** Read the file and confirm that it is valid JSON (no comma at the end of a list, no unescaped backslash inside a `Bash(...)` pattern, no mismatched brace).
2. **Unknown top-level keys.** Flag each key that is not one of the known settings keys: `permissions`, `model`, `hooks`, `enabledPlugins`, `enabledMcpjsonServers`, `enableAllProjectMcpServers`, `mcpServers`, `extraKnownMarketplaces`, `askUserQuestionTimeout`, `voice`, `voiceEnabled`, `skipWorkflowUsageWarning`, `theme`, `editorMode`, `switchModelsOnFlag`, `remoteControlAtStartup`, `agentPushNotifEnabled`, `statusLine`, `outputStyle`, `env`. This list can be incomplete. Flag an unknown key as "make sure that this is a real key", not as a confirmed error.
3. **Permission rule conflicts.** Inside `permissions.allow` and `permissions.deny`, flag: the identical rule listed twice; the identical rule in both `allow` and `deny`; a rule that a broader rule in the same array already covers (for example `Bash(git status:*)` beside a bare `Bash`).
4. **Rules that are too broad.** Flag a bare tool name with no argument scope in `allow` (for example `Bash`, `Edit`, or `Read` with no pattern), or a wildcard pattern (`Bash(*)`) that defeats the least privilege. This file applies to every project by default, so flag these more strongly than in a project-scoped file.
5. **Stale plugin references.** If `enabledPlugins` is present, compare each key against `claude plugin list --json`. Flag each entry for a plugin that is no longer installed.
6. **Stale marketplace references.** If `extraKnownMarketplaces` is present, check that the `source.path` of each entry (for the `"source": "directory"` entries) exists on disk. Flag each one that does not.
7. **Hook exposure.** For each entry under `hooks`, quote the command exactly in the report. These commands run automatically and unattended for every matching tool call across every project. Call out each command that seems to embed a credential, a token, or shell logic that permits too much (for example no quotes around a `$(...)` substitution).
8. **File permissions.** Run `stat -c '%a %U:%G' ~/.claude/settings.json` (or `stat -f '%Lp %Su:%Sg'` on macOS). Flag the file if the group or the world can write it. Each other person with access to the machine can then change the hooks that run automatically.
9. **Repository hook wiring.** For each `extraKnownMarketplaces` entry whose `source.path` holds a `hooks/` directory, check for `enforce-prose-review.sh`, `enforce-code-review.sh`, and `confirm-git-commit-push.sh`. For each one that is on disk, confirm that it is wired into the top-level `hooks` key. `enforce-prose-review.sh` and `enforce-code-review.sh` must be a `command` under `hooks.Stop`. `confirm-git-commit-push.sh` must be under `hooks.PreToolUse` with a `matcher` of `Bash`. Flag each script that is on disk but absent from `hooks`, wired under the wrong event, or without the expected matcher. For each one that is absent or wired wrongly, put the exact JSON entry that fixes it in the report, and say that `/global:repair-hook-wiring` applies it after the approval of the user. Skip this check in silence if no marketplace path holds a `hooks/` directory with these scripts.

## Steps

1. Read `~/.claude/settings.json`. If a project directory is available, also read its `.claude/settings.json` and `.claude/settings.local.json` for cross-scope context.
2. Apply each check above to the content of the file. Run `claude plugin list --json` and `stat` only when a check needs them.
3. Report the findings in groups per check. Give the offending key or entry, what is wrong, and why it matters. If nothing is wrong, say so plainly. Do not invent issues to fill the report.
4. If check 9 found a script that is absent or wired wrongly, end the report with `/global:repair-hook-wiring` as the way to apply the fix. Do not try the repair here.
