---
description: Write Racket tests with rackunit — the check vocabulary (check-equal?, check-pred, check-=, check-exn, check-match), grouping with test-case and test-suite (#:before/#:after), running via raco test or run-tests, custom failure context with with-check-info, and BDD-style describe/context/it from rackunit/spec. Use when writing or organizing Racket tests, adding a test submodule, choosing a check, or structuring specs.
---

# Testing with rackunit

`rackunit` is Racket's unit-testing library. A test is a `check-*` form that
records a failure (with actual/expected/location) instead of throwing. The
idiomatic home for tests is a `test` submodule, run by `raco test` — no
separate test file, and the tests can see the module's private bindings (see
[[modules]]).

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

Pick the most specific check — its failure message is only as good as the
information it has:

| Check                                  | Passes when                         |
|----------------------------------------|-------------------------------------|
| `(check-equal? actual expected [msg])` | `equal?` — the default for values   |
| `(check-not-equal? a b)`               | not `equal?`                        |
| `(check-eqv? a b)` / `(check-eq? a b)` | `eqv?` / `eq?`                      |
| `(check-true e)` / `(check-false e)`   | `e` is `#t` / `#f`                  |
| `(check-pred pred v)`                  | `(pred v)` is true                  |
| `(check-= a b tol [msg])`              | numbers within `tol`                |
| `(check-exn pred-or-rx thunk [msg])`   | `thunk` raises a matching exception |
| `(check-not-exn thunk)`                | `thunk` raises nothing              |
| `(check-match v pattern [when-expr])`  | `v` matches the `match` pattern     |
| `(check-regexp-match rx str)`          | `rx` matches `str`                  |
| `(check pred a b)` / `(fail)`          | generic / unconditional failure     |

```racket
(check-pred string? (greet "x"))
(check-= 3.14159 3.1416 0.001)
(check-exn exn:fail:contract? (lambda () (car '())))   ; note: a THUNK
(check-match (list 1 2 3) (list _ _ _))
```

`check-exn` takes a **predicate or regexp** and a **zero-argument thunk** —
not the raising expression directly, or it raises before the check runs.

## Grouping tests

- **`test-case`** names a group so failures are reported under that label:

  ```racket
  (test-case "addition"
    (check-equal? (+ 2 2) 4)
    (check-equal? (+ 0 0) 0))
  ```

- **`test-suite`** bundles cases and other suites into a value you can run,
  with optional setup/teardown:

  ```racket
  (define arith
    (test-suite "arith"
      #:before (lambda () (setup!))
      #:after  (lambda () (teardown!))
      (test-case "adds"  (check-equal? (+ 2 2) 4))
      (test-case "mults" (check-equal? (* 2 3) 6))))
  ```

A bare `check-*` at the top of a `test` submodule is already a test; wrap in
`test-case` when you want a name, and in `test-suite` when you need hooks or
a runnable value.

## Running tests

- **`raco test file.rkt`** is the default — it runs the `test` submodule (and
  top-level checks) and aggregates results across files.
- **`run-tests`** (from `rackunit/text-ui`) runs a `test-suite` value and
  returns the number of failures + errors — useful for a custom runner or a
  non-zero exit code:

  ```racket
  (require rackunit/text-ui)
  (exit (run-tests arith))
  ```

A failure prints `name` / `location` / `message` / `actual` / `expected`,
then a summary like `1/3 test failures`.

## Custom failure context

`with-check-info` attaches extra fields shown when a check inside it fails —
use it to build domain-specific checks that explain themselves:

```racket
(define (check-positive n)
  (with-check-info (['value n] ['context "check-positive"])
    (check-true (> n 0))))
```

## BDD style: rackunit/spec

`rackunit/spec` adds `describe`, `context` (an alias for `describe`), and
`it` for readable, nested specs. `describe`/`context` just nest a
description; `it` expands to a `test-case` whose name is the descriptions
joined and indented. Checks inside `it` are ordinary rackunit checks.

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

It is a thin layer: there are **no `before`/`after` hooks** in `it`/`describe`.
For per-test setup, bind locally inside `it`, or drop to a `test-suite` with
`#:before`/`#:after`. Use `rackunit/spec` for the naming/structure; use core
rackunit checks and suites for everything else.

## Rules that prevent rework

- **Default to `(module+ test …)` + `raco test`.** Tests live beside the code
  they cover, see its private bindings, and don't run on `require` (see
  [[modules]]). Reserve `test-suite` + `run-tests` for custom runners.
- **Choose the specific check.** `(check-equal? x 42)` reports actual vs
  expected; `(check-true (= x 42))` reports only "got #f". Reach for
  `check-pred`, `check-=`, `check-match` over `check-true` of a predicate.
- **`check-exn` wants a predicate/regexp and a thunk.** Wrap the failing code
  in `(lambda () …)`; pass `exn:fail:…?` or a regexp to say *which* error.
- **Name groups with `test-case`.** A labeled case turns an anonymous failure
  into one you can locate; suites without names are hard to read in output.
- **`rackunit/spec` is structure, not a framework.** It has no hooks or
  fixtures — combine it with plain rackunit for setup, and don't expect
  before/after blocks.
