---
name: structs
description: Define and use Racket structs — the struct form and its options (#:transparent, #:mutable, #:prefab, #:guard, #:auto, #:constructor-name), inheritance and subtype predicates, struct-copy functional update, and generic interfaces via #:methods (gen:custom-write, gen:equal+hash, prop:procedure). Use when defining a struct, choosing transparent/opaque/prefab, controlling construction, customizing printing or equality, or deciding struct vs list/hash.
---

# Racket Structs

`struct` defines a new compound data type. One declaration generates a
constructor, a type predicate, and an accessor per field (plus setters when
mutable). It is built into `racket/base` — no require needed.

```racket
(struct posn (x y) #:transparent)
(posn 3 4)        ; constructor
(posn? v)         ; predicate
(posn-x p)        ; accessor per field
```

## The opacity spectrum — pick deliberately

This is the first decision, because it governs equality, printing, and
serialization:

| Mode            | `equal?`              | Prints as        | Use for                              |
|-----------------|-----------------------|------------------|--------------------------------------|
| opaque (default)| identity (`eq?`)      | `#<posn>`        | encapsulated state, hidden invariants|
| `#:transparent` | structural (by field) | `#(struct:posn 3 4)` | value types, test data, most cases |
| `#:prefab`      | structural            | `#s(posn 3 4)`   | data that must `read`/serialize      |

```racket
(equal? (posn 1 2) (posn 1 2))   ; #f when opaque, #t when transparent/prefab
```

- **Default to `#:transparent`** for plain value types. Opaque structs
  compare by identity, so two equal-looking values are `equal?`-distinct —
  a frequent surprise in tests and hash keys.
- **`#:prefab`** structs need no declaration to be reconstructed: `#s(posn
  1 2)` reads back to an equal value, so they cross `read`/`write` and
  `racket/serialize` boundaries. The cost is zero encapsulation — anyone can
  forge one. Use them for wire/disk data, not for invariants.
- **Opaque** is right when the struct guards an invariant and outside code
  should not see or fabricate its fields.

## Mutability

Fields are immutable unless you opt in. `#:mutable` makes every field
mutable and generates `set-name-field!`; mark individual fields with
`#:mutable` in the field spec for finer control.

```racket
(struct counter (n) #:mutable #:transparent)
(define c (counter 0))
(set-counter-n! c 5)

(struct cell ([v #:mutable] tag))   ; only v is mutable
```

Prefer immutable structs plus `struct-copy` (below) unless you need shared
mutable state — immutable values are safe to share and hash.

## Controlling construction

- **`#:guard`** runs before the instance exists; it receives the field
  values plus the struct name and returns the (possibly coerced) field
  values, or raises. Use it to validate or normalize:

  ```racket
  (struct temp (celsius)
    #:transparent
    #:guard (lambda (c name)
              (unless (real? c) (error name "need a real"))
              c))
  ```

  A subtype's guard runs after the supertype's, receiving the already-guarded
  super fields.

- **`#:auto` / `#:auto-value`** give fields filled in automatically (not
  constructor arguments) — auto fields must come last:

  ```racket
  (struct node (val [next #:auto]) #:auto-value 'none #:mutable)
  (node 10)   ; => next is 'none
  ```

- **`#:constructor-name` / `#:extra-constructor-name`** rename or add a
  constructor (e.g. keep `make-posn` alongside `posn`).

## Inheritance

A struct may extend another; the subtype satisfies the supertype predicate
and inherits its accessors.

```racket
(struct posn (x y) #:transparent)
(struct posn3 posn (z) #:transparent)
(define q (posn3 1 2 3))
(posn? q)      ; #t — subtype is a posn
(posn-x q)     ; 1  — inherited accessor
(posn3-z q)    ; 3
```

Prefer composition (a field holding another struct) over deep hierarchies;
single-level extension for genuine "is-a" is fine.

## Functional update

`struct-copy` builds a new instance from an existing one, overriding named
fields — the immutable-friendly way to "change" a field:

```racket
(struct-copy posn p [y 99])   ; new posn with p's x, y = 99
```

## Customizing behavior with #:methods

Implement a generic interface inline. Common ones:

- **`gen:custom-write`** — control printing. `make-constructor-style-printer`
  (from `racket/struct`) is the standard helper. Note it prints differently
  by mode: `#<point: 3 4>` under `write`/`display`, `(point 3 4)` under
  `print`.

  ```racket
  (require racket/struct)
  (struct point (x y)
    #:methods gen:custom-write
    [(define write-proc
       (make-constructor-style-printer
        (lambda (self) 'point)
        (lambda (self) (list (point-x self) (point-y self)))))])
  ```

- **`gen:equal+hash`** — give an opaque struct value equality (three procs:
  `equal-proc`, `hash-proc`, `hash2-proc`). Only needed when you want custom
  equality; `#:transparent` already gives structural `equal?`.

- **`#:property prop:procedure`** — make instances applicable like
  functions:

  ```racket
  (struct adder (n) #:property prop:procedure
    (lambda (self x) (+ (adder-n self) x)))
  ((adder 5) 10)   ; => 15
  ```

## Reflection and contracts

`(struct->vector v)` yields `#(struct:posn 1 2)` for inspection; full field
access via `struct-info` requires a transparent struct (or the right
inspector) — another reason opaque hides data. To contract a struct's fields
at a module boundary, use the `struct` clause of `contract-out` (see
[[contracts]]).

## Rules that prevent rework

- **Choose opacity before fields.** Opaque `equal?` is identity; if you will
  compare instances, put them in hash keys, or assert on them in tests, use
  `#:transparent`. Reach for opaque only to protect an invariant.
- **`#:prefab` is for data that must serialize, not for invariants.** Anyone
  can write `#s(tag …)`, so a prefab struct guarantees nothing about its
  contents — never use one to enforce a constraint.
- **`#:guard` runs before the struct exists.** It sees field values and the
  type name, not an instance; return the (coerced) values or raise. It is
  the place for construction-time validation.
- **Auto fields come last and aren't constructor arguments.** Order them
  after all explicit fields; supply `#:auto-value` or they default to `#f`.
- **Prefer immutable + `struct-copy` to `#:mutable`.** Immutable structs are
  safe to share and hash; add mutability only for genuinely shared state.
- **Use a struct when fields have fixed meaning.** A struct documents intent
  and checks arity at construction; reach for a list/hash only for
  homogeneous or open-ended data.
