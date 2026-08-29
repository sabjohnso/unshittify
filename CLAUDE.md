# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`unshittify` is a Claude Code **plugin marketplace**: a `.claude-plugin/marketplace.json` listing eight plugins under `plugins/`, each a self-contained bundle of skills (`skills/<name>/SKILL.md`) and subagents (`agents/<name>.md`). Everything under `plugins/` is a JSON manifest or a Markdown prompt that the Claude Code harness loads directly — no application code and no build step. It is checked by `tests/plugins/validate-plugins.sh` (below) rather than by a compiler. `hooks/` is real bash code with its own test suite.

Plugins:
- `local` — manage project-local settings (`.claude/settings.local.json`): theme, model, per-project plugin enable/disable, a settings-doctor audit.
- `global` — same settings-doctor audit, scoped to `~/.claude/settings.json` instead.
- `git` — commit-message drafting and git-history exploration agents/skills.
- `meta` — skills for authoring new skills and agents *for this repository*, encoding this repo's own house style.
- `communication` — reviews drafted prose against this repo's style bar before it reaches the user.
- `racket` — a large, mostly independent set of reference skills for the Racket language (classes, contracts, macros, GUI, testing, packaging, etc.), each with a `SKILL.md` + `reference.md` pair.
- `development` — language-agnostic development discipline: the `make-changing-easy` precondition, and the TDD, NST (Normalized Systems Theory), property-test, and efficiency review post-conditions. `hooks/enforce-code-review.sh` requires these four reviews by name, so this plugin is not optional decoration — removing or renaming one of its skills or agents breaks that hook.
- `cxx` — C++ work: sanitizer builds, structural search with clang-query, and this repo's C++ editing idioms.

## Commands

There is nothing to compile under `plugins/`, but it is not unchecked:

- **Validate every plugin file**: `tests/plugins/validate-plugins.sh` — run this after ANY edit under `plugins/`. It checks the whole tree and prints `path:line: message` per violation. See "The `tests/plugins/` validator" below for what it catches and why each check exists.
- **List installed plugins / their enabled state**: `claude plugin list --json`.
- **Exercise a skill or agent manually**: install/enable the plugin locally, then invoke its slash command (e.g. `/local:check-settings`) or trigger its agent by description in a live session — there is no offline harness for this.

For `hooks/`, see the next section.

## The `hooks/` directory

`hooks/` holds personal Claude Code hook scripts (bash) — not a plugin, and not loaded by the marketplace manifest. They are wired into `~/.claude/settings.json` by absolute path, so they take effect globally, in every project, regardless of which repository is the current working directory:

- `hooks/enforce-prose-review.sh` (`Stop`) — blocks ending a turn if the final assistant message is substantial prose and the `communication:prose-reviewer` agent was not invoked on it this turn.
- `hooks/enforce-code-review.sh` (`Stop`) — blocks ending a turn if a file was written or edited this turn but the required reviews (TDD, NST (Normalized Systems Theory), property-tests, efficiency — each satisfiable via its skill or its matching subagent) were not all invoked since the user's last message. "Edited" covers three routes, not just the `Edit` tool: a `Bash` command matching `BASH_WRITE_PATTERNS`, and delegation to any subagent not named in `READ_ONLY_AGENTS`, both count. The auto mode of the harness tells the model to prefer `sed` and heredocs over `Edit`, so watching tool names alone left the gate open on the path the model is actively told to take.
- `hooks/confirm-git-commit-push.sh` (`PreToolUse`, matcher `Bash`) — asks for confirmation before a `git commit` or `git push` runs, since those require an explicit instruction in the current turn. A `git commit` is denied outright until `communication:prose-reviewer` has run in the same turn.
- `hooks/lib/transcript.sh` — sourced by all three, never executed alone. It is the single place that knows the raw JSONL transcript schema: where a turn begins, how `tool_use` events are shaped, and what counts as an exact agent-name match. Change a schema assumption here, not in a hook.

The turn boundary in `transcript.sh` deserves particular care. The harness records several of its OWN messages in the user role with plain string content — a completion notification for an asynchronous subagent, a slash-command marker, local command output — and each one that counts as a boundary discards the evidence of everything the assistant did earlier in the same turn. The task-notification case broke a real guarantee: it is written *after* the `Agent` call that spawned the subagent, so `enforce-prose-review.sh` could never see a review it had just demanded, and every review in this harness is delegated that way. `find_turn_start_line` now rejects harness-authored messages by `origin.kind` and by content shape. Both rules only ever move the boundary *earlier*, which is the safe direction: an earlier boundary can only make a hook see more of the turn, never less.

All the scripts must pass `shellcheck` cleanly; run it (`shellcheck hooks/*.sh hooks/lib/*.sh`) after editing any of them. They have a test suite under `tests/hooks/`, using `bats` (bats-core) rather than any custom harness — run the whole suite with `tests/hooks/run_tests.sh`. Follow strict TDD when changing this logic: these scripts encode real decision functions (e.g. `enforce-code-review.sh`'s missing-reviews computation has stated laws — monotonicity, order-invariance, duplicate-insensitivity — each pinned by a test in `tests/hooks/enforce-code-review.bats`), not incidental scripting, so a behavior change belongs behind a new failing test first.

## The `tests/plugins/` validator

`tests/plugins/validate-plugins.sh` is the only thing that checks the ~4,900 lines of Markdown and JSON that are the actual product. Run it after any edit under `plugins/`:

```
tests/plugins/validate-plugins.sh          # check the repository
tests/plugins/run_tests.sh                 # check the validator itself (bats)
```

It prints one `path:line: message` per violation and exits non-zero if there were any. Every check exists because the corresponding defect had already shipped:

| Check | What shipped broken |
|-------|---------------------|
| unquoted frontmatter scalar containing ` #` | four Racket descriptions truncated mid-sentence by a YAML comment |
| a sibling file the `SKILL.md` never names | thirteen `reference.md` files nothing instructed the model to open |
| unknown tool in `allowed-tools` / `tools` | `Task(...)` left in a skill after the harness renamed that tool to `Agent` |
| the two manifests disagreeing | see commit `665f550` |
| agent missing `name`/`description`/`tools`/`model`, or a name not matching its filename | the rule held only by convention |
| skill missing `description` | a skill with no description can never trigger |

Add a check the same way you would add a hook behaviour: a failing test in `tests/plugins/validate-plugins.bats` first, built on a throwaway fixture tree rather than on live repository content, then the check.

## Architecture and conventions specific to this repo

- **Two manifests state each plugin's description.** Each plugin has its own `plugins/<name>/.claude-plugin/plugin.json`, and `.claude-plugin/marketplace.json` at the repo root duplicates that description in its `plugins[]` entry. They drifted once already — see commit `665f550`. `tests/plugins/validate-plugins.sh` now compares them, and also flags a plugin directory missing from the marketplace manifest. When a plugin's scope or description changes, update both files and run the validator.
- **The skill/agent distinction, and how to author each, is documented in-repo**: `plugins/meta/skills/write-skill/SKILL.md` and `plugins/meta/skills/write-agent/SKILL.md` are the canonical rules for frontmatter fields, tool scoping, and body structure for any new `SKILL.md` or agent file added anywhere in this repository. Read those before adding or editing a skill/agent rather than inferring conventions from a single example, since some plugins predate parts of that style guide.
- **The meta plugin states each authoring rule twice, and nothing keeps the two copies together.** `plugins/meta/skills/write-agent/SKILL.md` and `plugins/meta/agents/agent-writer.md` both carry the house rules for agent frontmatter (and likewise `write-skill/SKILL.md` with `skill-writer.md`), because one is used directly and the other when the work is delegated to a subagent. Changing a rule in the skill without changing it in the matching agent leaves the delegated path scaffolding files that violate the rule the skill just introduced — this happened when the `model` field became required. Update both.
- **Every agent names its model.** Each `plugins/*/agents/*.md` carries a `model` field: `haiku` for mechanical work, `sonnet` for judgment. None inherit the caller's model, so an agent's cost and capability do not change with the session's model. `tests/plugins/validate-plugins.sh` enforces this.
- **Skills in this repo are single-file.** No plugin uses a `skills/<name>/references/`, `scripts/`, or `assets/` subdirectory — everything lives in one `SKILL.md`. The `racket` plugin's `reference.md` alongside each `SKILL.md` is the one exception, kept because those files are large lookup tables, not instructions. **A sibling file is only reachable if the `SKILL.md` body names it** — nothing else tells the model to open it. Thirteen of the nineteen Racket skills once shipped a `reference.md` no `SKILL.md` mentioned, stranding roughly 1,600 lines. The validator now requires the citation.
- **Quote any frontmatter value containing a space followed by `#`.** YAML ends an unquoted scalar there, so a description mentioning a Racket `#:keyword` reaches the harness cut in half — usually losing the `Use when...` clause that makes the skill triggerable at all, while the file on disk still reads correctly. Four Racket skill descriptions shipped this way. The validator now rejects it.
- **The `local` and `global` plugins are parallel by design, not by accident.** `plugins/local/agents/settings-doctor.md` and `plugins/global/agents/settings-doctor.md` (and their matching `check-settings` skills) run the identical set of checks against different files (`.claude/settings.local.json` vs `~/.claude/settings.json`) but describe settings precedence differently. When fixing a bug in one settings-doctor's check logic, check whether the same bug exists in the other — they are not shared via any common file, so nothing keeps them in sync automatically.
- **Commit messages follow a fixed template** (emoji, `[module] <new state, not action taken>` subject, Problem/Solution bullets, closing haiku) — this is codified in `plugins/git/skills/commit-message/SKILL.md` and the `git:commit-writer` agent. Always invoke that skill (or the agent, when delegating to a subagent) for every commit in this repository — never write a commit message without the template — unless the user has explicitly said not to use the template. **The agent drafts only; it never commits.** It holds no tool that can invoke a subagent, so it cannot satisfy `confirm-git-commit-push.sh`'s prose-review gate; its caller runs the reviewer and the commit. The skill is deliberately set up to auto-trigger on any explicit commit request, not only on the literal `/git:commit-message` command, so the format stays consistent with the existing log.
- **`.org` files at the repo root are intentionally untracked.** `BadProseExamples.org` (the live catalogue the `communication` plugin's skill/agent read for prior prose failures) and `Review.org` are excluded by the user's global `~/.gitignore` (`*.org`), not this repo's own `.gitignore` (which is empty). If `BadProseExamples.org` is missing on a fresh checkout, that is expected — the communication plugin's skill and agent are written to degrade gracefully when it isn't present; do not try to force it into the repository.
