---
description: Review code — a diff, a file, or the working tree's pending changes — against this project's Normalized Systems Theory (NST) principles for evolvable code (encapsulation, separation of concerns, programming to interfaces, composition over inheritance, local reasoning, small focused units, declarative style, isolated side effects, the open-closed principle, and refactor-friendly tests), and report each violation with its principle and a concrete fix. Use automatically after any code is added or changed — a bug fix, a new feature, a refactor — as a standing post-condition on the change, not only when the user explicitly asks to review for evolvability or NST compliance.
argument-hint: "[file path, or none for working tree changes]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git status:*), Bash(git log:*)
---

# Review code against Normalized Systems Theory

Goal: find concrete places where reviewed code violates one of the ten evolvable-code principles in CLAUDE.md, name the principle, and propose the specific fix — not a restatement of the principle.

## Checklist

For each item, look for the code smell, not just the absence of a keyword.

1. **Encapsulation** — internal state or a private helper reachable from outside its owning module/class; a caller that reaches past an interface into another component's internals to save a few lines.
2. **Separation of concerns** — a function or class mixing what it computes with how it's stored or how it's presented (e.g. a handler that both parses input and issues a database write and formats the response).
3. **Program to interfaces, not implementations** — a consumer that depends on a concrete type/class where an abstract type, protocol, or contract would do, especially if it blocks swapping the implementation without editing the consumer.
4. **Composition over inheritance** — a subclass built to reuse a bit of unrelated behavior from its parent, or a deep inheritance chain where delegation or a higher-order function would be flatter and less brittle.
5. **Local reasoning** — a function whose correctness depends on global mutable state, call order, or a non-obvious side effect elsewhere in the file; anything that can't be understood by reading its own body and signature.
6. **Small, focused units** — a function or module doing more than one job, identifiable by needing "and" to describe what it does, or by a name that lists multiple responsibilities.
7. **Declarative over imperative** — a hand-rolled loop or manual state machine doing what a `map`/`filter`/`reduce`, a query, or a pattern match would express more directly.
8. **Isolated side effects** — I/O, mutation, or logging interleaved with pure computation, rather than pushed to the edges (functional core, imperative shell).
9. **Open-closed** — a new case handled by editing an existing `if`/`switch` chain across multiple call sites, rather than by adding a new case through an existing extension point (polymorphism, a registered handler, configuration).
10. **Refactor-friendly tests** — a test that asserts on a private method, an internal data structure, or call sequence rather than observable input/output behavior; a test that would break from a pure refactor that preserves behavior.

Also flag, where relevant, the two version-transparency properties: a change to a module's internals that forced an edit to its dependents (action version transparency), or a data-format change that leaked past the module's boundary instead of being absorbed by it (data version transparency).

## Steps

1. Obtain the code to review: if given a file path, read it; if given a diff or nothing, run `git diff` (or `git diff --staged` if the working tree is clean but the index isn't) to get the pending changes; use `git log`/`git show` only if more history is needed to judge whether a change is a violation or a deliberate divergence already justified elsewhere.
2. Walk the checklist above against the reviewed code. For each hit, record: the file:line, which principle it violates, a one-sentence statement of the concrete failure mode (not a restatement of the principle), and a specific proposed fix.
3. Skip code that violates a principle for a reason already justified in a comment, commit message, or CLAUDE.md's own carve-out for pre-existing code not written with these principles in mind — note the carve-out instead of re-flagging it.
4. Report findings ordered by principle, most-violated first. If nothing violates the checklist, say so rather than inventing a finding.
5. Do not apply fixes automatically — this skill reports; only edit the code if the user separately asks for the fix to be applied.
