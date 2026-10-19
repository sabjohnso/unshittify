---
description: Draft a new Claude Code subagent (the frontmatter, the tool scope, and the system prompt) for a plugin in this repository. Use when the user asks you to write, create, or add a new agent.
argument-hint: "[plugin name] [agent name and purpose]"
allowed-tools: Read, Write, Glob, Grep, Bash(mkdir -p:*), Bash(tests/plugins/validate-plugins.sh:*)
---

# Write a new agent

Goal: produce an agent Markdown file at `plugins/<plugin>/agents/<agent-name>.md` that fits the house style of this repository.

## Anatomy

- Frontmatter fields, in this order:
  - `name` (required). Lowercase, with hyphens. It matches the filename (`agents/<name>.md`).
  - `description` (required). Third person. It states what the agent does and when to call it (on its own initiative, from a workflow, or when the user asks for it by name). The harness matches against this field, so name concrete triggers, not only a topic.
  - `tools` (required). A plain list of tool names with commas (`Read, Grep, Glob, Bash`), with the least privilege: only what the steps of the agent use. Unlike the `allowed-tools` of a skill, the agents of this repository do not scope individual Bash subcommands here. Keep it to tool names. `tests/plugins/validate-plugins.sh` rejects a token with parentheses in the `tools` of an agent, and it accepts one in the `allowed-tools` of a skill. Narrow the Bash use of an agent in its body instead. State what it can run.
  - `model` (required). Every agent in this repository names its model. None inherits the model of the caller. Use `haiku` when the task is narrow and mechanical: an audit, a lookup, a fixed reformat, or a template fill whose output a different agent reviews. `git:commit-writer` drafts prose on `haiku` for exactly that reason. The `communication:prose-reviewer` gate checks its output. Use `sonnet` when the task requires open judgement or generation with no such gate behind it: a review, or an edit to real code. A named model means that the cost and the capability of an agent do not change with the model of the session.
- **Quote each frontmatter value that holds a space and then a `#`.** YAML ends an unquoted scalar at that point. So a description that mentions a `#:keyword` reaches the harness cut in half. It usually loses the trigger clause that makes the agent selectable at all, while the file on disk reads correctly. Four Racket skill descriptions shipped this way before anybody saw it. `tests/plugins/validate-plugins.sh` now rejects it.
- Body: a `# Title` that matches the role, one short paragraph that sets the scope and the hard boundaries (read-only, never commits, and so on), then sections such as `## Scope`, `## Process`, or a decision map. It ends with what the agent returns to its caller.
- The body prose follows Simplified Technical English (ASD-STE100): the imperative for steps, the active voice, one instruction per sentence, no sentence over 20 words in a step or 25 words in description, no "-ing" verb forms, and "must" for a requirement. The condensed rules are in `plugins/communication/skills/simplified-technical-english/SKILL.md`.

## Skill or agent?

A skill is the default. An agent earns its place when the work needs a context of its own: a scaffold of several files in one pass, a long investigation that must stay out of the main conversation, or a draft that a different agent then reviews (`git:commit-writer`, whose output the `communication:prose-reviewer` gate checks). Reference material is not a reason to add one. `plugins/racket` has a reference skill per topic and no agent at all, because nothing in it is delegated work.

An agent that restates the rules of a skill, as `meta:agent-writer` restates this file, is held together with its skill only by the author. When one copy changes, change the other in the same edit. The delegated path is the one that scaffolds files against the old rule with no error.

## Steps

1. Confirm the plugin of the agent. If the plugin does not exist yet, stop and ask. Do not create a new plugin as a side effect.
2. Set the boundaries of the agent before the draft: what it must never do (commit, edit, delete), and what it always returns.
3. Draft the frontmatter: the name, a description with concrete triggers, a minimal tools list, and a model (`haiku` for mechanical work, `sonnet` for judgement) with a reason.
4. Draft the body: the role paragraph with the boundaries, then the process or decision-map sections, then a note on the return format. Write in the second person ("You investigate...", "You draft..."), as the existing agents of this repository do.
5. Create the directory with `mkdir -p plugins/<plugin>/agents`. Then write `agents/<agent-name>.md`.
6. Run `tests/plugins/validate-plugins.sh`. It is the only check of `plugins/`. There is no compiler and no runtime here. It prints one `path:line: message` per violation. Fix everything that it reports before you continue.
7. Report the path that you created and when the agent is expected to run.
