---
description: Set the Claude Code model for the CURRENT project only, by writing to .claude/settings.local.json. Use when the user asks to set/change the project-local default model, e.g. "/local:model opus".
argument-hint: "[model-alias-or-id]"
disable-model-invocation: true
allowed-tools: Read, Write, Bash(mkdir -p .claude)
---

# Set project-local model

Goal: set the `"model"` key in the **current project's** `.claude/settings.local.json` (NOT `.claude/settings.json`, and NOT any user-level `~/.claude/settings.json`), merging into whatever JSON is already there.

## 1. Determine the target value

- If the user supplied an argument (`$ARGUMENTS`), use it as the model value directly, trimmed of whitespace.
- If `$ARGUMENTS` is empty, ask the user which model they want. Valid values include:
  - Aliases: `default` (clears the override), `sonnet`, `opus`, `haiku`, `fable`, `best`, `opusplan`
  - Aliases with extended context: `sonnet[1m]`, `opus[1m]`
  - A full model name/ID, e.g. `claude-opus-4-8`, `claude-sonnet-5`
- Do not validate beyond basic sanity (non-empty string) — Claude Code itself resolves/rejects the value at runtime. Pass whatever the user confirms straight through.

## 2. Locate/create the settings file

- The path is `.claude/settings.local.json` relative to the current project root (the directory containing `.claude/` — not `$HOME` and not this plugin's own directory).
- If `.claude/` does not exist, create it.
- If `.claude/settings.local.json` does not exist, treat its current contents as `{}`.

## 3. Merge and write

- Read the existing file contents (if present) and parse as JSON. If the file exists but is empty or fails to parse, stop and tell the user the file has invalid JSON that needs manual fixing rather than overwriting it blindly.
- Set (or overwrite) only the top-level `"model"` key to the value from step 1. Preserve every other existing top-level key and nested structure untouched.
- Write the merged object back to `.claude/settings.local.json` as pretty-printed JSON (2-space indent), with a trailing newline, keeping stable/deterministic key ordering (don't reorder unrelated existing keys).

## 4. Confirm

Tell the user exactly what was set and where, e.g.:

> Set `"model": "opus"` in `.claude/settings.local.json` for this project.
