---
description: Review code — a diff, a file, or the working tree's pending changes — for wasted computation that costs the user time: superlinear work where linear suffices, redundant recomputation, repeated or avoidable I/O, quadratic rebuilding, needless materialization, missing early exits, and wrong data structures. Report each with its cost class and a concrete fix. Use automatically after any code is added or changed — a bug fix, a new feature, a refactor — as a standing post-condition on the change, not only when the user explicitly asks to review for efficiency or performance.
argument-hint: "[file path, or none for working tree changes]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git status:*), Bash(git log:*)
---

# Review code for efficient use of the user's time

Goal: find concrete places where reviewed code wastes computation the user waits on, name the cost class, and propose the specific fix — not a generic call to "optimize."

## Value ordering (governs ranking and trade-offs)

Saving the **user's time** — the wall-clock latency they wait on, their attention, their rework — is worth far more than saving **usage credits or compute**. Both matter, but when they conflict, optimize for the user's time. Never recommend a change that trims credits or compute at the cost of the user's time or the code's readability; prioritize the findings that cut what the user actually waits on.

An inefficiency the user waits on costs that time again on every iteration cycle it survives, so its accumulated cost dwarfs the one-time cost of fixing it. Recommend fixing it immediately rather than letting it persist across multiple cycles — the time spent fixing it now is repaid the first few times the user would otherwise have waited on it.

## Guardrails (consistent with CLAUDE.md's Readability First)

- Flag only waste that bites at realistic input sizes. A quadratic pass over a list that is always three elements is not a finding.
- Do not recommend micro-optimizations or clever rewrites that trade clarity for unmeasured gains. Per CLAUDE.md, a nontrivial optimization requires benchmark or profiling evidence and keeps the simple reference implementation alongside it — say so rather than asserting a speedup.
- Prefer the fix that is both faster and clearer (e.g. a keyed lookup replacing a nested scan). Where the faster rewrite would hurt readability, say plainly that it is not worth it.

## Checklist

For each item, look for the code smell, not just the absence of a keyword.

1. **Superlinear where linear suffices** — a nested loop or repeated linear scan doing an O(n²) membership or join test that a hash/set lookup or a single pass would do in O(n); a `list.contains`/`in`/`find` inside a loop over the same collection.
2. **Redundant recomputation** — a loop-invariant value, or a pure call with unchanging arguments, recomputed on every iteration instead of hoisted once above the loop; the same derived result computed repeatedly across a function.
3. **Repeated or avoidable I/O** — re-reading a file, re-issuing a query, or re-fetching a resource already held in memory; a query inside a loop where one batched query would do (the N+1 pattern); opening, flushing, or closing a handle per iteration.
4. **Rebuilding instead of accumulating** — reconstructing a whole collection or string on each iteration (quadratic concatenation, `list = list + [x]` in a loop) rather than accumulating into one structure and building the result once.
5. **Needless materialization or dead work** — building a full intermediate collection only to take one element or immediately reduce it; loading or computing more than the result needs; work whose output is never used.
6. **Missing early exit** — scanning an entire structure when the answer is settled after the first match, rather than short-circuiting (no `break`/`any`/`return` on the first hit).
7. **Wrong data structure** — a list used for frequent membership or deduplication where a set or map is the right tool; a linear structure where the code repeatedly needs random access or keyed lookup.

## Steps

1. Obtain the code to review: if given a file path, read it; if given a diff or nothing, run `git diff` (or `git diff --staged` if the working tree is clean but the index isn't) to get the pending changes; use `git log`/`git show` only if more history is needed to judge whether a change is a genuine regression or a deliberate, already-justified choice.
2. Walk the checklist above against the reviewed code. For each hit, record: the file:line, which item it fails, a one-sentence statement of the concrete failure mode (not a restatement of the item), the cost class it changes (e.g. O(n²)→O(n), N+1→1 query), and a specific proposed fix.
3. Skip code whose apparent waste is justified in a comment, a commit message, or by input sizes that stay small — note the justification instead of re-flagging it. Skip any "optimization" that would only save compute at the cost of readability, and say why.
4. Rank findings by user-time impact first — a slow path the user waits on outranks a wasteful loop that runs unattended, regardless of which burns more compute. If nothing wastes the user's time, say so rather than inventing a finding.
5. Do not apply fixes automatically — this skill reports; only edit the code if the user separately asks for the fix to be applied.
