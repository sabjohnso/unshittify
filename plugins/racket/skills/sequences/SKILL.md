---
description: "Iterate and build data with the Racket for loops and sequences. Covers the for family (for/list, for/vector, for/hash, for/fold, for/sum), the iteration clauses (#:when, #:break, #:final, parallel bindings), the sequence constructors (in-range, in-list, in-vector, in-hash, in-naturals), the racket/sequence operations, and the three ways to define a new sequence (prop:sequence, make-do-sequence, define-sequence-syntax). Use when you write a loop or a comprehension, when you choose a sequence constructor, or when you make a value iterable."
allowed-tools: Read, Grep, Glob
---

# For loops and sequences

A `for` loop walks one or more **sequences**, and it binds a variable to
each element. The plain `for` runs its body for the effect. The `for/…`
comprehensions collect the results of the body into a list, a vector, a
hash, or a fold. A sequence is the common iteration protocol. Lists,
vectors, strings, hashes, ranges, ports, and your own types all flow through
the same `for`.

For the exact grammar of a `for` clause, the full list of sequence
constructors, and the three ways to define a sequence, read `reference.md`
in this skill directory.

```racket
(for ([x (in-list '(a b c))]) (displayln x))          ; an effect
(for/list ([x (in-range 5)]) (* x x))                 ; => '(0 1 4 9 16)
```

## The for family

Pick the variant by the result that you want:

| Form                     | Result                                        |
|--------------------------|-----------------------------------------------|
| `for`                    | `(void)`. It runs the body for the effect     |
| `for/list`               | a list of the body values                     |
| `for/vector`             | a vector (`#:length` allocates it in advance) |
| `for/hash` `for/hasheq`  | a hash. The body returns `(values key val)`   |
| `for/fold`               | one or more accumulators (below)              |
| `for/sum` `for/product`  | a numeric reduction of the body values        |
| `for/and` `for/or`       | a boolean reduction (it short-circuits)       |
| `for/first` `for/last`   | the first or the last body value              |
| `for/lists`              | several parallel lists from a `values` body   |

Each one has a `for*/…` sibling that nests the clauses (a Cartesian
product) and does not iterate them in parallel.

There is **no `for/string` and no `for/bytes`**. Build those from
`for/list`: `(list->string (for/list ([c (in-string s)]) (char-upcase c)))`,
and `list->bytes` in the same way. (`2htdp/abstraction` defines a
`for/string`, but it is a form of a teaching language, not part of
`racket`.)

## for/fold: accumulate

`for/fold` threads accumulators through the loop. The body returns a new
value per accumulator with `values`, and `#:result` shapes the final answer:

```racket
(for/fold ([sum 0] [cnt 0] #:result (/ sum cnt))
          ([x (in-list '(2 4 6))])
  (values (+ sum x) (+ cnt 1)))            ; => 4  (the average)
```

`for/foldr` folds from the right. `for/fold` is the general tool. The other
comprehensions are special cases of it.

## The iteration clauses

Inside the clause list, after the bindings:

- **Parallel bindings** iterate together, and they stop at the shortest
  sequence: `([x (in-range 10)] [y (in-naturals 100)])`.
- **`#:when cond` and `#:unless cond`** filter. The bindings *before* them
  are in scope. A binding *after* `#:when` starts a new iteration (it
  nests).
- **`#:break cond`** stops the loop (without the current element).
  **`#:final cond`** runs this iteration, then stops.
- **`#:do [body ...]`** runs code with side effects between the clauses.
- **A `(k v)` pattern** binds several values per step, for example from
  `in-hash` or `in-indexed`.

```racket
(for/list ([x (in-range 10)] [y (in-naturals 100)]
           #:when (even? x))
  (list x y))                              ; => '((0 100) (2 102) (4 104) ...)

(for/list ([x (in-naturals)] #:break (> x 4)) x)   ; => '(0 1 2 3 4)
```

`for*` is the nested form. `(for*/list ([x '(1 2)] [y '(a b)]) (list x y))`
gives all four combinations.

## The sequence constructors

The `in-…` forms describe how to iterate a value. **Prefer the specific
constructor**, `(in-list xs)` and not a bare `xs`. Then `for` compiles a
specialized loop with no allocation. A bare value falls back to the generic
`sequence?` dispatch.

| Constructor                                                   | Iterates                                      |
|---------------------------------------------------------------|-----------------------------------------------|
| `(in-range end)` / `(in-range a b step)`                      | numbers                                       |
| `(in-list xs)` `(in-vector v)` `(in-string s)` `(in-bytes b)` | the elements                                  |
| `(in-hash h)` / `in-hash-keys` / `in-hash-values`             | the hash entries                              |
| `(in-naturals [start])`                                       | `0,1,2,…`, a counter to pair in parallel      |
| `(in-cycle seq …)`                                            | the sequences, without an end                 |
| `(in-value v)`                                                | exactly one element (`v`)                     |
| `(in-indexed seq)`                                            | `(values element index)`                      |
| `(in-sequences s …)` / `(in-parallel s …)`                    | a concatenation / a zip                       |
| `(in-port read p)` `(in-lines p)`                             | the data of a port                            |

`in-naturals` paired with an other sequence is the idiomatic index counter.

## The racket/sequence operations

`(require racket/sequence)` gives sequence-level combinators that work on
every sequence, with no conversion to a list first:

```racket
(sequence->list (in-range 3))                    ; '(0 1 2)
(sequence-map add1 '(1 2 3))                     ; a sequence: 2 3 4
(sequence-filter even? (in-range 10))            ; 0 2 4 6 8
(sequence-ref (in-naturals) 7)                   ; 7
(sequence-tail (in-range 6) 3)                   ; 3 4 5
(for/list ([s (in-slice 2 (in-range 6))]) (sequence->list s))  ; '((0 1)(2 3)(4 5))
```

`empty-sequence`, `sequence-append`, `sequence-fold`, and `sequence-length`
complete the set.

## Define a new sequence

There are three mechanisms, from the simplest to the fastest:

### 1. `prop:sequence`: make a struct iterable

When a struct only wraps something that is already iterable, delegate. This
is the easiest way, and it is usually enough (see `../structs/SKILL.md`):

```racket
(struct ring (items)
  #:property prop:sequence
  (lambda (r) (in-list (ring-items r))))
(for/list ([x (ring '(a b c))]) x)               ; => '(a b c)
```

### 2. `make-do-sequence`: a sequence value from position functions

For an iteration with no existing collection behind it, return a sequence
whose thunk gives the position protocol: the element from a position, the
next position, the initial position, and the predicates that decide whether
to continue.

```racket
(define (in-countdown n)
  (make-do-sequence
   (lambda ()
     (values (lambda (pos) pos)        ; the element from a position
             (lambda (pos) (sub1 pos)) ; the next position
             n                         ; the initial position
             (lambda (pos) (> pos 0))  ; continue while this is true
             #f #f))))
(for/list ([x (in-countdown 5)]) x)              ; => '(5 4 3 2 1)
```

### 3. `define-sequence-syntax`: an `in-X` that `for` inlines

For a hot, reusable iterator, define a macro that the compiler splices
*inline* into the loop through `:do-in` (no closure per step), with a
procedure **fallback** for a use as an ordinary sequence value. Always give
the fallback:

```racket
(require (for-syntax racket/base))
(define-sequence-syntax in-evens
  (lambda () #'in-evens/proc)                     ; the fallback value form
  (lambda (stx)                                   ; the inline expansion in `for`
    (syntax-case stx ()
      [[(x) (_ hi)]
       #'[(x) (:do-in ([(h) hi]) #t ([i 0]) (< i h)
                      ([(x) (* 2 i)]) #t #t [(add1 i)])]])))
(define (in-evens/proc hi) (sequence-map (lambda (i) (* 2 i)) (in-range hi)))
```

For a lazy or coroutine-style sequence, `in-generator` (from
`racket/generator`) is an easier alternative. A body that `yield`s values
becomes a sequence. See `../macros/SKILL.md` only if you need the
compile-time inline expansion.

## Rules that prevent rework

- **Use the specific sequence constructors for speed.** Write `(in-list
  xs)` or `(in-vector v)`, not the bare value. Then `for` emits a
  specialized loop. The bare form works, but it goes through the generic
  dispatch and it allocates.
- **A `for/fold` body returns `values`.** One value per accumulator, in
  order. Use `#:result` to project the final answer. Do not post-process it.
- **`#:when` and `#:unless` nest. They do not only filter.** A binding after
  a `#:when` iterates again for each outer element that survives. That is
  exactly the `for*` nest. Order the clauses accordingly.
- **Pick the comprehension. Do not build it again.** `for/sum`, `for/hash`,
  and `for/first` already exist. Use `for/fold` only when none of them fits.
- **Make a struct iterable with `prop:sequence` first.** Drop to
  `make-do-sequence` only for an iteration with no collection behind it.
  Drop to `define-sequence-syntax` only when a profile
  (`../profiling/SKILL.md`) shows that the loop is hot, and always give it a
  procedure fallback.
