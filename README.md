# unshittify

A Claude Code plugin marketplace. It holds eight plugins of skills and
subagents, plus three hook scripts. The hooks hold some working habits in
place, so the habits do not depend on memory.

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
| `local` | Project-local settings (`.claude/settings.local.json`) that `/config` does not show per project: the theme, the model, the plugins that are enabled per project, and a settings audit. |
| `global` | The audit again, against `~/.claude/settings.json`. It runs the checks of `local`, less the two that only apply inside a project, plus one check that the hook scripts of a marketplace are wired into the file. A slash-command-only repair adds the wiring when it is absent. |
| `git` | A draft of a commit message in the template of this repository, and an exploration of the git history. |
| `development` | Language-agnostic discipline: a "make changing easy" precondition, and the reviews for test-driven development, Normalized Systems Theory, property tests, and efficiency. |
| `cxx` | C++ work: sanitizer builds, structural search with `clang-query`, and editing idioms. |
| `racket` | Reference skills for Racket: classes, contracts, macros, concurrency, exceptions, GUI, drawing, testing, packaging, and more. Each one is a `SKILL.md` with a signature-level `reference.md` beside it. |
| `communication` | Holds the condensed rules of Simplified Technical English (ASD-STE100), reviews prose against STE and the house style, and aligns markdown tables. |
| `meta` | Skills that write new skills and agents in the house style of this repository. |

## The hooks

`hooks/` is not a plugin, and the marketplace manifest does not load it. It
holds three bash scripts. You wire them into `~/.claude/settings.json`
yourself, by absolute path. After that, they apply in **every** project on
the machine, not only in this one.

| Script | Event | What it does |
|--------|-------|--------------|
| `enforce-prose-review.sh` | `Stop` | Blocks the end of a turn when the final message is substantial prose that the `communication:prose-reviewer` agent did not see. That agent checks Simplified Technical English first. |
| `enforce-code-review.sh` | `Stop` | Blocks the end of a turn when a file changed but not all of the four required reviews ran. It counts the changes made through `Bash` and through a delegated subagent, not only through the `Edit` tool. |
| `confirm-git-commit-push.sh` | `PreToolUse` (`Bash`) | Denies `git commit` until the prose reviewer has seen the message. Asks before each commit and each push. |

### How to wire them

Run `/global:check-settings`, which reports exactly what is absent. Then run
`/global:repair-hook-wiring`, which adds it after your approval. Or edit
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

Put the path of your own checkout in place of the example path. The scripts
need `bash`, `jq`, and `awk`.

Know two things before you turn them on. The hooks are global. A hook that
blocks a turn blocks it in every repository that you open, not only in this
one. And `enforce-code-review.sh` treats a delegation to an unknown subagent
as a possible file change. The edits of a subagent go to the transcript of
the subagent, and they never reach the transcript that the hook gets. The
`READ_ONLY_AGENTS` table of that hook is a judgement about what each listed
agent is told to do. It is not a fact read from the `tools:` line of the
agent. No entry is in the table because it looks harmless there. Every agent
in this repository holds a tool that writes: `Bash`, or `Edit` in the case of
`communication:prose-reviewer`. A delegation to an agent that is not in the
table costs a redundant review. For `communication:prose-reviewer`, the cost
was higher. `enforce-prose-review.sh` demands that agent on every substantial
reply. Until the table exempted it, the two hooks left no move that satisfied
both. One required the review, and the other blocked the turn for the review.

## Development

```sh
tests/run_tests.sh                   # shellcheck, every bats suite, the validator
tests/hooks/run_tests.sh             # the hook scripts (bats)
tests/plugins/run_tests.sh           # the tests of the validator (bats)
tests/scripts/run_tests.sh           # scripts/ (bats)
tests/plugins/validate-plugins.sh    # the validator, against this repository
scripts/update-install.sh            # publish your edits to the local install
```

An edit of a file under `plugins/` changes nothing that a live session sees.
An install copies the tree into
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, and the session
loads that copy. `scripts/update-install.sh` refreshes the marketplace,
publishes every plugin again, and then verifies each installed snapshot
against the tree. It exits with a nonzero status if a snapshot is stale. Use
`--dry-run` to see the commands. Use `--verify-only` to check for stale
snapshots and change nothing.

The verification matters because `claude plugin update` keys on the version
string alone. It reports a plugin edited with no version increase as current,
and the stale copy stays in place. The script reinstalls those plugins and
does not update them.

`.github/workflows/tests.yml` runs `tests/run_tests.sh` on every push and
pull request. So one command settles the question locally and in continuous
integration. It runs `shellcheck` first, over the hooks, the validator, and
the runners themselves.

The test suites need `bats` and `shellcheck`. The hook scripts and the
validator need only `bash`, `jq`, and `awk`. Run `validate-plugins.sh` after
each edit under `plugins/`. It is the only check of the Markdown and the
JSON. The defects that it catches are invisible to the eye: a YAML comment
that removes half of a description, a reference file that nothing points to,
and a renamed tool.

`CLAUDE.md` holds the conventions and the reasons behind them.
