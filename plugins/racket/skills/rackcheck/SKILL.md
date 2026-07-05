---
description: Property-based testing in Racket with rackcheck — write laws over generated inputs with property/check-property, build inputs from generators (gen:natural, gen:list, gen:let, gen:filter, gen:choice, gen:frequency), reproduce failures by seed via make-config, read shrunk minimal counterexamples, and classify inputs with label!. Use when testing invariants/algebraic laws instead of fixed examples, writing generators, or debugging a shrunk counterexample.
---

# Property-Based Testing with rackcheck

A property test states a law that should hold for *all* inputs, then
rackcheck checks it against many randomly generated cases. When one fails, it
**shrinks** the counterexample to the smallest input that still breaks the
law — so you debug `n = 50`, not `n = 8347291`. This complements example-based
[[rackunit]] (which pins specific cases) and fits algebra-driven design:
encode the algebra's laws, then verify them.

```racket
#lang racket/base
(require rackcheck rackunit)

(define prop-reverse-involutive
  (property ([xs (gen:list gen:natural)])
    (equal? (reverse (reverse xs)) xs)))

(module+ test
  (check-property prop-reverse-involutive))   ; runs 100 cases under `raco test`
```

`property` binds each variable to a value drawn from its generator, runs the
body, and treats a non-`#f` result as a pass. `check-property` is a rackunit
check, so properties live in a `(module+ test …)` and run with `raco test`
alongside ordinary checks (see [[modules]], [[rackunit]]).

## Generators

A generator (`gen:…`) describes how to produce — and shrink — random values.

| Generator                                                             | Produces                               |
|-----------------------------------------------------------------------|----------------------------------------|
| `gen:natural`                                                         | naturals `0, 1, 2, …`                  |
| `(gen:integer-in lo hi)`                                              | integers in `[lo, hi]`                 |
| `gen:real`                                                            | reals                                  |
| `gen:boolean`                                                         | `#t` / `#f`                            |
| `gen:char` `gen:char-letter` `gen:char-digit` `gen:char-alphanumeric` | characters                             |
| `(gen:string g)` `gen:symbol` `gen:bytes`                             | text from a char generator             |
| `(gen:list g [#:max-length n])`                                       | lists of `g` values                    |
| `(gen:vector g)` `(gen:hash kg vg)`                                   | other collections                      |
| `(gen:tuple g ...)`                                                   | a fixed-length list, one per generator |
| `(gen:const v)`                                                       | always `v`                             |

Combine and transform them:

- **`(gen:map g f)`** — apply `f` to each generated value.
- **`(gen:bind g f)`** — `f` returns the *next generator* from a value
  (dependent generation).
- **`gen:let`** — readable do-notation over `gen:bind`, for structured data:

  ```racket
  (define gen:interval
    (gen:let ([lo (gen:integer-in 0 100)]
              [span gen:natural])
      (list lo (+ lo span))))        ; guarantees lo <= hi
  ```

- **`(gen:choice g ...)`** — uniformly pick one generator.
- **`(gen:one-of lst)`** — pick a value from a list.
- **`(gen:frequency `((w . g) …))`** — weighted choice.
- **`(gen:filter g pred [max-attempts])`** — keep only values passing `pred`.
- **`(gen:sized f)` / `(gen:resize g n)` / `(gen:scale g f)`** — control the
  size parameter that bounds magnitude/length.

### Inspect generators with `sample`

While writing a generator, `sample` shows what it produces — no property
needed:

```racket
(sample gen:interval 5)   ; => ((3 3) (0 1) (2 14) ...)
```

## Configuring and reproducing runs

`check-property` takes an optional `config` first:

```racket
(check-property (make-config #:tests 1000 #:seed 42) prop-foo)
```

`make-config` keywords: `#:tests` (count, default 100), `#:seed` (fixes the
RNG), `#:size` (a function bounding case size), `#:deadline`. **When a
property fails, the report prints the `seed`** — pass it back via
`#:seed` to replay the exact failing run while you debug.

## Shrinking

On failure rackcheck searches for the minimal counterexample. A false
"every natural is < 50":

```
FAILURE
name:       all-small
seed:       1
Failed after 9 tests:

  n = 50
Could not shrink.
```

It reports `n = 50` — the boundary — rather than the larger value that first
failed. Implications:

- **Pick generators that shrink toward something meaningful.** Built-in
  generators shrink to small/simple values; `gen:map`/`gen:let` preserve
  shrinking, so prefer them over post-hoc fixups.
- **`gen:no-shrink`** disables shrinking for a generator when a smaller value
  would be invalid; reach for it rarely.

## Classifying inputs with `label!`

Call `label!` inside a property to tag the current case; the report shows the
distribution, which reveals whether your generator actually exercises the
interesting space:

```racket
(property ([n gen:natural])
  (label! (if (even? n) "even" "odd"))
  (>= n 0))
;; Labels:  62.00% even   38.00% odd
```

## Writing properties that find bugs

Express a relationship the implementation must satisfy — not a restatement of
its code:

- **Round-trip / inverse:** `(decode (encode x))` equals `x`.
- **Invariant:** sorting preserves length and membership; a balanced tree
  stays balanced after insert.
- **Algebraic laws:** commutativity, associativity, identity, idempotence —
  `(= (op a b) (op b a))`.
- **Model / oracle:** compare a fast implementation against a simple, obvious
  one over random inputs.
- **Metamorphic:** relate two runs — `(length (append a b))` equals
  `(+ (length a) (length b))` — when no single expected value exists.

## Rules that prevent rework

- **Put properties in `(module+ test …)`.** They are rackunit checks; let
  `raco test` run them with the rest (see [[modules]], [[rackunit]]).
- **Pin `#:seed` to reproduce.** The failure prints a seed — feed it back to
  replay the exact case rather than re-rolling and hoping it recurs.
- **Construct valid inputs; don't `gen:filter` heavily.** A filter that
  rejects most candidates is slow and can exhaust — build the value with
  `gen:let`/`gen:map` so it is valid by construction.
- **One law per property.** A focused property yields a precise
  counterexample; bundling laws muddies which one broke.
- **Don't restate the implementation.** A property that mirrors the code
  passes for the same reason the code is wrong — assert an independent
  relationship (inverse, invariant, model).
- **Pair with example tests.** Keep a few `check-equal?` cases ([[rackunit]])
  for known edge cases and regressions; properties cover the space, examples
  pin the corners.
