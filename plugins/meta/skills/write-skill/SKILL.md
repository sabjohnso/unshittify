---
description: Draft a new Claude Code skill (the frontmatter, the body, and the directory) for a plugin in this repository. Use when the user asks you to write, create, or add a new skill, or to revise an existing SKILL.md.
argument-hint: "[plugin name] [skill name and purpose]"
allowed-tools: Read, Write, Glob, Grep, Bash(mkdir -p:*), Bash(tests/plugins/validate-plugins.sh:*)
---

# Write a new skill

Goal: produce a `SKILL.md` that fits the house style of this repository, and put it at `plugins/<plugin>/skills/<skill-name>/SKILL.md`.

## Anatomy

- The name of the skill is **not** in the frontmatter. It is the directory name (`skills/<skill-name>/`). Choose a short kebab-case name that also serves as the slash-command name (for example `skills/commit-message/` gives `/git:commit-message`).
- Frontmatter fields, in this order:
  - `description` (required). Third person. It states what the skill does and when to use it, and it ends with a concrete trigger phrase ("Use when the user asks to..."). This is the only field that is always loaded into the context. So it must be specific enough to trigger in the right situations and nowhere else.
  - `argument-hint` (optional). A short hint in brackets, shown beside the slash command, for example `"[module hint]"`.
  - `disable-model-invocation` (optional, bool). Set `true` for a skill that does a consequential action, or that changes a settings file, and that must run only when the user types the slash command. Omit it for a skill that is safe to trigger from the description alone. That covers a consequential action that an explicit-instruction requirement already gates somewhere else. `plugins/git/skills/commit-message/SKILL.md` is a worked example. It omits the field on purpose. A standing instruction already restricts a commit to an explicit user request, and `hooks/confirm-git-commit-push.sh` confirms before the `git commit` runs. A gate on that skill behind the literal slash command only makes a bypass with a freehand message easier.
  - `allowed-tools` (optional). Scope the tool access as tightly as the task permits. Prefer an argument-scoped Bash pattern (`Bash(git status:*)`) over a bare `Bash`. List only the tools that the steps use.
- **Quote each frontmatter value that holds a space and then a `#`.** YAML ends an unquoted scalar at that point. So a description that mentions a Racket `#:keyword` reaches the harness cut in half. It usually loses the `Use when...` clause that makes the skill triggerable at all, while the file on disk reads correctly. Four Racket descriptions shipped this way before anybody saw it. `tests/plugins/validate-plugins.sh` now rejects it.
- Body: start with a one-line `Goal:` statement, then the reference material (tables, decision maps) that the skill needs, then a section of numbered steps (`## Steps`, or `## 1. ...`, `## 2. ...`).
- The body prose follows Simplified Technical English (ASD-STE100): the imperative for steps, the active voice, one instruction per sentence, no sentence over 20 words in a step or 25 words in description, no "-ing" verb forms, and "must" for a requirement. The condensed rules are in `plugins/communication/skills/simplified-technical-english/SKILL.md`.
- Keep everything in the single `SKILL.md` file. A skill in this repository does not use a `references/`, `scripts/`, or `assets/` subdirectory. Add one only when the content cannot fit inline (for example a large lookup table, or a script that must run deterministically), and say why.

## Steps

1. Confirm the plugin of the skill and its directory: `plugins/<plugin>/skills/<skill-name>/`. If the plugin does not exist yet, stop and ask. Do not create a new plugin as a side effect.
2. Work out two to four concrete example calls of the skill, if the request does not make them clear. They decide the trigger phrase of the description and the steps of the body.
3. Draft the frontmatter: the description, an argument-hint if the skill takes user input, disable-model-invocation only if the action is consequential or changes a settings file and nothing else restricts it, and allowed-tools scoped to what the steps call.
4. Draft the body: the `Goal:` line, a reference or map section if necessary, then the numbered steps in the imperative ("Run X", "Confirm Y"), not in the second person ("You should...").
5. Create the directory with `mkdir -p plugins/<plugin>/skills/<skill-name>`. Then write `SKILL.md`.
6. Run `tests/plugins/validate-plugins.sh`. It is the only check of `plugins/`. There is no compiler and no runtime here. It prints one `path:line: message` per violation. Fix everything that it reports before you continue.
7. Report the path that you created and the phrase that triggers it. If `disable-model-invocation` is set, report that the skill requires the explicit slash command.
