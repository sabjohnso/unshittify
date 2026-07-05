---
description: Destructure and dispatch on data shape with racket/match — match and match*, the pattern catalog (list, struct, ?, and/or, app, ==, quasiquote, regexp, hash-table, ellipsis), binding forms (match-define, match-let, match-lambda), guards and the => failure escape, and define-match-expander. Use when writing a match expression, destructuring a struct/list/hash, choosing a match binding form, or fixing a non-exhaustive-match error.
---

# Racket Pattern Matching

`match` (from `racket/match`) destructures a value and dispatches on its
shape in one form. Clauses are tried top to bottom; the first whose pattern
matches runs, binding the pattern variables for its body. No matching clause
raises `exn:fail`. Built into `#lang racket`; under `racket/base` add
`(require racket/match)`. For the complete pattern grammar and every binding
form, read `reference.md` in this skill directory.

```racket
(match value
  [pattern body ...+]
  ...)
```

## Pattern catalog

| Pattern                          | Matches / binds                                         |
|----------------------------------|---------------------------------------------------------|
| `_`                              | anything, binds nothing                                 |
| `id`                             | anything, binds `id` to it                              |
| `42` `"s"` `#t` `'sym`           | that literal (by `equal?`)                              |
| `(list p ...)`                   | a list of exactly those elements                        |
| `(list p ... pn ...)` (ellipsis) | `pn ...` matches zero or more; binds each var to a list |
| `(list* p ... rest)`             | fixed head, `rest` bound to the tail                    |
| `(cons a d)` `(vector p ...)`    | pair / vector by position                               |
| `(struct id (p ...))`            | a `id` instance, fields by position                     |
| `(struct* id ([field p] ...))`   | a `id` instance, fields by name (any subset)            |
| `(? pred p ...)`                 | value satisfies `pred`, then also matches `p ...`       |
| `(and p ...)` `(or p ...)`       | all / any (each `or` arm must bind the same vars)       |
| `(not p ...)`                    | none of `p ...` match                                   |
| `(app fn p)`                     | apply `fn` to the value, match result against `p`       |
| `(== expr)`                      | value is `equal?` to `expr` (a *value*, not a pattern)  |
| `` `(a ,x ,@xs) ``               | quasiquote: literals match, `,x`/`,@xs` bind            |
| `(regexp rx)` / `(regexp rx p)`  | string matches `rx`; second form matches the match-list |
| `(hash-table (key p) ...)`       | hash with those keys, values matched by `p`             |
| `(list-no-order p ...)`          | a list containing those elements in any order           |

Ellipsis depth: `(list (list x y) ...)` binds `x` and `y` to *lists*, one
element per inner pair. `(list p ..3)` requires at least three.

## Repeated variables constrain by equality

Using the same pattern variable twice means the two positions must be
`equal?` — handy with `match*`, which matches several values at once:

```racket
(match* (a b)
  [(x x) 'equal]                       ; fires only when a equal? b
  [((? number?) (? number?)) (if (< a b) 'less 'greater)]
  [(_ _) 'incomparable])
```

## Binding forms

When you only have one shape and don't need dispatch, skip the clause list:

```racket
(match-define (list lo hi) (compute-range))   ; bind lo, hi in this scope
(match-let ([(cons a b) p]) (+ a b))           ; like let, with patterns
(define area (match-lambda [(posn x y) (* x y)]))  ; a 1-arg matching fn
(match-lambda** [(a b) ...] ...)               ; multi-arg, like match*
```

`match-let*` threads bindings left to right; `match-letrec` allows
recursion; `match-lambda*` matches against the *argument list*.

## Guards and fallthrough

Express side conditions three ways, in rough order of preference:

- **`#:when cond`** after the pattern — the cleanest boolean guard. If
  `cond` is false the clause is abandoned and matching resumes at the next
  clause: `[x #:when (even? x) ...]`.
- **`(? predicate)`** inside the pattern, when the test is local to one
  position: `[(? string? s) ...]`, `[(and n (? even?)) ...]`.
- **The `(=> fail)` escape** when the decision needs values computed in the
  body: bind a zero-argument `fail` and call it to abandon this clause and
  resume at the next one.

```racket
(match v
  [(list a b) #:when (> a b) 'a-bigger]                  ; guard with #:when
  [(list a b) (=> fail) (if (= a b) (fail) 'a-smaller)]  ; or escape via =>
  [_ 'other])
```

## Custom patterns

`define-match-expander` names a reusable pattern (optionally also an
expression). Its transformer runs at phase 1, so require
`(for-syntax racket/base)`:

```racket
(require racket/match (for-syntax racket/base))
(define-match-expander origin
  (lambda (stx) #'(posn 0 0)))            ; used as a pattern: (origin)
(match p [(origin) 'at-origin] [_ 'elsewhere])
```

## Rules that prevent rework

- **Order clauses specific-to-general.** First match wins; a broad pattern
  (`id`, `_`, `(? string?)`) placed early shadows the narrower clauses below
  it. Put `_` last as the catch-all.
- **`app` applies its function unconditionally.** `(app string->number n)`
  runs `string->number` on *whatever* reaches it and errors on a non-string
  — guard it: `(and (? string?) (app string->number (? number? n)))`.
- **Ellipsis binds to a list, one level deeper.** A var under `...` is a list
  in the body; under two `...` it is a list of lists. Match the ellipsis
  depth to how you consume the variable.
- **`==` takes a value, quoting takes a literal.** Use `(== expr)` to compare
  against a computed value; a bare literal or `'sym` matches that constant.
  Don't write `(== 'sym)` where `'sym` already works.
- **`or` arms must bind the same variables.** Every alternative in
  `(or p ...)` has to introduce the same set of pattern variables, or the
  body can't use them.
- **A non-exhaustive `match` raises at runtime, not compile time.** Add a
  final `[_ ...]` (or an explicit error) when the input set is open, so a
  missed shape is a clear message rather than a bare `match` failure.
- **Match expanders need `(for-syntax racket/base)`.** The expander body is
  transformer code; without the phase-1 import you get "unbound identifier:
  lambda".
