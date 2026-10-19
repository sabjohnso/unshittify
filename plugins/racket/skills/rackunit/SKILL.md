---
description: "Write Racket tests with rackunit. Covers the check vocabulary (check-equal?, check-pred, check-=, check-exn, check-match), groups with test-case and test-suite (#:before and #:after), a run through raco test or run-tests, a custom failure context with with-check-info, and the BDD-style describe, context, and it forms from the separate rackunit-spec package. Use when you write or organize Racket tests, when you add a test submodule, when you choose a check, or when you structure specs."
allowed-tools: Bash(racket:*), Bash(raco:*), Read, Grep, Glob
---

# Tests with rackunit

`rackunit` is the unit-test library of Racket. A test is a `check-*` form
that records a failure (with the actual value, the expected value, and the
location). It does not throw. The idiomatic home for tests is a `test`
submodule, which `raco test` runs. There is no separate test file, and the
tests can see the private bindings of the module (see
[modules](../modules/SKILL.md)).

For the complete check vocabulary and the signatures of the test groups, the
runners, and the custom checks, read `reference.md` in this skill directory.

```racket
#lang racket/base
(provide double)
(define (double n) (* 2 n))

(module+ test
  (require rackunit)
  (check-equal? (double 21) 42)
  (test-case "negatives" (check-equal? (double -3) -6)))
```

Run it: `raco test file.rkt`.

## The check vocabulary

Pick the most specific check. Its failure message is only as good as the
information that it has:

| Check                                  | Passes when                          |
|----------------------------------------|--------------------------------------|
| `(check-equal? actual expected [msg])` | `equal?`. The default for values     |
| `(check-not-equal? a b)`               | not `equal?`                         |
| `(check-eqv? a b)` / `(check-eq? a b)` | `eqv?` / `eq?`                       |
| `(check-true e)` / `(check-false e)`   | `e` is `#t` / `#f`                   |
| `(check-pred pred v)`                  | `(pred v)` is true                   |
| `(check-= a b tol [msg])`              | the numbers are within `tol`         |
| `(check-exn pred-or-rx thunk [msg])`   | `thunk` raises a matching exception  |
| `(check-not-exn thunk)`                | `thunk` raises nothing               |
| `(check-match v pattern [when-expr])`  | `v` matches the `match` pattern      |
| `(check-regexp-match rx str)`          | `rx` matches `str`                   |
| `(check pred a b)` / `(fail)`          | a generic check / an unconditional failure |

```racket
(check-pred string? (greet "x"))
(check-= 3.14159 3.1416 0.001)
(check-exn exn:fail:contract? (lambda () (car '())))   ; note: a THUNK
(check-match (list 1 2 3) (list _ _ _))
```

`check-exn` takes a **predicate or a regexp** and a **thunk with zero
arguments**. Do not pass the expression that raises directly. Otherwise it
raises before the check runs.

## Test groups

- **`test-case`** names a group, so the report shows each failure under
  that label:

  ```racket
  (test-case "addition"
    (check-equal? (+ 2 2) 4)
    (check-equal? (+ 0 0) 0))
  ```

- **`test-suite`** bundles cases and other suites into a value that you can
  run, with an optional setup and teardown:

  ```racket
  (define arith
    (test-suite "arith"
      #:before (lambda () (setup!))
      #:after  (lambda () (teardown!))
      (test-case "adds"  (check-equal? (+ 2 2) 4))
      (test-case "mults" (check-equal? (* 2 3) 6))))
  ```

A bare `check-*` at the top of a `test` submodule is already a test. Wrap it
in `test-case` when you want a name. Wrap it in `test-suite` when you need
hooks or a value that you can run.

## Run the tests

- **`raco test file.rkt`** is the default. It runs the `test` submodule (and
  the top-level checks), and it collects the results across files.
- **`run-tests`** (from `rackunit/text-ui`) runs a `test-suite` value and
  returns the number of failures plus errors. It is useful for a custom
  runner or a nonzero exit code:

  ```racket
  (require rackunit/text-ui)
  (exit (run-tests arith))
  ```

A failure prints the `name`, the `location`, the `message`, the `actual`
value, and the `expected` value, then a summary such as `1/3 test failures`.

## A custom failure context

`with-check-info` attaches extra fields that the report shows when a check
inside it fails. Use it to build domain-specific checks that explain
themselves:

```racket
(define (check-positive n)
  (with-check-info (['value n] ['context "check-positive"])
    (check-true (> n 0))))
```

## The BDD style: rackunit/spec

`rackunit/spec` is **not** part of `rackunit`. Despite the collection path,
it ships in the separate `rackunit-spec` package. On a stock install,
`(require rackunit/spec)` fails with `open-input-file: cannot open module
file`. Install it first:

```
raco pkg install rackunit-spec
```

It adds `describe`, `context` (an alias for `describe`), and `it` for
readable, nested specs. `describe` and `context` only nest a description.
`it` expands to a `test-case` whose name is the descriptions joined and
indented. A check inside `it` is an ordinary rackunit check.

```racket
(require rackunit rackunit/spec)

(describe "a stack"
  (context "when empty"
    (it "is empty"
      (check-equal? (unbox (stack)) '())))
  (context "after push"
    (it "pops the last value"
      (define s (stack))
      (push! s 1) (push! s 2)
      (check-equal? (pop! s) 2))))
```

It is a thin layer. There are **no `before` and `after` hooks** in `it` and
`describe`. For a setup per test, bind locally inside `it`, or drop to a
`test-suite` with `#:before` and `#:after`. Use `rackunit/spec` for the
names and the structure. Use the core rackunit checks and suites for all
the rest.

## Rules that prevent rework

- **Default to `(module+ test …)` plus `raco test`.** The tests live beside
  the code that they cover, they see its private bindings, and they do not
  run on a `require` (see [modules](../modules/SKILL.md)). Keep `test-suite`
  plus `run-tests` for a custom runner.
- **Choose the specific check.** `(check-equal? x 42)` reports the actual
  and the expected value. `(check-true (= x 42))` reports only "got #f". Use
  `check-pred`, `check-=`, and `check-match` instead of `check-true` on a
  predicate.
- **`check-exn` takes a predicate or a regexp and a thunk.** Wrap the code
  that fails in `(lambda () …)`. Pass `exn:fail:…?` or a regexp to say
  *which* error.
- **Name the groups with `test-case`.** A labeled case turns an anonymous
  failure into one that you can locate. A suite with no name is hard to
  read in the output.
- **`rackunit/spec` is a separate package, and it is structure, not a
  framework.** Run `raco pkg install rackunit-spec` before you require it.
  It has no hooks and no fixtures. Combine it with plain rackunit for the
  setup. Do not expect before and after blocks.
