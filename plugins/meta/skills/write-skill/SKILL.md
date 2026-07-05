---
description: Draft a new Claude Code skill — frontmatter, body, and directory placement — for a plugin in this repository. Use when the user asks to write, create, or add a new skill, or to revise an existing SKILL.md.
argument-hint: "[plugin name] [skill name and purpose]"
disable-model-invocation: true
allowed-tools: Read, Write, Glob, Grep, Bash(mkdir -p:*)
---

# Write a new skill

Goal: produce a `SKILL.md` that fits this repository's house style and place it at `plugins/<plugin>/skills/<skill-name>/SKILL.md`.

## Anatomy

- The skill's name is **not** written in frontmatter — it is the directory name (`skills/<skill-name>/`). Choose a short, kebab-case name that doubles as the slash-command name (e.g. `skills/commit-message/` → `/git:commit-message`).
- Frontmatter fields, in this order:
  - `description` (required) — third person, states what the skill does and when to use it, ending with concrete trigger phrasing ("Use when the user asks to..."). This is the only field always loaded into context, so it must be specific enough to trigger correctly and nowhere else.
  - `argument-hint` (optional) — a short bracketed hint shown next to the slash command, e.g. `"[module hint]"`.
  - `disable-model-invocation` (optional, bool) — set `true` for skills that perform a consequential or scoped action (committing, changing settings) that should only run when the user explicitly types the slash command, never inferred from conversation. Omit it only for skills that are safe to auto-trigger from the description alone.
  - `allowed-tools` (optional) — scope tool access as tightly as the task allows. Prefer argument-scoped Bash patterns (`Bash(git status:*)`) over a bare `Bash`, and list only the tools actually needed.
- Body: start with a one-line `Goal:` statement, then any reference material (tables, decision maps) the skill needs, then a numbered steps section (`## Steps` or `## 1. ...`, `## 2. ...`).
- Keep everything in the single `SKILL.md` file. Skills in this repo do not use `references/`, `scripts/`, or `assets/` subdirectories — only add one if the content genuinely cannot fit inline (e.g. a large lookup table, or a script that must run deterministically), and say why.

## Steps

1. Confirm which plugin the skill belongs to and its directory: `plugins/<plugin>/skills/<skill-name>/`. If the plugin doesn't exist yet, stop and ask — do not create a new plugin as a side effect.
2. Work out 2-4 concrete example invocations of the skill, if not already clear from the request — they determine the description's trigger phrasing and the body's steps.
3. Draft the frontmatter: description, argument-hint if the skill takes user input, disable-model-invocation if the action is consequential or scoped, allowed-tools scoped to what the steps actually call.
4. Draft the body: `Goal:` line, any reference/mapping section, then numbered steps written in imperative form ("Run X", "Confirm Y"), not second person ("You should...").
5. Create the file with `mkdir -p plugins/<plugin>/skills/<skill-name>` then write `SKILL.md`.
6. Report the path created and, briefly, what phrase should trigger it (or that it requires the explicit slash command, if `disable-model-invocation` is set).
