---
description: Choose which installed plugins (and their bundled skills) are active for the CURRENT project only. Enable or disable them at the local scope. Use when the user asks you to pick, select, or curate the skills or plugins that apply to this project.
argument-hint: "[enable|disable] [plugin-id...]"
disable-model-invocation: true
allowed-tools: Bash(claude plugin list:*), Bash(claude plugin enable:*), Bash(claude plugin disable:*)
---

# Select the project-local plugins

Goal: choose which installed plugins are active for the **current project only**. Toggle them at the `local` settings scope (`.claude/settings.local.json`). Leave the shared `.claude/settings.json` and the global configuration of the user as they are.

If it applies, tell the user at the start: Claude Code enables or disables whole plugins, not individual skills inside a plugin. If the words of the user show that they want to keep one skill from a plugin and drop a different skill from that same plugin, tell them that this is not possible. The finest control is the plugin as a whole.

This skill only enables or disables plugins that are **already installed**. An install of a new plugin (`claude plugin install`) is a separate action. Do not do it here, unless the user explicitly asks for it.

## 1. See what is installed

Run:
```
claude plugin list --json
```
This returns an array of objects such as `{"id": "name@marketplace", "version": ..., "scope": ..., "enabled": true|false, ...}`. Use `id` as the plugin identifier for every command below.

## 2. Find the requested action

- If `$ARGUMENTS` starts with `enable` or `disable`, with one or more plugin ids after it, use those directly.
- Otherwise, show the user the installed plugins from step 1 (the id and the current `enabled` state), and ask which ones to enable or disable for this project.

## 3. Apply the changes

For each plugin id to enable:
```
claude plugin enable <id> --scope local
```
For each plugin id to disable:
```
claude plugin disable <id> --scope local
```
`--scope local` writes the toggle into `.claude/settings.local.json` for the current project, and not into the global settings of the user or the shared project settings.

## 4. Confirm

Run `claude plugin list --json` again (or use the output of the commands). Tell the user exactly which plugins are now enabled or disabled for this project. Tell them that the change is in `.claude/settings.local.json` (personal, ignored by git), and that `.claude/settings.json` did not change.
