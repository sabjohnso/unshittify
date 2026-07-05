---
description: Draft a new Claude Code subagent — frontmatter, tool scope, and system prompt — for a plugin in this repository. Use when the user asks to write, create, or add a new agent.
argument-hint: "[plugin name] [agent name and purpose]"
disable-model-invocation: true
allowed-tools: Read, Write, Glob, Grep, Bash(mkdir -p:*)
---

# Write a new agent

Goal: produce an agent Markdown file at `plugins/<plugin>/agents/<agent-name>.md` that fits this repository's house style.

## Anatomy

- Frontmatter fields, in this order:
  - `name` (required) — lowercase, hyphenated, matches the filename (`agents/<name>.md`).
  - `description` (required) — third person, states what the agent does and when to invoke it (proactively, from a workflow, or when the user asks for it by name). This is what the harness matches against, so name concrete triggers, not just a topic.
  - `tools` (required) — a plain comma-separated list of tool names (`Read, Grep, Glob, Bash`), least privilege: only what the agent's steps actually need. Unlike skill `allowed-tools`, this repo's agents do not scope individual Bash subcommands here — keep it to tool names.
  - `model` — set explicitly (`haiku`, `sonnet`, etc.) when the task is narrow and mechanical (an audit, a lookup); omit it (inherit the caller's model) when the task requires open-ended judgment or generation.
- Body: a `# Title` matching the role, one short paragraph establishing scope and any hard boundaries (read-only, never commits, etc.), then sections such as `## Scope`, `## Process`, or a decision map, ending with what the agent should return to its caller.

## Steps

1. Confirm which plugin the agent belongs to. If it doesn't exist yet, stop and ask — do not create a new plugin as a side effect.
2. Establish the agent's boundaries before drafting: what it must never do (commit, edit, delete), and what it always returns.
3. Draft frontmatter: name, description with concrete triggers, minimal tools list, and a model choice with a reason.
4. Draft the body: role paragraph with boundaries, then process/decision-map sections, then a return-format note — write in second person ("You investigate...", "You draft..."), matching this repo's existing agents.
5. Create the file with `mkdir -p plugins/<plugin>/agents` then write `agents/<agent-name>.md`.
6. Report the path created and when the agent is expected to be invoked.
