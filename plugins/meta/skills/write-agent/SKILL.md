---
description: Draft a new Claude Code subagent — frontmatter, tool scope, and system prompt — for a plugin in this repository. Use when the user asks to write, create, or add a new agent.
argument-hint: "[plugin name] [agent name and purpose]"
allowed-tools: Read, Write, Glob, Grep, Bash(mkdir -p:*), Bash(tests/plugins/validate-plugins.sh:*)
---

# Write a new agent

Goal: produce an agent Markdown file at `plugins/<plugin>/agents/<agent-name>.md` that fits this repository's house style.

## Anatomy

- Frontmatter fields, in this order:
  - `name` (required) — lowercase, hyphenated, matches the filename (`agents/<name>.md`).
  - `description` (required) — third person, states what the agent does and when to invoke it (proactively, from a workflow, or when the user asks for it by name). This is what the harness matches against, so name concrete triggers, not just a topic.
  - `tools` (required) — a plain comma-separated list of tool names (`Read, Grep, Glob, Bash`), least privilege: only what the agent's steps actually need. Unlike skill `allowed-tools`, this repo's agents do not scope individual Bash subcommands here — keep it to tool names. `tests/plugins/validate-plugins.sh` rejects a parenthesised token in an agent's `tools` while still accepting one in a skill's `allowed-tools`. Narrow an agent's Bash use in its body instead, by stating what it may run.
  - `model` (required) — every agent in this repository names its model; none inherit the caller's. Use `haiku` when the task is narrow and mechanical: an audit, a lookup, a fixed reformatting, or filling a template whose output another agent reviews (`git:commit-writer` drafts prose on `haiku` for exactly that reason — the `communication:prose-reviewer` gate checks its output). Use `sonnet` when the task requires open-ended judgment or generation with no such gate behind it: a review, an edit to real code. Naming the model means an agent's cost and capability do not swing with whatever model the session happens to be using.
- **Quote any frontmatter value containing a space followed by `#`.** YAML ends an unquoted scalar at that point, so a description mentioning a `#:keyword` reaches the harness cut in half — usually losing the trigger clause that makes the agent selectable at all, while the file on disk still reads correctly. Four Racket skill descriptions shipped this way before anything noticed. `tests/plugins/validate-plugins.sh` now rejects it.
- Body: a `# Title` matching the role, one short paragraph establishing scope and any hard boundaries (read-only, never commits, etc.), then sections such as `## Scope`, `## Process`, or a decision map, ending with what the agent should return to its caller.

## Skill or agent?

A skill is the default. An agent earns its place when the work needs a context of its own: scaffolding several files in one pass, a long investigation that should stay out of the main conversation, or a draft that another agent then reviews (`git:commit-writer`, whose output the `communication:prose-reviewer` gate checks). Reference material is not a reason to add one — `plugins/racket` carries a reference skill per topic and no agent at all, because nothing in it is delegated work.

An agent that restates rules a skill also states — as `meta:agent-writer` restates this file — is held together with its skill by nothing but the author. Whenever one copy changes, change the other in the same edit; the delegated path is the one that silently keeps scaffolding files against the old rule.

## Steps

1. Confirm which plugin the agent belongs to. If it doesn't exist yet, stop and ask — do not create a new plugin as a side effect.
2. Establish the agent's boundaries before drafting: what it must never do (commit, edit, delete), and what it always returns.
3. Draft frontmatter: name, description with concrete triggers, minimal tools list, and a model (`haiku` for mechanical work, `sonnet` for judgment) with a reason.
4. Draft the body: role paragraph with boundaries, then process/decision-map sections, then a return-format note — write in second person ("You investigate...", "You draft..."), matching this repo's existing agents.
5. Create the file with `mkdir -p plugins/<plugin>/agents` then write `agents/<agent-name>.md`.
6. Run `tests/plugins/validate-plugins.sh`. It is the only check over `plugins/` — there is no compiler and no runtime here — and it prints one `path:line: message` per violation. Fix everything it reports before going on.
7. Report the path created and when the agent is expected to be invoked.
