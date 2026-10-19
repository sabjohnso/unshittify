---
description: Review a diff, a file, or a commit range against the strict TDD (red-green-refactor) requirement of this project in CLAUDE.md. A failed test must come before each implementation. The implementation must be the minimum that the tests demand. A refactor must not change what the tests assert. Use automatically after each code change (a bug fix, a new feature, a refactor) as a standing postcondition on the change, not only when the user explicitly asks for a review of TDD compliance or an audit of the red-green-refactor discipline.
argument-hint: "[file path, commit range, or none for working tree changes]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git status:*)
---

# Review code against the Test-Driven Development discipline

Goal: confirm that a failed test, written first, demanded the production code under review. Confirm that the implementation is no more than the tests require. Confirm that each change labeled as a refactor left the test assertions unchanged.

## Checklist

1. **Red before green.** A commit (or hunk) that adds or changes production code, with no earlier commit that adds a test that failed against the old code. The order matters. A test in the same commit as the implementation that it exercises is acceptable only if the commit history of the project shows the same pattern at other places. A test added *after* the implementation that it exercises is not TDD, whatever the commit grouping.
2. **Minimum implementation.** Code in the reviewed change that no test exercises: unused parameters, untaken branches, error handling for a case that no test constructs, or generality (extra options, abstraction layers) beyond what the current tests require.
3. **A refactor keeps the assertions.** A change that is labeled or shaped as a refactor (a restructure with no behavior change) but also edits test assertions, adds new assertions, or changes expected values. If the assertions changed, this is new behavior that needs its own red step, not a refactor.
4. **Passed tests as evidence, not assumed correctness.** Flag each claim in a commit message or a comment that the code is "correct" or "complete", unless the commit refers to or reproduces the output of the matching test run.

## Steps

1. Set the scope: a file path, an explicit commit range, or (by default) the pending changes of the working tree through `git status` and `git diff`. If the commits are separable, use `git log --oneline` and `git show` per commit to inspect the order.
2. For each production-code hunk in the scope, find the tests that exercise it. If none exists, flag the hunk as untested. That is a TDD violation, whether the code is correct or not.
3. Where the commit history is available, check whether a test commit comes before the implementation commit that it justifies. If the test and the implementation are in a single commit, note that the history alone cannot show the order, and say so. Do not guess.
4. For each tested hunk, judge the minimality against the second item of the checklist. Does the code do only what the current tests require?
5. For each change presented as a refactor, diff the test files specifically and confirm that no assertion moved.
6. Report the findings in the groups red, green, and refactor. Give each one a file and line or a commit hash, and the concrete gap, not a restatement of the rule. State explicitly if nothing violates the discipline.
7. Do not apply fixes automatically. This skill reports. Edit code or tests only if the user separately asks you to apply the fix.
