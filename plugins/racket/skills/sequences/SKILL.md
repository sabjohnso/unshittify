---
description: Iterate and build data with Racket for-loops and sequences — the for family (for/list, for/vector, for/hash, for/fold, for/sum), iteration clauses (#:when, #:break, #:final, parallel bindings), sequence constructors (in-range, in-list, in-vector, in-hash, in-naturals), racket/sequence operations, and the three ways to define new sequences (prop:sequence, make-do-sequence, define-sequence-syntax). Use when writing a loop or comprehension, choosing a sequence constructor, or making a value iterable.
---

# For-loops and Sequences

A `for` loop walks one or more **sequences**, binding a variable to each
element. The plain `for` runs its body for effect; the `for/…`
comprehensions collect the body's results into a list, vector, hash, or fold.
Sequences are the common iteration protocol — lists, vectors, strings,
hashes, ranges, ports, and your own types all flow through the same `for`.

```racket
(for ([x (in-list '(a b c))]) (displayln x))          ; effect
(for/list ([x (in-range 5)]) (* x x))                 ; => '(0 1 4 9 16)
```

## The for family

Pick the variant by what you want back:

| Form                      | Result                                            |
|---------------------------|---------------------------------------------------|
| `for`                     | `(void)` — run body for effect                    |
| `for/list`                | a list of body values                             |
| `for/vector`              | a vector (`#:length` to preallocate)              |
| `for/hash` `for/hasheq`   | a hash; body returns `(values key val)`           |
| `for/fold`                | one or more accumulators (below)                  |
| `for/sum` `for/product`   | numeric reduction of body values                  |
| `for/and` `for/or`        | boolean reduction (short-circuits)                |
| `for/first` `for/last`    | the first / last body value                       |
| `for/lists`               | several parallel lists from a `values` body       |
| `for/string` `for/bytes`  | a string / byte string                            |

Each has a `for*/…` sibling that nests the clauses (a Cartesian product)
instead of iterating them in parallel.

## for/fold — accumulate

`for/fold` threads accumulators through the loop; the body returns a new
value per accumulator with `values`, and `#:result` shapes the final answer:

```racket
(for/fold ([sum 0] [cnt 0] #:result (/ sum cnt))
          ([x (in-list '(2 4 6))])
  (values (+ sum x) (+ cnt 1)))            ; => 4  (the average)
```

`for/foldr` folds from the right. `for/fold` is the general tool — the other
comprehensions are specializations of it.

## Iteration clauses

Inside the clause list, after the bindings:

- **Parallel bindings** iterate together, stopping at the shortest:
  `([x (in-range 10)] [y (in-naturals 100)])`.
- **`#:when cond` / `#:unless cond`** filter; bindings *before* them are in
  scope, and a binding *after* `#:when` restarts iteration (it nests).
- **`#:break cond`** stops the loop (excluding the current element);
  **`#:final cond`** runs this iteration, then stops.
- **`#:do [body ...]`** runs side code between clauses.
- **`(k v)` patterns** bind multiple values per step, e.g. from `in-hash` or
  `in-indexed`.

```racket
(for/list ([x (in-range 10)] [y (in-naturals 100)]
           #:when (even? x))
  (list x y))                              ; => '((0 100) (2 102) (4 104) ...)

(for/list ([x (in-naturals)] #:break (> x 4)) x)   ; => '(0 1 2 3 4)
```

`for*` is the nested form: `(for*/list ([x '(1 2)] [y '(a b)]) (list x y))`
yields all four combinations.

## Sequence constructors

The `in-…` forms describe how to iterate a value. **Prefer the specific
constructor** — `(in-list xs)` not bare `xs` — because `for` then compiles a
specialized, allocation-free loop; a bare value falls back to the generic
`sequence?` dispatch.

| Constructor                          | Iterates                                  |
|--------------------------------------|-------------------------------------------|
| `(in-range end)` / `(in-range a b step)` | numbers                               |
| `(in-list xs)` `(in-vector v)` `(in-string s)` `(in-bytes b)` | elements |
| `(in-hash h)` / `in-hash-keys` / `in-hash-values` | hash entries             |
| `(in-naturals [start])`              | `0,1,2,…` — a counter to pair in parallel |
| `(in-cycle seq …)`                   | the sequence(s), forever                  |
| `(in-value v)`                       | exactly one element (`v`)                 |
| `(in-indexed seq)`                   | `(values element index)`                  |
| `(in-sequences s …)` / `(in-parallel s …)` | concatenate / zip                   |
| `(in-port read p)` `(in-lines p)`    | a port's data                             |

`in-naturals` paired with another sequence is the idiomatic index counter.

## racket/sequence operations

`(require racket/sequence)` for sequence-level combinators that work on any
sequence without realizing it to a list first:

```racket
(sequence->list (in-range 3))                    ; '(0 1 2)
(sequence-map add1 '(1 2 3))                     ; a sequence: 2 3 4
(sequence-filter even? (in-range 10))            ; 0 2 4 6 8
(sequence-ref (in-naturals) 7)                   ; 7
(sequence-tail (in-range 6) 3)                   ; 3 4 5
(for/list ([s (in-slice 2 (in-range 6))]) (sequence->list s))  ; '((0 1)(2 3)(4 5))
```

`empty-sequence`, `sequence-append`, `sequence-fold`, and `sequence-length`
round out the set.

## Defining new sequences

Three mechanisms, from simplest to fastest:

### 1. `prop:sequence` — make a struct iterable

When a struct just wraps something already iterable, delegate. This is the
easiest and usually enough (see [[structs]]):

```racket
(struct ring (items)
  #:property prop:sequence
  (lambda (r) (in-list (ring-items r))))
(for/list ([x (ring '(a b c))]) x)               ; => '(a b c)
```

### 2. `make-do-sequence` — a sequence value from position functions

For iteration not backed by an existing collection, return a sequence whose
thunk supplies the position protocol: element-from-position, next-position,
initial-position, and continue-while predicates.

```racket
(define (in-countdown n)
  (make-do-sequence
   (lambda ()
     (values (lambda (pos) pos)        ; pos -> element
             (lambda (pos) (sub1 pos)) ; next position
             n                         ; initial position
             (lambda (pos) (> pos 0))  ; continue while true
             #f #f))))
(for/list ([x (in-countdown 5)]) x)              ; => '(5 4 3 2 1)
```

### 3. `define-sequence-syntax` — an `in-X` that inlines in `for`

For a hot, reusable iterator, define a macro that the compiler splices
*inline* into the loop via `:do-in` (no per-step closure), with a procedure
**fallback** for when it is used as an ordinary sequence value. Always
provide the fallback:

```racket
(require (for-syntax racket/base))
(define-sequence-syntax in-evens
  (lambda () #'in-evens/proc)                     ; fallback value form
  (lambda (stx)                                   ; inline expansion in `for`
    (syntax-case stx ()
      [[(x) (_ hi)]
       #'[(x) (:do-in ([(h) hi]) #t ([i 0]) (< i h)
                      ([(x) (* 2 i)]) #t #t [(add1 i)])]])))
(define (in-evens/proc hi) (sequence-map (lambda (i) (* 2 i)) (in-range hi)))
```

For lazy or coroutine-style sequences, `in-generator` (from
`racket/generator`) is an easier alternative: a body that `yield`s values
becomes a sequence (see [[macros]] only if you need compile-time inlining).

## Rules that prevent rework

- **Annotate sequences for speed.** Write `(in-list xs)`/`(in-vector v)`, not
  the bare value — `for` then emits a specialized loop. The bare form works
  but goes through generic dispatch and allocates.
- **`for/fold` bodies return `values`.** One value per accumulator, in order;
  use `#:result` to project the final answer instead of post-processing.
- **`#:when`/`#:unless` nest, they don't just filter.** A binding after a
  `#:when` re-iterates for each surviving outer element — exactly `for*`-style
  nesting; order clauses accordingly.
- **Pick the comprehension, don't rebuild it.** `for/sum`, `for/hash`,
  `for/first` already exist; reach for `for/fold` only when none fit.
- **Make structs iterable with `prop:sequence` first.** Drop to
  `make-do-sequence` only for non-collection iteration, and to
  `define-sequence-syntax` only when profiling ([[profiling]]) shows the loop
  is hot — and always give it a proc fallback.
