---
description: "Define generic interfaces in Racket with racket/generic. Covers define-generics to declare a set of methods, the implementation of the methods per type with #:methods gen:NAME, defaults and fallbacks (#:defaults, #:fast-defaults, #:fallbacks), a call to a sibling method with define/generic, the introspection of support (#:defined-predicate, exn:fail:support?), and a contract on an instance with generic-instance/c. Use when several types must share an interface with runtime dispatch, or when you extend an interface to existing types."
allowed-tools: Read, Grep, Glob
---

# Generic interfaces with racket/generic

With `racket/generic`, you declare an **interface** (a named set of methods)
once, and then you implement it for many types. A call to a method
dispatches at run time on its first argument. This is the mechanism behind
the built-in interfaces such as `gen:custom-write` and `gen:equal+hash` (see
[structs](../structs/SKILL.md)). With `define-generics`, you define your
own.

For the exact grammar of `define-generics`, its keyword options, and the
contract forms, read `reference.md` in this skill directory.

```racket
(require racket/generic)

(define-generics shape
  (area shape)
  (describe shape [prefix]))             ; [prefix] is an optional method argument

(struct square (side)
  #:methods gen:shape
  [(define (area s) (* (square-side s) (square-side s)))
   (define (describe s [prefix "sq"]) (format "~a ~a" prefix (square-side s)))])

(area (square 4))                        ; => 16
```

## What `define-generics` creates

From `(define-generics shape (area shape) …)` you get:

- **`gen:shape`**, the binding that you pass to `#:methods` to implement the
  interface for a struct.
- **`shape?`**, a predicate. It is true for every value that implements the
  interface.
- **`area`, `describe`, …**, the generic methods. Each one dispatches on its
  `shape` argument.

The name in the first position of each method clause (`shape`) marks the
argument that the dispatch uses. It must be the same across the methods.

## Implement the interface

Implement it in a struct with `#:methods gen:NAME` (see
[structs](../structs/SKILL.md)). To call **an other method of the same
interface** from inside a method body, you must capture it with
`define/generic`. A bare reference does **not** dispatch, and it fails with
"method not implemented":

```racket
(struct wrapped (inner)
  #:methods gen:renderable
  [(define/generic super-render render)    ; capture the generic `render`
   (define (render w) (string-append "[" (super-render (wrapped-inner w)) "]"))])
```

This is a common mistake with `racket/generic`. Inside `#:methods` and
`#:fallbacks`, a sibling call goes through a `define/generic` alias.

## Defaults and fallbacks

There are three ways to give behavior beyond a `#:methods` per struct:

- **`#:defaults ([pred impl …] …)`** implements the interface for existing
  types that you do not control (for example `number?`, `string?`):

  ```racket
  (define-generics shape
    (area shape)
    #:defaults ([number? (define (area n) (* n n))]))
  (area 5)                                ; => 25
  ```

- **`#:fast-defaults ([pred impl …] …)`** is the same, but the check comes
  *before* the normal dispatch, for hot built-in types.

- **`#:fallbacks [impl …]`** gives default method bodies for a method that
  an implementer leaves out. Write them in terms of the other methods
  (captured with `define/generic`):

  ```racket
  (define-generics container
    (items container)
    (size container)
    #:fallbacks
    [(define/generic g-items items)
     (define (size c) (length (g-items c)))])   ; size defaults to the item count
  ```

`#:requires (method …)` declares the methods that an implementation must
give (the ones that the fallbacks depend on). `#:derive-property prop expr`
attaches a struct type property computed from the methods. For example,
derive `prop:custom-write` from a `->string` method, so the instances print
through the interface.

## Ask what a value implements

`#:defined-predicate name` adds a procedure that tests whether a specific
instance implements a given method. `#:defined-table name` exposes the full
map. A call to a method with *no* implementation raises `exn:fail:support?`:

```racket
(define-generics container (items container) (size container)
  #:defined-predicate container-implements?)
(container-implements? some-stack 'size)         ; #t / #f
```

## A contract on an interface

`(generic-instance/c gen:shape)` is a contract that every value that
implements the interface satisfies. Use it at a module boundary to demand
"something with a shape", not a concrete struct (see
[contracts](../contracts/SKILL.md)):

```racket
(provide (contract-out [total-area (-> (listof (generic-instance/c gen:shape)) real?)]))
```

## When to use a generic interface

Use `racket/generic` when **several types** must answer the same operations,
and the callers must not care which type they hold. That is open extension.
A new type implements the interface, and the callers do not change. For a
closed set of cases, a plain function with `match` or `cond`
([pattern-matching](../pattern-matching/SKILL.md)) is simpler. For one type,
write functions. Generics earn their place when the set of types is open and
the dispatch must stay out of the call sites.

## Rules that prevent rework

- **Use `define/generic` for every sibling call.** Inside `#:methods` and
  `#:fallbacks`, capture the other methods with `define/generic` before you
  call them. A bare reference fails at run time.
- **The dispatch is on the first (marked) argument only.** Design the methods
  so that the type that selects the implementation comes first.
  `racket/generic` has single dispatch.
- **Extend an existing type with `#:defaults`, not with a wrapper.**
  Implement the interface for `number?`, `string?`, and the like directly.
  Do not box them.
- **Use `#:fallbacks` for a method that can be derived.** Define the minimal
  primitive methods per type, and let the fallbacks compute the rest from
  them. Then fewer method bodies per struct must stay in step.
- **`provide` the `gen:NAME` binding, so an other module can implement it.**
  Export `gen:shape` (and the predicate and the methods). Then a downstream
  struct can add `#:methods gen:shape` (see [modules](../modules/SKILL.md)).
- **Put a `generic-instance/c` contract at the boundary, not the struct
  predicate.** Accept every implementer at the boundary, so new types
  continue to work ([contracts](../contracts/SKILL.md)).
