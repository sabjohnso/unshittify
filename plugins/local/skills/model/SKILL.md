---
description: Set the Claude Code model for the CURRENT project only, with a write to .claude/settings.local.json. Use when the user asks you to set or change the project-local default model, for example "/local:model opus".
argument-hint: "[model-alias-or-id]"
disable-model-invocation: true
allowed-tools: Read, Write, Bash(mkdir -p .claude)
---

# Set the project-local model

Goal: set the `"model"` key in the `.claude/settings.local.json` of the **current project** (NOT `.claude/settings.json`, and NOT a user-level `~/.claude/settings.json`). Merge the key into the JSON that is already there.

## 1. Find the target value

- If the user gave an argument (`$ARGUMENTS`), use it as the model value directly, with the whitespace trimmed.
- If `$ARGUMENTS` is empty, ask the user which model they want. The valid values include:
  - The aliases: `default` (clears the override), `sonnet`, `opus`, `haiku`, `fable`, `best`, `opusplan`
  - The aliases with an extended context: `sonnet[1m]`, `opus[1m]`
  - A full model name or ID, for example `claude-opus-4-8`, `claude-sonnet-5`
- Do not validate the value beyond a basic check (a string that is not empty). Claude Code itself resolves or rejects the value at run time. Pass through the value that the user confirms.

## 2. Find or create the settings file

- The path is `.claude/settings.local.json`, relative to the root of the current project (the directory that holds `.claude/`). It is not `$HOME`, and it is not the directory of this plugin.
- If `.claude/` does not exist, create it.
- If `.claude/settings.local.json` does not exist, treat its current content as `{}`.

## 3. Merge and write

- Read the content of the existing file (if it is present) and parse it as JSON. If the file exists but is empty or does not parse, stop. Tell the user that the file holds invalid JSON that needs a manual fix. Do not overwrite it blindly.
- Set (or overwrite) only the top-level `"model"` key to the value from step 1. Keep every other top-level key and nested structure as it is.
- Write the merged object back to `.claude/settings.local.json` as pretty-printed JSON (an indent of 2 spaces), with a newline at the end, and with the existing key order.

## 4. Confirm

Tell the user exactly what you set and where, for example:

> Set `"model": "opus"` in `.claude/settings.local.json` for this project.
