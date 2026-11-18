---
description: Add missing repository hook wiring to the global Claude Code settings of the user (~/.claude/settings.json). The wiring is the Stop, UserPromptSubmit, and PreToolUse entries for the hook scripts of a marketplace (enforce-prose-review.sh, enforce-code-review.sh, report-dead-jobs.sh, confirm-git-commit-push.sh, and deny-untracked-background.sh). Add it only after you show the exact JSON and get explicit approval. Use only when the user types this slash command, after the user saw a check-settings report that named the missing wiring.
argument-hint: "[marketplace path, if more than one has hooks]"
disable-model-invocation: true
allowed-tools: Read, Bash(jq:*), Bash(cp ~/.claude/settings.json:*), Bash(mv ~/.claude/settings.json.new:*)
---

# Repair missing hook wiring

Goal: wire the hook scripts of a marketplace into `~/.claude/settings.json`, so that they run. Change nothing else in the file.

This skill is separate from `global:check-settings` on purpose. That skill reads. This one writes to the file that decides which commands run automatically, unattended, in every project. `plugins/meta/skills/write-skill/SKILL.md` requires `disable-model-invocation: true` for exactly this kind of skill, so this skill has it. It runs only when the user types `/global:repair-hook-wiring`, never because a conversation came near the topic.

## Preconditions

Run `global:check-settings` first. This skill acts on that report. It does not derive the report again. Stop and say so if:

- no `extraKnownMarketplaces` entry has a `source.path` with a `hooks/` directory, or
- every script found there is already wired correctly, or
- the user did not see the report that names what is absent.

## Correct wiring

The command is `bash <path>/hooks/<script>`, where `<path>` is the `extraKnownMarketplaces` `source.path` that holds the `hooks/` directory. Derive it from the settings file. Never write a fixed absolute path.

| Script                           | Event                         | Matcher |
|----------------------------------|-------------------------------|---------|
| `enforce-prose-review.sh`        | `Stop`                        | none    |
| `enforce-code-review.sh`         | `Stop`                        | none    |
| `report-dead-jobs.sh`            | `Stop` and `UserPromptSubmit` | none    |
| `confirm-git-commit-push.sh`     | `PreToolUse`                  | `Bash`  |
| `deny-untracked-background.sh`   | `PreToolUse`                  | `Bash`  |

## Steps

1. Read `~/.claude/settings.json` and the check-settings report. List exactly which scripts are absent or wired wrongly.
2. Show the user the exact JSON that you will add, and ask. Continue only after an explicit yes. If the user declines, leave the file as it is and say so.
3. Make a backup of the file: `cp ~/.claude/settings.json ~/.claude/settings.json.bak`.
4. Build the merged JSON with `jq` into `~/.claude/settings.json.new`. `allowed-tools` permits the `mv` in step 5 only for that exact path, so a temporary file at a different place cannot be installed. Add a missing `Stop` command to the `hooks` array of an existing `hooks.Stop` entry. If the array is absent, create it. Add a missing `UserPromptSubmit` command in the same way. Add a missing `PreToolUse` command to an existing entry whose `matcher` is `Bash`, or create one. Never remove, reorder, or duplicate an entry that is already present.
5. Validate the file (`jq empty ~/.claude/settings.json.new`). Only when it is valid, run `mv ~/.claude/settings.json.new ~/.claude/settings.json`. If the merge or the validation fails, leave the live file as it is and report the failure. If something goes wrong after the move, restore the file with `cp ~/.claude/settings.json.bak ~/.claude/settings.json`.
6. For a script that is present but under the wrong event or without its matcher, describe the correction. Ask before you change it. Never move an existing entry in silence.
7. Report exactly which commands you added, and confirm that the file is valid JSON.
