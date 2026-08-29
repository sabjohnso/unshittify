---
description: Add missing repository hook wiring to the user's global Claude Code settings (~/.claude/settings.json) — the Stop and PreToolUse entries for a marketplace's enforce-prose-review.sh, enforce-code-review.sh, and confirm-git-commit-push.sh — after showing the exact JSON and getting explicit approval. Use only when the user types this slash command, having already seen a check-settings report naming the missing wiring.
argument-hint: "[marketplace path, if more than one has hooks]"
disable-model-invocation: true
allowed-tools: Read, Bash(jq:*), Bash(cp ~/.claude/settings.json:*), Bash(mv:*)
---

# Repair missing hook wiring

Goal: wire a marketplace's hook scripts into `~/.claude/settings.json` so they actually run, changing nothing else in the file.

This skill is separate from `global:check-settings` on purpose. That skill reads; this one writes to the file that decides which commands execute automatically, unattended, in every project. `plugins/meta/skills/write-skill/SKILL.md` requires `disable-model-invocation: true` for exactly this shape of skill, so this one carries it: it runs only when the user types `/global:repair-hook-wiring`, never because a conversation drifted near the topic.

## Preconditions

Run `global:check-settings` first. This skill acts on that report; it does not re-derive it. Stop and say so if:

- no `extraKnownMarketplaces` entry's `source.path` contains a `hooks/` directory, or
- every script found there is already wired correctly, or
- the user has not seen the report naming what is missing.

## What correct wiring looks like

The command is `bash <path>/hooks/<script>`, where `<path>` is the `extraKnownMarketplaces` `source.path` holding the `hooks/` directory. Derive it from the settings file — never hardcode an absolute path.

| Script                      | Event        | Matcher |
|-----------------------------|--------------|---------|
| `enforce-prose-review.sh`   | `Stop`       | none    |
| `enforce-code-review.sh`    | `Stop`       | none    |
| `confirm-git-commit-push.sh`| `PreToolUse` | `Bash`  |

## Steps

1. Read `~/.claude/settings.json` and the check-settings report. List exactly which scripts are missing or mis-wired.
2. Show the user the exact JSON that would be added, and ask. Proceed only on an explicit yes; if the user declines, leave the file untouched and say so.
3. Back the file up: `cp ~/.claude/settings.json ~/.claude/settings.json.bak`.
4. Build the merged JSON with `jq` into a temp file. Append a missing `Stop` command to an existing `hooks.Stop` entry's `hooks` array, or create the array if absent; append a missing `PreToolUse` command to an existing entry whose `matcher` is `Bash`, or create one. Never remove, reorder, or duplicate anything already present.
5. Validate the temp file (`jq empty <temp>`). Only once it is valid, `mv` it into place. If the merge or validation fails, leave the live file untouched and report the failure; if anything goes wrong after the move, restore from the `.bak`.
6. For a script that is present but under the wrong event or missing its matcher, describe the correction and ask before changing it — never silently move an existing entry.
7. Report exactly which commands were added and confirm the file is still valid JSON.
