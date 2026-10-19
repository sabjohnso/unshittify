---
description: "Review code (a diff, a file, or the pending changes of the working tree) for wasted computation that costs the user time: superlinear work where linear work is enough, redundant recomputation, repeated or avoidable I/O, quadratic rebuilds, needless materialization, missing early exits, and wrong data structures. Report each one with its cost class and a concrete fix. Use automatically after each code change (a bug fix, a new feature, a refactor) as a standing postcondition on the change, not only when the user explicitly asks for a review of efficiency or performance."
argument-hint: "[file path, or none for working tree changes]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git status:*), Bash(git log:*), Bash(git show:*)
---

# Review code for an efficient use of the time of the user

Goal: find the concrete places where the code under review wastes computation that the user waits on. Name the cost class and propose the specific fix. Do not give a generic call to "optimize".

## The value order (it governs the ranking and the trade-offs)

A saved unit of the **time of the user** (the wall-clock latency that they wait on, their attention, their rework) is worth far more than a saved unit of **usage credits or compute**. Both matter. When they conflict, optimize for the time of the user. Never recommend a change that trims credits or compute at the cost of the time of the user or the readability of the code. Put the findings that cut what the user waits on first.

An inefficiency that the user waits on costs that time again on every iteration that it survives. So its accumulated cost is far larger than the one-time cost of the fix. Recommend an immediate fix. Do not let it persist across several cycles. The time spent on the fix now is repaid the first few times that the user would otherwise wait on it.

## Guards (consistent with the Readability First rule of CLAUDE.md)

- Flag only waste that costs real time at realistic input sizes. A quadratic pass over a list that always has three elements is not a finding.
- Do not recommend a micro-optimization or a clever rewrite that trades clarity for an unmeasured gain. Per CLAUDE.md, a nontrivial optimization requires benchmark or profile evidence, and it keeps the simple reference implementation beside it. Say so. Do not assert a speed gain.
- Prefer the fix that is both faster and clearer (for example a keyed lookup in the place of a nested scan). Where the faster rewrite hurts the readability, say plainly that it is not worth it.

## Checklist

For each item, look for the wasteful pattern itself, not only for names or keywords that hint at it.

1. **Superlinear where linear is enough.** A nested loop or a repeated linear scan that does an O(n²) membership or join test, where a hash or set lookup or a single pass does it in O(n). A `list.contains`, `in`, or `find` inside a loop over the same collection.
2. **Redundant recomputation.** A loop-invariant value, or a pure call with unchanged arguments, computed again on every iteration instead of once above the loop. The same derived result computed several times across a function.
3. **Repeated or avoidable I/O.** A second read of a file, a second issue of a query, or a second fetch of a resource that is already in memory. A query inside a loop where one batched query is enough (the N+1 pattern). An open, a flush, or a close of a handle per iteration.
4. **A rebuild instead of an accumulation.** A reconstruction of a whole collection or string on each iteration (quadratic concatenation, `list = list + [x]` in a loop), instead of an accumulation into one structure and one build of the result.
5. **Needless materialization or dead work.** A build of a full intermediate collection only to take one element or to reduce it at once. A load or a computation of more than the result needs. Work whose output is never used.
6. **A missing early exit.** A scan of a whole structure when the answer is settled after the first match, with no short circuit (no `break`, `any`, or `return` on the first hit).
7. **The wrong data structure.** A list used for frequent membership tests or deduplication, where a set or a map is the right tool. A linear structure where the code repeatedly needs random access or a keyed lookup.

## Steps

1. Get the code to review. If you get a file path, read it. If you get a diff or nothing, run `git diff` (or `git diff --staged` if the working tree is clean but the index is not) to get the pending changes. Use `git log` and `git show` only if you need more history to judge whether a change is a real regression or a deliberate choice that is already justified.
2. Apply the checklist above to the code under review. For each hit, record: the file and line, the item that it fails, a one-sentence statement of the concrete failure mode (not a restatement of the item), the cost class that changes (for example O(n²) to O(n), or N+1 queries to 1), and a specific proposed fix.
3. Skip code whose apparent waste is justified in a comment, in a commit message, or by input sizes that stay small. Note the justification instead of a new flag. Skip each "optimization" that only saves compute at the cost of the readability, and say why.
4. Rank the findings by their impact on the time of the user. A slow path that the user waits on ranks above a wasteful loop that runs unattended, whichever burns more compute. If nothing wastes the time of the user, say so. Do not invent a finding.
5. Do not apply fixes automatically. This skill reports. Edit the code only if the user separately asks you to apply the fix.
