# unshittify

A Claude Code plugin marketplace: eight plugins of skills and subagents, plus
three hook scripts that hold a few working habits in place rather than leaving
them to memory.

## Install

Add the marketplace, then install the plugins you want:

```sh
git clone https://github.com/<owner>/unshittify.git ~/src/unshittify
claude plugin marketplace add ~/src/unshittify
claude plugin install racket@unshittify
claude plugin list --json          # confirm what is installed and enabled
```

## The plugins

| Plugin | What it gives you |
|--------|-------------------|
| `local` | Project-local settings (`.claude/settings.local.json`) that `/config` does not expose per-project: theme, model, per-project plugin enable/disable, and a settings audit. |
| `global` | The same audit against `~/.claude/settings.json`, plus a slash-command-only repair for missing hook wiring. |
| `git` | Commit-message drafting in this repo's template, and git-history exploration. |
| `development` | Language-agnostic discipline: a "make changing easy" precondition, and TDD, Normalized Systems Theory, property-test, and efficiency reviews. |
| `cxx` | C++ work: sanitizer builds, structural search with `clang-query`, and editing idioms. |
| `racket` | Nineteen reference skills for Racket - classes, contracts, macros, concurrency, GUI, drawing, testing, packaging - each a `SKILL.md` with a signature-level `reference.md`. |
| `communication` | Reviews drafted prose against a written style bar before it reaches you; aligns markdown tables. |
| `meta` | Skills for authoring new skills and agents in this repository's house style. |

## The hooks

`hooks/` is not a plugin and the marketplace manifest does not load it. These
are three bash scripts you wire into `~/.claude/settings.json` yourself, by
absolute path, after which they apply in **every** project on the machine -
not only in this one.

| Script | Event | What it does |
|--------|-------|--------------|
| `enforce-prose-review.sh` | `Stop` | Blocks ending a turn when the final message is substantial prose that the `communication:prose-reviewer` agent has not seen. |
| `enforce-code-review.sh` | `Stop` | Blocks ending a turn when a file was changed but the four required reviews did not all run. Counts changes made through `Bash` and through a delegated subagent, not only through the `Edit` tool. |
| `confirm-git-commit-push.sh` | `PreToolUse` (`Bash`) | Denies `git commit` until the message has been prose-reviewed; asks before any commit or push. |

### Wiring them up

Either run `/global:check-settings`, which reports exactly what is missing,
then `/global:repair-hook-wiring`, which adds it with your approval - or edit
`~/.claude/settings.json` by hand:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [
          { "type": "command", "command": "bash /home/you/src/unshittify/hooks/enforce-prose-review.sh" },
          { "type": "command", "command": "bash /home/you/src/unshittify/hooks/enforce-code-review.sh" }
      ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
          { "type": "command", "command": "bash /home/you/src/unshittify/hooks/confirm-git-commit-push.sh" }
      ] }
    ]
  }
}
```

Substitute your own checkout path. The scripts need `bash`, `jq`, and `awk`.

Two things are worth knowing before you turn them on. They are global, so a
hook that blocks a turn blocks it in every repository you open, not just this
one. And `enforce-code-review.sh` treats delegation to any subagent it does
not recognise as a possible file change, because a subagent's edits are
recorded in the subagent's transcript and never reach the one the hook is
handed; the cost is a redundant review after delegating to an agent not yet
listed in its `READ_ONLY_AGENTS` table.

## Developing

```sh
tests/run_tests.sh                   # everything
tests/hooks/run_tests.sh             # the hook scripts (bats)
tests/plugins/run_tests.sh           # the validator's own tests (bats)
tests/plugins/validate-plugins.sh    # the validator, against this repository
shellcheck hooks/*.sh hooks/lib/*.sh
```

`bats` and `shellcheck` are the only external tools needed. Run
`validate-plugins.sh` after any edit under `plugins/` - it is the only thing
that checks the Markdown and JSON, and the defects it catches (a YAML comment
eating half a description, a reference file nothing points at, a renamed tool)
are all invisible on inspection.

`CLAUDE.md` carries the conventions and the reasoning behind them.
