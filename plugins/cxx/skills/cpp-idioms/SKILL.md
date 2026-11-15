---
description: Reference for the C++-specific coding idioms that apply when you write or edit C++. Where to put an exception-to-Result guard (the tested library boundary, not the application or main() code). How to order a precondition check (the main path in the first branch and the error in the else, never a guard clause first). When to split an oversized function into one function per job. When to prefer a range algorithm over an explicit loop, and when an explicit loop is the right tool. The C++-specific TDD mechanics (a compile error is valid red evidence, and a passed assertion is evidence only if it tests the claimed property). Use when you write new C++ code or edit existing C++ code, especially around a fallible boundary, the main() or driver entry point of an executable, or a loop.
---

# C++ editing idioms

Goal: apply the right C++ idiom at the change site. Where does the exception guard go? Which branch of a precondition check comes first? When has a function outgrown one job? Must a loop become an algorithm? What counts as red evidence in C++? This is a reference to read while you edit, not a procedure to run from start to end, so it has no numbered steps. The procedure that it feeds is the one in `/development:make-changing-easy`.

These idioms generalize a real refactor of the `main()` of an executable. The refactor widened an exception guard that handled only one error type, split a function with nine jobs into one function per job, replaced two explicit loops with range algorithms where that fit, and left one loop as a loop where it did not fit.

## Guard a fallible boundary in library code, not in application code

A function can throw a narrow, expected exception type (a project-specific error type with a source location), but it can also throw a plain `std::exception` for an internal invariant violation. Wrap such a function in a checked variant that:

1. Catches the narrow, expected exception type first. Keep its structured information (the source span, the error code). Do not discard it into a plain string.
2. Falls back to a broader `catch (const std::exception &)`, and wraps its `what()` into the same error type that the caller already expects.
3. Never lets an exception escape the boundary. The checked variant always returns a `Result` or `Expected` style value.

Order the catch clauses from the most specific to the most general. A generic clause before a specific clause shadows the specific one with no error.

Put this checked variant in the library boundary that the tests can already reach (`src/`, `include/`). Do not put it inline inside `main()` or other code that only the executable holds. An executable target is usually not linked into the test binary. So no test can exercise a guard that is written there (an inline `try` and `catch` plus a `dynamic_cast` to recover the specific error type). The same guard one layer down, as a named function in the tested library, is testable.

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

## Put the main path first

When a function checks a precondition, write the main logic in the first branch and the error in the `else`. Do not write a guard clause that throws or returns an error first and puts the main logic after it. What the function does is more important than its error message. A guard clause puts the error first and hides the main logic below it.

```cpp
quadrature_rule
quadrature_rule::gauss(int positive_point_count) {
  if (positive_point_count >= 1) {
    const int n = positive_point_count;
    auto [points, weights] = symmetric_rule_on_unit_interval(n, gauss_point_of(n));
    return {std::move(points), std::move(weights)};
  } else {
    throw std::invalid_argument("A Gauss rule needs at least one point");
  }
}
```

Write the condition as the valid inputs, not as the invalid inputs. Use the plain inverse of the old check (`x < 1` becomes `x >= 1`, `!f()` becomes `f()`, `a < 0 || a >= n` becomes `a >= 0 && a < n`). For an integer, pointer or boolean value, do not write `!(...)` around the old condition.

A plain inverse is exact only for integer, pointer and boolean values. For a floating-point value, `x >= 1` is not the inverse of `x < 1`, because both are false for a NaN (a not-a-number value). To keep the old behavior, write `!(x < 1)`. If a NaN must now take the other branch, the behavior changes. Write a failed test first.

The condition still runs first. Only the order of the text changes. If the new condition is the exact inverse of the old one, the conversion of a guard clause does not change the behavior.

When a function has two or more checks, combine them in the first branch. Then give each error in an `else if`, in the order of the old checks. Each input then gets the same error as before:

```cpp
if (total[1] <= 0 && total[2] == volume_of_root) {
  return total[0];
} else if (total[1] > 0) {
  throw std::invalid_argument(own_problem ? *own_problem : another_rank_has_a_problem);
} else {
  throw std::invalid_argument("The leaves of all ranks must fill the root without a gap or an overlap");
}
```

Put one `if`–`else` inside another only when the main path must do work before the next check. Examples are a value that the next condition reads, or a collective call that each rank must make in the same order. Do not combine the conditions if that changes which error an input gets. Do not combine them if a condition is unsafe before an earlier check passes (for example, a dereference after an end check). Keep the short-circuit order of `&&`.

In an `else if` chain, a condition can run two times: one time in the combined condition and one time in its `else if`. If a condition costs time or has a side effect, calculate it one time into a named `const bool` before the `if`. Let the `if` and the `else if` read that name. A named condition runs even when an earlier check fails, so do this only when the condition must run in all cases (for example a collective call that each rank makes). In all other cases, put one `if`–`else` inside another, so that the condition runs only after the earlier checks pass.

A fail-fast validation loop that only checks each element and returns at the first failure has no main path in its body. Keep it as an explicit loop, as the loop-shape rule below says. When a check in a loop body guards the work of that body, the check takes the same form as in a function. A function whose only job is the check (a `require_*` function that ends with the `throw`) has no main path. Keep it as it is, because an empty first branch does not help the reader.

## Split a function when it does more than one job

A driver function (`main()`, a request handler, a top-level dispatcher) must reduce to two tasks: it classifies its input, and it dispatches to a function per case. It must not also validate, do I/O, and run the pipeline of each case inline. Signs that a function has outgrown a single responsibility:

- It mixes the classification of the argument or the input with validation, with I/O, and with two or more independent pipelines.
- The same short block (for example "render a diagnostic and return an error code") occurs three or more times.

Extract one function per job. Factor each block that occurs three or more times into a single shared helper. This is the same "small, focused units" principle of Normalized Systems Theory that `/development:make-changing-easy` assesses in general. Apply it specifically to `main()` and driver functions. They tend to collect jobs one `if` branch at a time, until nobody sees that they do nine jobs under one name.

## Loop, or algorithm?

| Loop shape                                                                                                                              | Choice                                                                                                                                                                                                                                                                  |
|-----------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| A single predicate applied to every element, with no early exit and no side effect (classify, filter, detect)                           | A range algorithm: `std::ranges::any_of`, `all_of`, or `none_of` to detect, `std::ranges::copy_if` or a `views::filter` to select.                                                                                                                                      |
| Fail-fast validation: check each element, and return at once with a side effect (print a diagnostic, set an error) on the first failure | Keep the explicit loop. The standard library has no generic "transform with early abort" algorithm. A forced one (`std::ranges::for_each` with a mutable early-exit flag, or `std::transform` plus a separate check) hides the early return and does not make it clearer. |

The conversion of the first shape and no conversion of the second shape is the correct result of the "declarative code where possible" principle. That principle argues for the algorithm exactly because it fits. It is not a blanket rule against `for` loops.

## TDD mechanics specific to C++

- **A compile error is valid red evidence for a symbol that does not exist yet.** Write a test against a function or type before it exists, and confirm that the build fails with an undeclared-identifier or undefined-reference error. That satisfies the red step as well as a failed runtime assertion does. The test does not need to compile first.
- **A passed assertion is evidence only for what it checks.** If the name of a test promises a specific guarantee (for example "preserves the original error location"), its assertion must check that specific value. It must not check a substring of a rendered message that also passes under a weaker or wrong implementation. Make sure that a new or stronger assertion catches the regression that it targets. Put that regression back for a moment, confirm that the test fails, then restore the fix and confirm that the test passes again. This project already applies that discipline to property tests. Apply it here to a single assertion.
- **A general law that a property test already covers does not need a new proof by a new example test.** When you add an edge-case regression test for a boundary guard, check whether the invariant (for example "this stage never crashes on valid input") is already a property test at another place. If it is, the job of the new example test is the coverage of the specific new wrap behavior. It is not a new proof of the general law.

## Rules that prevent rework

- **Never write a guard clause that throws or returns an error before the main logic.** Put the main path in the first branch and the error in the `else`. Make the new condition the exact inverse of the old one. Keep the order of the errors. A fail-fast validation loop and a `require_*` function have no main path, so this rule does not apply to them. Change the order of an existing check only when the requested change touches that check.
- **Never put a guard with a narrow exception and then a generic exception in `main()` or other code that only the executable holds.** If nothing under the test tree links against it, nothing can show that it works. Move it one layer down into the tested library first.
- **Never leave a fail-fast validation loop as an algorithm call that only approximates an "early abort".** An explicit loop that returns at once on the first failure is already the clearest expression of that behavior.
- **Never accept a passed test for a specific claim ("preserves the location", "is idempotent", "is thread-safe") before you check that its assertion, and not only its name, tests that specific claim.**
