---
description: Review code (a diff, a file, or the pending changes of the working tree) against the Normalized Systems Theory (NST) principles of this project for evolvable code (encapsulation, separation of concerns, interfaces and not implementations, composition over inheritance, local reasoning, small focused units, declarative style, isolated side effects, the open-closed principle, and refactor-friendly tests). Report each violation with its principle and a concrete fix. Use automatically after each code change (a bug fix, a new feature, a refactor) as a standing postcondition on the change, not only when the user explicitly asks for a review of evolvability or NST compliance.
argument-hint: "[file path, or none for working tree changes]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git status:*), Bash(git log:*), Bash(git show:*)
---

# Review code against Normalized Systems Theory

Goal: find the concrete places where the code under review violates one of the ten evolvable-code principles in CLAUDE.md. Name the principle and propose the specific fix. Do not restate the principle.

## Checklist

For each item, look for the structural problem itself, not only for names or keywords that hint at it.

1. **Encapsulation.** Internal state or a private helper that is reachable from outside its own module or class. A caller that reaches past an interface into the internals of another component to save some lines.
2. **Separation of concerns.** A function or class that mixes what it computes with how the result is stored or how it is presented (for example a handler that parses the input, issues a database write, and formats the response).
3. **Interfaces, not implementations.** A consumer that depends on a concrete type or class where an abstract type, a protocol, or a contract is enough. This matters most when it blocks a swap of the implementation without an edit of the consumer.
4. **Composition over inheritance.** A subclass built to reuse a bit of unrelated behavior from its parent. A deep inheritance chain where delegation or a higher-order function is flatter and less brittle.
5. **Local reasoning.** A function whose correctness depends on global mutable state, on the call order, or on a side effect at another place in the file. All that you cannot understand from its own body and signature.
6. **Small, focused units.** A function or module that does more than one job. You can identify it by the "and" that its description needs, or by a name that lists several responsibilities.
7. **Declarative over imperative.** A hand-written loop or a manual state machine that does what a `map`, `filter`, or `reduce`, a query, or a pattern match expresses more directly.
8. **Isolated side effects.** I/O, mutation, or a log call mixed with pure computation, instead of pushed to the edges (functional core, imperative shell).
9. **Open-closed.** A new case handled with an edit of an existing `if` or `switch` chain across several call sites, instead of a new case through an existing extension point (polymorphism, a registered handler, configuration).
10. **Refactor-friendly tests.** A test that asserts on a private method, an internal data structure, or a call sequence instead of the observable input and output behavior. A test that breaks under a pure refactor that keeps the behavior.

Also flag, where it applies, the two version-transparency properties: a change to the internals of a module that forced an edit of its dependents (action version transparency), or a data-format change that leaked past the boundary of the module instead of an absorption inside it (data version transparency).

## Steps

1. Get the code to review. If you get a file path, read it. If you get a diff or nothing, run `git diff` (or `git diff --staged` if the working tree is clean but the index is not) to get the pending changes. Use `git log` and `git show` only if you need more history to judge whether a change is a violation or a deliberate divergence that is already justified at another place.
2. Apply the checklist above to the code under review. For each hit, record: the file and line, the principle that it violates, a one-sentence statement of the concrete failure mode (not a restatement of the principle), and a specific proposed fix.
3. Skip code that violates a principle for a reason already justified in a comment, in a commit message, or by the exception of CLAUDE.md for code that was not written with these principles. Note the exception instead of a new flag.
4. Report the findings in the order of the principles, with the most violated principle first. If nothing violates the checklist, say so. Do not invent a finding.
5. Do not apply fixes automatically. This skill reports. Edit the code only if the user separately asks you to apply the fix.
