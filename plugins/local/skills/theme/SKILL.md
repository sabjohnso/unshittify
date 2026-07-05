---
description: Set the Claude Code theme for the CURRENT project only, by writing to .claude/settings.local.json. Use when the user asks to set/change the project-local theme, e.g. "/local:theme dark".
argument-hint: [theme-name]
disable-model-invocation: true
allowed-tools: Read, Write, Bash(mkdir -p .claude)
---

# Set project-local theme

Goal: set the `"theme"` key in the **current project's** `.claude/settings.local.json` (NOT `.claude/settings.json`, and NOT any user-level `~/.claude/settings.json`), merging into whatever JSON is already there.

## 1. Determine the target value

- If the user supplied an argument (`$ARGUMENTS`), use it as the theme value directly, trimmed of whitespace.
- If `$ARGUMENTS` is empty, ask the user what theme they want. Mention that common values are `dark`, `light`, `dark-daltonized`, `light-daltonized`, `dark-ansi`, `light-ansi` (colorblind-friendly and ANSI-only variants), but do NOT refuse a value outside this list — Claude Code itself is the authority on what's valid. Pass through whatever the user confirms.

## 2. Locate/create the settings file

- The path is `.claude/settings.local.json` relative to the current project root (the directory containing `.claude/`, i.e. the project you're currently working in — not `$HOME` and not this plugin's own directory).
- If `.claude/` does not exist, create it.
- If `.claude/settings.local.json` does not exist, treat its current contents as `{}`.

## 3. Merge and write

- Read the existing file contents (if present) and parse as JSON. If the file exists but is empty or fails to parse, stop and tell the user the file has invalid JSON that needs manual fixing rather than overwriting it blindly.
- Set (or overwrite) only the top-level `"theme"` key to the value from step 1. Preserve every other existing top-level key and nested structure untouched.
- Write the merged object back to `.claude/settings.local.json` as pretty-printed JSON (2-space indent), with a trailing newline, keeping stable/deterministic key ordering (don't reorder unrelated existing keys).

## 4. Confirm

Tell the user exactly what was set and where, e.g.:

> Set `"theme": "dark"` in `.claude/settings.local.json` for this project.
