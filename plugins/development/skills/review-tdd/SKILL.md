---
description: Review a diff, file, or commit range against this project's strict TDD (red-green-refactor) requirement in CLAUDE.md — that a failing test preceded any implementation, that the implementation is the minimum the tests demand, and that refactors did not change what the tests assert. Use automatically after any code is added or changed — a bug fix, a new feature, a refactor — as a standing post-condition on the change, not only when the user explicitly asks to review for TDD compliance or audit red-green-refactor discipline.
argument-hint: "[file path, commit range, or none for working tree changes]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git status:*)
---

# Review code against Test-Driven Development discipline

Goal: confirm that reviewed production code was demanded by a failing test written first, that the implementation is no more than the tests require, and that anything labeled a refactor left test assertions unchanged.

## Checklist

1. **Red before green** — a commit (or hunk) that adds or changes production code with no preceding commit adding a test that would have failed against the old code. Order matters: a test added in the same commit as the implementation it exercises is acceptable only if the commit history elsewhere in the project treats that as this project's convention; a test added *after* the implementation it exercises is not TDD regardless of commit grouping.
2. **Minimum implementation** — code in the reviewed change that no test exercises: unused parameters, untaken branches, error handling for a case no test constructs, generality (extra options, abstraction layers) beyond what the current tests require.
3. **Refactor preserves assertions** — a change labeled or shaped as a refactor (restructuring without behavior change) that also edits test assertions, adds new assertions, or changes expected values. If assertions changed, this is new behavior needing its own red step, not a refactor.
4. **Passing tests as evidence, not assumed correctness** — flag any claim in a commit message or comment that code is "correct" or "complete" without the corresponding test run's output being referenced or reproducible.

## Steps

1. Determine scope: a file path, an explicit commit range, or (default) the working tree's pending changes via `git status` and `git diff`. If commits are separable, use `git log --oneline` and per-commit `git show` to inspect ordering.
2. For each production-code hunk in scope, find the test(s) that exercise it. If none exist, flag it as untested — a TDD violation independent of whether the code is correct.
3. Where commit history is available, check whether a test commit precedes the implementation commit it justifies. If the test and implementation are combined into a single commit, note that ordering cannot be verified from history alone and say so rather than guessing.
4. For each tested hunk, judge minimality against the checklist's second item — does the code do only what current tests require?
5. For any change presented as a refactor, diff the test files specifically and confirm no assertions moved.
6. Report findings grouped by red / green / refactor, each with a file:line or commit hash and the concrete gap — not a restatement of the rule. State explicitly if nothing violates the discipline.
7. Do not apply fixes automatically — this skill reports; only edit code or tests if the user separately asks for the fix to be applied.
