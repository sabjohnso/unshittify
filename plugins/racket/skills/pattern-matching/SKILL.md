---
description: Destructure and dispatch on the shape of data with racket/match. Covers match and match*, the pattern catalog (list, struct, ?, and, or, app, ==, quasiquote, regexp, hash-table, ellipsis), the binding forms (match-define, match-let, match-lambda), guards and the => failure escape, and define-match-expander. Use when you write a match expression, when you destructure a struct, a list, or a hash, when you choose a match binding form, or when you fix a non-exhaustive-match error.
allowed-tools: Read, Grep, Glob
---

# Racket pattern matching

`match` (from `racket/match`) destructures a value and dispatches on its
shape in one form. Racket tries the clauses from the top to the bottom. The
first clause whose pattern matches runs, with the pattern variables bound
for its body. If no clause matches, `match` raises `exn:fail`. It is part of
`#lang racket`. Under `racket/base`, add `(require racket/match)`. For the
complete pattern grammar and every binding form, read `reference.md` in this
skill directory.

```racket
(match value
  [pattern body ...+]
  ...)
```

## The pattern catalog

| Pattern                          | Matches and binds                                          |
|----------------------------------|------------------------------------------------------------|
| `_`                              | everything, and binds nothing                              |
| `id`                             | everything, and binds `id` to it                           |
| `42` `"s"` `#t` `'sym`           | that literal (by `equal?`)                                 |
| `(list p ...)`                   | a list of exactly those elements                           |
| `(list p ... pn ...)` (ellipsis) | `pn ...` matches zero or more, and binds each variable to a list |
| `(list* p ... rest)`             | a fixed head, with `rest` bound to the tail                |
| `(cons a d)` `(vector p ...)`    | a pair or a vector, by position                            |
| `(struct id (p ...))`            | an `id` instance, with the fields by position              |
| `(struct* id ([field p] ...))`   | an `id` instance, with the fields by name (a subset)       |
| `(? pred p ...)`                 | a value that satisfies `pred` and also matches `p ...`     |
| `(and p ...)` `(or p ...)`       | all or one (each `or` arm must bind the same variables)    |
| `(not p ...)`                    | none of `p ...` matches                                    |
| `(app fn p)`                     | apply `fn` to the value, and match the result against `p`  |
| `(== expr)`                      | the value is `equal?` to `expr` (a *value*, not a pattern) |
| `` `(a ,x ,@xs) ``               | quasiquote: the literals match, and `,x` and `,@xs` bind   |
| `(regexp rx)` / `(regexp rx p)`  | the string matches `rx`. The second form matches the match list |
| `(hash-table (key p) ...)`       | a hash with those keys, with the values matched by `p`     |
| `(list-no-order p ...)`          | a list that holds those elements in any order              |

The ellipsis depth: `(list (list x y) ...)` binds `x` and `y` to *lists*,
one element per inner pair. `(list p ..3)` requires at least three.

## A repeated variable constrains by equality

The same pattern variable at two positions means that the two positions
must be `equal?`. This is useful with `match*`, which matches several values
at once:

```racket
(match* (a b)
  [(x x) 'equal]                       ; fires only when a is equal? to b
  [((? number?) (? number?)) (if (< a b) 'less 'greater)]
  [(_ _) 'incomparable])
```

## The binding forms

When you have only one shape and you need no dispatch, skip the clause
list:

```racket
(match-define (list lo hi) (compute-range))   ; bind lo and hi in this scope
(match-let ([(cons a b) p]) (+ a b))           ; like let, with patterns
(define area (match-lambda [(posn x y) (* x y)]))  ; a one-argument function with a match
(match-lambda** [(a b) ...] ...)               ; several arguments, like match*
```

`match-let*` binds from the left to the right. `match-letrec` permits
recursion. `match-lambda*` matches against the *argument list*.

## Guards and the fall through

There are three ways to express a side condition, in the rough order of
preference:

- **`#:when cond`** after the pattern. This is the cleanest boolean guard.
  If `cond` is false, `match` abandons the clause and continues at the next
  clause: `[x #:when (even? x) ...]`.
- **`(? predicate)`** inside the pattern, when the test is local to one
  position: `[(? string? s) ...]`, `[(and n (? even?)) ...]`.
- **The `(=> fail)` escape**, when the decision needs values computed in the
  body. Bind a `fail` with zero arguments, and call it to abandon this
  clause and continue at the next one.

```racket
(match v
  [(list a b) #:when (> a b) 'a-bigger]                  ; a guard with #:when
  [(list a b) (=> fail) (if (= a b) (fail) 'a-smaller)]  ; or an escape with =>
  [_ 'other])
```

## Custom patterns

`define-match-expander` names a reusable pattern (and, as an option, an
expression). Its transformer runs at phase 1, so require `(for-syntax
racket/base)`:

```racket
(require racket/match (for-syntax racket/base))
(define-match-expander origin
  (lambda (stx) #'(posn 0 0)))            ; used as a pattern: (origin)
(match p [(origin) 'at-origin] [_ 'elsewhere])
```

## Rules that prevent rework

- **Order the clauses from the specific to the general.** The first match
  wins. A broad pattern (`id`, `_`, `(? string?)`) at an early position
  shadows the narrower clauses below it. Put `_` last as the catch-all.
- **`app` applies its function without a condition.** `(app string->number
  n)` runs `string->number` on *every* value that reaches it, and it gives an
  error on a value that is not a string. Guard it: `(and (? string?) (app
  string->number (? number? n)))`.
- **An ellipsis binds a list, one level deeper.** A variable under `...` is
  a list in the body. Under two `...` it is a list of lists. Match the
  ellipsis depth to the way that you consume the variable.
- **`==` takes a value. A quote takes a literal.** Use `(== expr)` to
  compare against a computed value. A bare literal or `'sym` matches that
  constant. Do not write `(== 'sym)` where `'sym` already works.
- **The `or` arms must bind the same variables.** Every alternative in `(or
  p ...)` must introduce the same set of pattern variables. Otherwise the
  body cannot use them.
- **A non-exhaustive `match` raises at run time, not at compile time.** Add a
  final `[_ ...]` (or an explicit error) when the input set is open. Then a
  missed shape gives a clear message and not a bare `match` failure.
- **A match expander needs `(for-syntax racket/base)`.** The expander body is
  transformer code. With no phase-1 import, you get "unbound identifier:
  lambda".
