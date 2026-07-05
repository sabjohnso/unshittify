---
name: generics
description: Define generic interfaces in Racket with racket/generic — define-generics to declare a set of methods, implement them per type via #:methods gen:NAME, provide defaults/fallbacks (#:defaults, #:fast-defaults, #:fallbacks), call sibling methods with define/generic, introspect support (#:defined-predicate, exn:fail:support?), and contract instances with generic-instance/c. Use when several types should share an interface with runtime dispatch, or extending an interface to existing types.
---

# Generic Interfaces with racket/generic

`racket/generic` lets you declare an **interface** — a named set of methods —
once, then implement it for many types. Calling a method dispatches at
runtime on its first argument. This is the mechanism behind built-in
interfaces like `gen:custom-write` and `gen:equal+hash` (see [[structs]]);
`define-generics` lets you define your own.

```racket
(require racket/generic)

(define-generics shape
  (area shape)
  (describe shape [prefix]))             ; [prefix] is an optional method arg

(struct square (side)
  #:methods gen:shape
  [(define (area s) (* (square-side s) (square-side s)))
   (define (describe s [prefix "sq"]) (format "~a ~a" prefix (square-side s)))])

(area (square 4))                        ; => 16
```

## What `define-generics` creates

From `(define-generics shape (area shape) …)` you get:

- **`gen:shape`** — the binding you pass to `#:methods` to implement the
  interface for a struct.
- **`shape?`** — a predicate: true for any value implementing the interface.
- **`area`, `describe`, …** — the generic methods, each dispatching on its
  `shape` argument.

The name in the first position of each method clause (`shape`) marks which
argument is dispatched on; it must be the same across the methods.

## Implementing the interface

Implement in a struct with `#:methods gen:NAME` (see [[structs]]). To call
**another method of the same interface** from inside a method body, you must
capture it with `define/generic` — a bare reference does **not** dispatch and
fails with "method not implemented":

```racket
(struct wrapped (inner)
  #:methods gen:renderable
  [(define/generic super-render render)    ; capture the generic `render`
   (define (render w) (string-append "[" (super-render (wrapped-inner w)) "]"))])
```

This is the single most common mistake with `racket/generic`: inside
`#:methods`/`#:fallbacks`, sibling calls go through a `define/generic` alias.

## Defaults and fallbacks

Three ways to supply behavior beyond a per-struct `#:methods`:

- **`#:defaults ([pred impl …] …)`** — implement the interface for existing
  types you don't control (e.g. `number?`, `string?`):

  ```racket
  (define-generics shape
    (area shape)
    #:defaults ([number? (define (area n) (* n n))]))
  (area 5)                                ; => 25
  ```

- **`#:fast-defaults ([pred impl …] …)`** — same, but checked *before* the
  normal dispatch, for hot built-in types.

- **`#:fallbacks [impl …]`** — default method bodies used when an
  implementing type leaves a method out. Write them in terms of other
  methods (captured with `define/generic`):

  ```racket
  (define-generics container
    (items container)
    (size container)
    #:fallbacks
    [(define/generic g-items items)
     (define (size c) (length (g-items c)))])   ; size defaults to item count
  ```

`#:requires (method …)` declares methods an implementation must provide (the
ones fallbacks depend on). `#:derive-property prop expr` attaches a struct
type property computed from the methods — e.g. derive `prop:custom-write`
from a `->string` method so instances print through the interface.

## Asking what a value implements

`#:defined-predicate name` adds a procedure to test whether a specific
instance implements a given method; `#:defined-table name` exposes the full
map. Calling an *un*implemented method raises `exn:fail:support?`:

```racket
(define-generics container (items container) (size container)
  #:defined-predicate container-implements?)
(container-implements? some-stack 'size)         ; #t / #f
```

## Contracting an interface

`(generic-instance/c gen:shape)` is a contract satisfied by any value
implementing the interface — use it at module boundaries to demand "something
shaped," not a concrete struct (see [[contracts]]):

```racket
(provide (contract-out [total-area (-> (listof (generic-instance/c gen:shape)) real?)]))
```

## When to use a generic interface

Reach for `racket/generic` when **several types** should answer the same
operations and callers shouldn't care which type they hold — open extension,
where new types implement the interface without touching the callers. For a
closed set of cases, a plain function with `match`/`cond` ([[pattern-matching]])
is simpler. For one type, just write functions. Generics earn their keep when
the type set is open and dispatch must stay out of the call sites.

## Rules that prevent rework

- **`define/generic` for every sibling call.** Inside `#:methods`/`#:fallbacks`,
  capture other methods with `define/generic` before calling them; a bare
  reference fails at runtime.
- **Dispatch is on the first (marked) argument only.** Design methods so the
  type that selects the implementation comes first; `racket/generic` is
  single-dispatch.
- **Extend existing types with `#:defaults`, not wrappers.** Implement the
  interface for `number?`/`string?`/etc. directly instead of boxing them.
- **Use `#:fallbacks` for derivable methods.** Define the minimal primitive
  methods per type and let fallbacks compute the rest in terms of them —
  fewer per-struct method bodies to keep in sync.
- **`provide` the `gen:NAME` binding to let other modules implement it.**
  Export `gen:shape` (and the predicate/methods) so downstream structs can
  add `#:methods gen:shape` (see [[modules]]).
- **Contract with `generic-instance/c`, not the struct predicate.** Accept any
  implementer at the boundary so new types keep working ([[contracts]]).
