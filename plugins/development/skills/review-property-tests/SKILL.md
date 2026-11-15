---
description: Review new or changed data types and operations against the Algebra Driven Design requirement of this project in CLAUDE.md. The types and the operations must be designed as algebras with explicit laws. Property-based tests (QCheck or an equivalent) must check those laws, not only examples. Example-based tests (Alcotest or an equivalent) are for edge cases and regressions. Use automatically after each code change (a bug fix, a new feature, a refactor) as a postcondition of the change. Use it not only when the user explicitly asks for a review of property-test coverage or algebra-driven design compliance.
argument-hint: "[file path, or none for working tree changes]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git status:*)
---

# Review code against algebra-driven design and property tests

Goal: for each new or changed data type or operation in the scope, confirm that its algebraic laws are stated. Also confirm that a property-based test with generated inputs checks them. One or two fixed examples are not enough.

## Checklist

1. **Undeclared laws.** A new type or operation with no stated invariant. Examples of a type or operation are a parser, a serializer, and a combinator. Other examples are a custom equality, order, or comparison, and an operation like arithmetic or a monoid. Examples of an invariant are round trip, idempotence, commutativity, associativity, identity element, inverse, monotonicity, or a similar one.
2. **Laws asserted only by example.** An invariant that holds in general, but only one or two fixed inputs in an example-based test check it. No property test with a generator produces arbitrary inputs for it.
3. **A missing round-trip check.** An encode and decode, serialize and deserialize, or parse and print pair with no property test that asserts `decode(encode(x)) == x`. The pair also has no documented reason that the round trip does not hold.
4. **Property tests that are too narrow.** A property test whose generator is so constrained that it cannot catch a real violation of the law that it claims to check. Examples of a constraint are a small fixed set, only "nice" values, and no boundary or adversarial cases.
5. **Example tests in the place of a property.** An example-based test that iterates over several hand-written cases to approximate a general law. A single property test states that law directly and checks it far more broadly. The example test is not wrong on its own. It signals that the property test is missing.
6. **Correct use of examples.** Confirm that example-based tests exist for real edge cases and regressions, and as examples kept for readability. Per CLAUDE.md, that is the intended and correct use. Do not flag it.

## Steps

1. Get the code in the scope. If you got a file path, use it. If you got none, use `git diff` and `git status` for the pending changes of the working tree.
2. Identify each new or materially changed data type or operation in the scope.
3. For each one, work out the algebraic law that it must satisfy, from its shape. A serializer implies a round trip. A merge or combine operation implies associativity and possibly commutativity. A normalization function implies idempotence. And so on.
4. Search the matching test files for a property test that covers that law. Note the range of its generator, to judge whether the test exercises the law (checklist item 4).
5. Where no property test exists, check whether an example-based test does the job of the law instead (checklist item 5). That is the gap to report, not the example test itself.
6. Report these items for each type or operation:
   - the law that it implies
   - whether a property test covers it
   - if not, what the missing property test must assert

   State explicitly if the coverage is already adequate.
7. Do not apply fixes automatically. This skill reports. Write or edit tests only if the user separately asks for that.
