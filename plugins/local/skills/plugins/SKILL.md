---
description: Choose which installed plugins (and their bundled skills) are active for the CURRENT project only, by toggling local-scope enable/disable. Use when the user asks to pick/select/curate which skills or plugins apply to this project.
argument-hint: "[enable|disable] [plugin-id...]"
disable-model-invocation: true
allowed-tools: Bash(claude plugin list:*), Bash(claude plugin enable:*), Bash(claude plugin disable:*)
---

# Select project-local plugins

Goal: choose which already-installed plugins are active for the **current project only**, by toggling them at the `local` settings scope (`.claude/settings.local.json`), leaving the shared `.claude/settings.json` and the user's global configuration untouched.

Note the granularity limit up front if relevant: Claude Code enables/disables whole plugins, not individual skills within a plugin. If the user's phrasing implies they want to keep one skill from a plugin while dropping another skill from that same plugin, tell them that isn't possible — the finest control is the plugin as a whole.

This skill only curates plugins that are **already installed**. Installing a new plugin (`claude plugin install`) is a separate action, not something to do here unless the user explicitly asks for it.

## 1. See what's installed

Run:
```
claude plugin list --json
```
This returns an array of objects like `{"id": "name@marketplace", "version": ..., "scope": ..., "enabled": true|false, ...}`. Use `id` as the plugin identifier for every command below.

## 2. Determine the requested action

- If `$ARGUMENTS` starts with `enable` or `disable` followed by one or more plugin ids, use those directly.
- Otherwise, show the user the installed plugins from step 1 (id + current `enabled` state) and ask which ones to enable and/or disable for this project.

## 3. Apply the change(s)

For each plugin id to enable:
```
claude plugin enable <id> --scope local
```
For each plugin id to disable:
```
claude plugin disable <id> --scope local
```
`--scope local` is what writes the toggle into `.claude/settings.local.json` for the current project rather than the user's global settings or the shared project settings.

## 4. Confirm

Re-run `claude plugin list --json` (or use the command output) and tell the user exactly which plugins are now enabled/disabled for this project, and that the change lives in `.claude/settings.local.json` (personal, gitignored) — `.claude/settings.json` was not touched.
