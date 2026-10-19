---
description: Property-based tests in Racket with rackcheck. Covers laws over generated inputs with property and check-property, inputs from generators (gen:natural, gen:list, gen:let, gen:filter, gen:choice, gen:frequency), the reproduction of a failure by seed with make-config, the shrunk minimal counterexamples, and the classification of inputs with label!. Use when you test invariants or algebraic laws instead of fixed examples, when you write generators, or when you debug a shrunk counterexample.
allowed-tools: Bash(racket:*), Bash(raco:*), Read, Grep, Glob
---

# Property-based tests with rackcheck

A property test states a law that must hold for *all* inputs. Then
rackcheck checks the law against many cases with random values. When a case
fails, rackcheck **shrinks** the counterexample to the smallest input that
still breaks the law. So you debug `n = 50`, not `n = 8347291`. This
complements the example-based tests of [rackunit](../rackunit/SKILL.md)
(which pin specific cases), and it fits algebra-driven design: encode the
laws of the algebra, then verify them.

For the full generator catalogue and the exact signatures of the property
and configuration forms, read `reference.md` in this skill directory.

```racket
#lang racket/base
(require rackcheck rackunit)

(define prop-reverse-involutive
  (property ([xs (gen:list gen:natural)])
    (equal? (reverse (reverse xs)) xs)))

(module+ test
  (check-property prop-reverse-involutive))   ; runs 100 cases under `raco test`
```

`property` binds each variable to a value from its generator, runs the body,
and treats a result that is not `#f` as a pass. `check-property` is a
rackunit check. So a property lives in a `(module+ test …)` and runs with
`raco test` beside the ordinary checks (see [modules](../modules/SKILL.md),
[rackunit](../rackunit/SKILL.md)).

## Generators

A generator (`gen:…`) describes how to produce random values, and how to
shrink them.

| Generator                                                             | Produces                                    |
|-----------------------------------------------------------------------|---------------------------------------------|
| `gen:natural`                                                         | the naturals `0, 1, 2, …`                   |
| `(gen:integer-in lo hi)`                                              | integers in `[lo, hi]`                      |
| `gen:real`                                                            | reals                                       |
| `gen:boolean`                                                         | `#t` or `#f`                                |
| `gen:char` `gen:char-letter` `gen:char-digit` `gen:char-alphanumeric` | characters                                  |
| `(gen:string [g])` `(gen:symbol [g])`                                 | strings or symbols from a character generator |
| `(gen:bytes [g])`                                                     | a byte string from an integer generator     |
| `(gen:list g [#:max-length n])`                                       | lists of `g` values                         |
| `(gen:vector g [#:max-length n])`                                     | vectors of `g` values                       |
| `(gen:hash key g key g ...)`                                          | a hash: *literal* keys, generated values    |
| `(gen:tuple g ...)`                                                   | a list of fixed length, one element per generator |
| `(gen:const v)`                                                       | always `v`                                  |

`gen:symbol`, `gen:string`, and `gen:bytes` are procedures, not generator
values. `(sample gen:symbol 2)` raises `expected: gen?`. Write
`(gen:symbol)`.

`gen:hash` (and `gen:hasheq`, `gen:hasheqv`) takes **literal keys and
generators in turn**. The keys are fixed. Only the values are generated:

```racket
(sample (gen:hash 'a gen:natural 'b gen:boolean) 2)
;; => (#hash((a . 0) (b . #t)) #hash((a . 1) (b . #f)))
```

A *generator* at the position of a key raises nothing. It builds a hash
with the generator itself as the key, so the property runs and tests
nothing.

Combine and change generators:

- **`(gen:map g f)`** applies `f` to each generated value.
- **`(gen:bind g f)`**: `f` returns the *next generator* from a value
  (dependent generation).
- **`gen:let`** is readable do-notation over `gen:bind`, for structured
  data:

  ```racket
  (define gen:interval
    (gen:let ([lo (gen:integer-in 0 100)]
              [span gen:natural])
      (list lo (+ lo span))))        ; guarantees lo <= hi
  ```

- **`(gen:choice g ...)`** picks one generator with a uniform probability.
- **`(gen:one-of lst)`** picks a value from a list.
- **`(gen:frequency (list (cons w g) …))`** is a weighted choice. It takes a
  *list of pairs*. Each pair has a weight and a generator value. A
  quasiquoted `` `((1 . gen:natural)) `` passes the symbol `gen:natural`
  and fails the `gen?` contract.
- **`(gen:filter g pred [max-attempts])`** keeps only the values that pass
  `pred`.
- **`(gen:sized f)`, `(gen:resize g n)`, `(gen:scale g f)`** control the
  size parameter that bounds the magnitude or the length.

### Inspect a generator with `sample`

While you write a generator, `sample` shows what it produces. No property is
necessary:

```racket
(sample gen:interval 5)   ; => ((3 3) (0 1) (2 14) ...)
```

## Configure and reproduce a run

`check-property` takes an optional `config` first:

```racket
(check-property (make-config #:tests 1000 #:seed 42) prop-foo)
```

The `make-config` keywords: `#:tests` (the count, default 100), `#:seed`
(fixes the random number generator), `#:size` (a function that bounds the
case size), `#:deadline`. `#:deadline` is an *absolute* time in
milliseconds, not a duration. The default is `(+
(current-inexact-milliseconds) 60000)`. To permit `ms` more, pass `(+
(current-inexact-milliseconds) ms)`.

**When a property fails, the report prints the `seed`.** Pass it back
through `#:seed` to replay the exact failed run while you debug.

## Shrink

On a failure, rackcheck searches for the minimal counterexample. A false
"every natural is < 50":

```
FAILURE
location:   prop.rkt:4:2
name:       all-small
seed:       1
params:     '(#<prop> #<config>)

Failed after 9 tests:

  n = 50

Could not shrink.
```

It reports `n = 50`, the boundary, and not the larger value that failed
first. The implications:

- **Pick generators that shrink toward a meaningful value.** The built-in
  generators shrink to small and simple values. `gen:map` and `gen:let` keep
  the shrink, so prefer them to a fix after the fact.
- **`gen:no-shrink`** disables the shrink for a generator when a smaller
  value is invalid. Use it rarely.

## Classify the inputs with `label!`

Call `label!` inside a property to tag the current case. The report shows
the distribution, which reveals whether your generator covers the input
space that you care about:

```racket
(property ([n gen:natural])
  (label! (if (even? n) "even" "odd"))
  (>= n 0))
;; Labels:
;; ├ 53.00% odd
;; └ 47.00% even
```

## Write properties that find bugs

Express a relation that the implementation must satisfy. Do not restate its
code:

- **Round trip or inverse:** `(decode (encode x))` equals `x`.
- **Invariant:** a sort keeps the length and the membership. A balanced tree
  stays balanced after an insert.
- **Algebraic laws:** commutativity, associativity, identity, idempotence.
  `(= (op a b) (op b a))`.
- **Model or oracle:** compare a fast implementation against a simple,
  obvious one over random inputs.
- **Metamorphic:** relate two runs. `(length (append a b))` equals `(+
  (length a) (length b))`. Use this when no single expected value exists.

## Rules that prevent rework

- **Put the properties in `(module+ test …)`.** They are rackunit checks.
  Let `raco test` run them with the rest (see
  [modules](../modules/SKILL.md), [rackunit](../rackunit/SKILL.md)).
- **Pin `#:seed` to reproduce a failure.** The failure prints a seed. Feed
  it back to replay the exact case. Do not roll again in the hope that the
  case occurs again.
- **Construct valid inputs. Do not use `gen:filter` a lot.** A filter that
  rejects most candidates is slow, and it can exhaust its retry limit (it
  raises `exn:fail:gen:exhausted`). Build the value with `gen:let` or
  `gen:map`, so it is valid by construction.
- **One law per property.** A focused property gives a precise
  counterexample. A bundle of laws hides which law broke.
- **Do not restate the implementation.** A property that mirrors the code
  passes for the same reason that the code is wrong. Assert an independent
  relation (an inverse, an invariant, a model).
- **Pair the properties with example tests.** Keep some `check-equal?` cases
  ([rackunit](../rackunit/SKILL.md)) for known edge cases and regressions.
  The properties cover the space. The examples pin the corners.
