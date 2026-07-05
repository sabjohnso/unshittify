# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`unshittify` is a Claude Code **plugin marketplace**: a `.claude-plugin/marketplace.json` listing six plugins under `plugins/`, each a self-contained bundle of skills (`skills/<name>/SKILL.md`) and subagents (`agents/<name>.md`). Everything under `plugins/` is a JSON manifest or a Markdown prompt that the Claude Code harness loads directly — no application code, no build step, no test suite. The one exception is `hooks/` (below), which is real bash code with its own test suite.

Plugins:
- `local` — manage project-local settings (`.claude/settings.local.json`): theme, model, per-project plugin enable/disable, a settings-doctor audit.
- `global` — same settings-doctor audit, scoped to `~/.claude/settings.json` instead.
- `git` — commit-message drafting and git-history exploration agents/skills.
- `meta` — skills for authoring new skills and agents *for this repository*, encoding this repo's own house style.
- `communication` — reviews drafted prose against this repo's style bar before it reaches the user.
- `racket` — a large, mostly independent set of reference skills for the Racket language (classes, contracts, macros, GUI, testing, packaging, etc.), each with a `SKILL.md` + `reference.md` pair.

## Commands

There is nothing to compile or test under `plugins/`. The only verification available there is:

- **Validate a manifest edit**: `python3 -m json.tool <file>` (or `jq . <file>`) on `.claude-plugin/marketplace.json` or any `plugins/*/.claude-plugin/plugin.json` after editing it, since nothing else will catch a syntax error.
- **List installed plugins / their enabled state**: `claude plugin list --json`.
- **Exercise a skill or agent manually**: install/enable the plugin locally, then invoke its slash command (e.g. `/local:check-settings`) or trigger its agent by description in a live session — there is no offline harness for this.

For `hooks/`, see the next section.

## The `hooks/` directory

`hooks/` holds personal Claude Code hook scripts (bash) — not a plugin, and not loaded by the marketplace manifest. They are wired into `~/.claude/settings.json` by absolute path, so they take effect globally, in every project, regardless of which repository is the current working directory:

- `hooks/enforce-prose-review.sh` (`Stop`) — blocks ending a turn if the final assistant message is substantial prose and the `communication:review-prose` skill was not invoked on it this turn.
- `hooks/enforce-code-review.sh` (`Stop`) — blocks ending a turn if code was written or edited this turn but the required reviews (TDD, NST, property-tests — each satisfiable via its skill or its matching subagent) were not all invoked since the user's last message.
- `hooks/confirm-git-commit-push.sh` (`PreToolUse`, matcher `Bash`) — asks for confirmation before a `git commit` or `git push` runs, since those require an explicit instruction in the current turn.

Both scripts must pass `shellcheck` cleanly; run it directly (`shellcheck hooks/*.sh`) after editing either one. Both have a test suite under `tests/hooks/`, using `bats` (bats-core) rather than any custom harness — run the whole suite with `tests/hooks/run_tests.sh`. Follow strict TDD when changing this logic: these scripts encode real decision functions (e.g. `enforce-code-review.sh`'s missing-reviews computation has stated laws — monotonicity, order-invariance, duplicate-insensitivity — each pinned by a test in `tests/hooks/enforce-code-review.bats`), not incidental scripting, so a behavior change belongs behind a new failing test first.

## Architecture and conventions specific to this repo

- **Two manifests must stay in sync manually.** Each plugin has its own `plugins/<name>/.claude-plugin/plugin.json` (with its own `description`), and `.claude-plugin/marketplace.json` at the repo root duplicates that description in its `plugins[]` entry. Nothing enforces agreement between them — see commit `665f550` where they drifted. When a plugin's scope or description changes, update both files.
- **Skills vs. agents, and how to author them, is itself documented in-repo**: `plugins/meta/skills/write-skill/SKILL.md` and `plugins/meta/skills/write-agent/SKILL.md` are the canonical rules for frontmatter fields, tool scoping, and body structure for any new `SKILL.md` or agent file added anywhere in this repository. Read those before adding or editing a skill/agent rather than inferring conventions from a single example, since some plugins predate parts of that style guide.
- **Skills in this repo are single-file.** No plugin uses a `skills/<name>/references/`, `scripts/`, or `assets/` subdirectory — everything lives in one `SKILL.md`. The `racket` plugin's `reference.md` alongside each `SKILL.md` is the one exception, kept because those files are large lookup tables, not instructions.
- **The `local` and `global` plugins are parallel by design, not by accident.** `plugins/local/agents/settings-doctor.md` and `plugins/global/agents/settings-doctor.md` (and their matching `check-settings` skills) run the identical set of checks against different files (`.claude/settings.local.json` vs `~/.claude/settings.json`) with different precedence framing. When fixing a bug in one settings-doctor's check logic, check whether the same bug exists in the other — they are not shared via any common file, so nothing keeps them in sync automatically.
- **Commit messages follow a fixed template** (emoji, `[module] <new state, not action taken>` subject, Problem/Solution bullets, closing haiku) — this is codified in `plugins/git/skills/commit-message/SKILL.md` and the `git:commit-writer` agent. Use that skill/agent when asked to commit rather than freehanding a message, so the format stays consistent with the existing log.
- **`.org` files at the repo root are intentionally untracked.** `BadProseExamples.org` (the live catalogue the `communication` plugin's skill/agent read for prior prose failures) and `Review.org` are excluded by the user's global `~/.gitignore` (`*.org`), not this repo's own `.gitignore` (which is empty). If `BadProseExamples.org` is missing on a fresh checkout, that is expected — the communication plugin's skill and agent are written to degrade gracefully when it isn't present; do not try to force it into the repository.
