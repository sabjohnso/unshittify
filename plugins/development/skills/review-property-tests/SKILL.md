---
description: Review new or changed data types and operations against this project's Algebra Driven Design requirement in CLAUDE.md — that types and operations are designed as algebras with explicit laws, that those laws are verified with property-based tests (QCheck or equivalent) rather than only examples, and that example-based tests (Alcotest or equivalent) are reserved for edge cases and regressions. Use automatically after any code is added or changed — a bug fix, a new feature, a refactor — as a standing post-condition on the change, not only when the user explicitly asks to review property-test coverage or algebra-driven design compliance.
argument-hint: "[file path, or none for working tree changes]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git status:*)
---

# Review code against algebra-driven design and property testing

Goal: for each new or changed data type or operation in scope, confirm its algebraic laws are stated and checked by a property-based test that generates inputs, not just illustrated by one or two hard-coded examples.

## Checklist

1. **Undeclared laws** — a new type or operation (parser, serializer, combinator, custom equality/ordering/comparison, arithmetic-like or monoid-like operation) with no stated invariant: round-trip, idempotence, commutativity, associativity, identity element, inverse, monotonicity, or similar.
2. **Laws asserted only by example** — an invariant that holds in general but is checked only against one or two fixed inputs in an example-based test, rather than a property test whose generator produces arbitrary inputs.
3. **Missing round-trip check** — any encode/decode, serialize/deserialize, or parse/print pair without a property test asserting `decode(encode(x)) == x`, or a documented reason the round trip doesn't hold.
4. **Property tests too narrow** — a property test whose generator is constrained enough (a tiny fixed set, only "nice" values, no boundary or adversarial cases) that it would not catch a real violation of the law it claims to check.
5. **Example tests standing in for a property** — an example-based test iterating several hand-written cases to approximate a general law that a single property test would state directly and check far more broadly. The example test is not wrong on its own; it signals the underlying property test is missing.
6. **Correct use of examples** — confirm example-based tests exist for genuine edge cases, regressions, and readability anchors; this is the intended and correct use per CLAUDE.md, not something to flag.

## Steps

1. Obtain the code in scope: a file path, or (default) `git diff` / `git status` for the working tree's pending changes.
2. Identify each new or materially changed data type or operation in scope.
3. For each, work out what algebraic law it should satisfy given its shape (a serializer implies round-trip, a merge/combine operation implies associativity and possibly commutativity, a normalization function implies idempotence, and so on).
4. Search the corresponding test files for a property test covering that law; note its generator's range to judge whether it actually exercises the law (checklist item 4).
5. Where no property test exists, check whether an example-based test is doing the law's job instead (checklist item 5) — that is the gap to report, not the example test itself.
6. Report findings per type/operation: the law it implies, whether a property test covers it, and if not, what the missing property test should assert. State explicitly if coverage is already adequate.
7. Do not apply fixes automatically — this skill reports; only write or edit tests if the user separately asks for that.
