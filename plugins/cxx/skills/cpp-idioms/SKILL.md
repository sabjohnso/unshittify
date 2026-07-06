---
description: Reference for C++-specific coding idioms to apply when writing or editing C++ — where to place an exception-to-Result guard (the tested library boundary, not app or main() code), when to split an oversized function into one function per job, when to prefer a range algorithm over an explicit loop versus when an explicit loop is still the right tool, and C++-specific TDD mechanics (a compile error is valid red evidence; a passing assertion is only evidence if it actually tests the claimed property). Use when writing new C++ code or editing existing C++ code, especially around a fallible boundary, an executable's main()/driver entry point, or a loop.
---

# C++ editing idioms

These idioms generalize a real refactor of an executable's `main()`: broadening an exception guard that only handled one error type, splitting a nine-job function into one function per job, and replacing two explicit loops with range algorithms where that fit and leaving one as a loop where it didn't.

## Guard fallible boundaries in library code, not app code

If a function throws a narrow, expected exception type (a project-specific error type carrying a source location) but can also throw a plain `std::exception` for an internal invariant violation, wrap it in a checked variant that:

1. Catches the narrow, expected exception type first, preserving its structured information (source span, error code) rather than discarding it into a plain string.
2. Falls back to a broader `catch (const std::exception &)`, wrapping its `what()` into the same error type the caller already expects.
3. Never lets an exception escape the boundary — the checked variant always returns a `Result`/`Expected`-style value.

Order the catch clauses from most specific to most general; a generic clause placed first would shadow the specific one silently.

Put this checked variant in the library boundary the tests can already reach (`src/`, `include/`), not inline inside `main()` or other executable-only code. An executable target usually isn't linked into the test binary, so a guard written there — inline `try`/`catch` plus a `dynamic_cast` to recover the specific error type — cannot be exercised directly by any test; the same guard placed one layer down, as a named function in the tested library, can be.

```cpp
// include/mylib/driver.hpp
Result<std::string> emit_ir_checked(const CheckedModule &m);

// src/mylib/driver.cpp
Result<std::string> emit_ir_checked(const CheckedModule &m) {
  try {
    return Result<std::string>::ok(emit_ir(m));
  } catch (const AsmError &e) {
    return Result<std::string>::err(e);
  } catch (const std::exception &e) {
    return Result<std::string>::err(AsmError(SourceSpan{}, std::string("codegen: ") + e.what()));
  }
}
```

## Split a function once it does more than one job

A driver function — `main()`, a request handler, a top-level dispatcher — should reduce to classifying its input and dispatching to a per-case function, not also performing validation, I/O, and each case's own pipeline inline. Signs a function has outgrown single responsibility:

- It mixes argument/input classification with validation, with I/O, with two or more independent pipelines.
- The same short block (e.g. "render a diagnostic and return an error code") appears three or more times.

Extract one function per job, and factor any block repeated three or more times into a single shared helper. This is the same Normalized Systems Theory "small, focused units" principle `/development:make-changing-easy` already assesses generally — apply it specifically to `main()`/driver functions, which tend to accumulate jobs one `if` branch at a time until no one notices they've become nine functions wearing one name.

## Loop, or algorithm?

| Loop shape                                                                                                                              | Choice                                                                                                                                                                                                                                                                  |
|-----------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| A single predicate applied to every element, no early exit, no side effect (classify, filter, detect)                                   | A range algorithm: `std::ranges::any_of`/`all_of`/`none_of` to detect, `std::ranges::copy_if` or a `views::filter` to select.                                                                                                                                           |
| Fail-fast validation: check each element, return immediately with a side effect (print a diagnostic, set an error) on the first failure | Keep the explicit loop. The standard library has no generic "transform with early abort" algorithm; forcing one in (`std::ranges::for_each` with a mutable early-exit flag, `std::transform` plus a separate check) obscures the early return instead of clarifying it. |

Converting the first shape and leaving the second alone is the correct outcome of applying "declarative code where possible" — that principle argues for the algorithm precisely because it fits, not as a blanket rule against `for` loops.

## TDD mechanics specific to C++

- **A compile error is valid red evidence for a symbol that doesn't exist yet.** Writing a test against a function or type before it exists and confirming the build fails with an undeclared-identifier or undefined-reference error satisfies the red step exactly as well as a failing runtime assertion would; it does not need to compile first.
- **A passing assertion is only evidence for what it actually checks.** If a test's name promises a specific guarantee (e.g., "preserves the original error location"), its assertion must check that specific value, not a substring of a rendered message that would also pass under a weaker or wrong implementation. Verify a new or strengthened assertion actually catches the regression it targets by temporarily reintroducing that regression, confirming the test fails, then restoring the fix and confirming it passes again — the same discipline this project already applies to property tests, applied here to a single assertion.
- **A general law already covered by a property test doesn't need re-proving by a new example test.** When adding an edge-case regression test for a boundary guard, check whether the underlying invariant (e.g., "this stage never crashes on valid input") is already a property test elsewhere; if so, the new example test's job is coverage of the specific new wrapping behavior, not re-establishing the general law.

## Rules that prevent rework

- **Never place a narrow-exception-then-generic-exception guard in `main()` or other executable-only code.** If nothing under the test tree links against it, nothing can prove it works; move it one layer down into the tested library first.
- **Never leave a fail-fast validation loop as an algorithm call that only approximates "early abort."** An explicit loop that returns immediately on the first failure is already the clearest expression of that behavior.
- **Never accept a passing test for a specific claim ("preserves location," "is idempotent," "is thread-safe") without checking that its assertion, not just its name, tests that specific claim.**
