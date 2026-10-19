---
description: "Define and use Racket structs. Covers the struct form and its options (#:transparent, #:mutable, #:prefab, #:guard, #:auto, #:constructor-name), inheritance and subtype predicates, functional update with struct-copy, and generic interfaces through #:methods (gen:custom-write, gen:equal+hash, prop:procedure). Use when you define a struct, when you choose between transparent, opaque, and prefab, when you control the construction, when you customize the print or the equality, or when you decide between a struct and a list or a hash."
allowed-tools: Read, Grep, Glob
---

# Racket structs

`struct` defines a new compound data type. One declaration generates a
constructor, a type predicate, and an accessor per field (plus a setter per
field when the struct is mutable). It is part of `racket/base`. No require
is necessary.

For the exact `struct` grammar, every keyword option, and the generated
bindings, read `reference.md` in this skill directory.

```racket
(struct posn (x y) #:transparent)
(posn 3 4)        ; the constructor
(posn? v)         ; the predicate
(posn-x p)        ; an accessor per field
```

## Opacity: pick it on purpose

This is the first decision, because it governs the equality, the print, and
the serialization:

| Mode             | `equal?`                | Prints as            | Use for                                  |
|------------------|-------------------------|----------------------|------------------------------------------|
| opaque (default) | identity (`eq?`)        | `#<posn>`            | encapsulated state, hidden invariants    |
| `#:transparent`  | structural (by field)   | `#(struct:posn 3 4)` | value types, test data, most cases       |
| `#:prefab`       | structural              | `#s(posn 3 4)`       | data that must `read` or serialize       |

The "Prints as" column is the `write` and `display` output. `print`, which
the REPL and `~v` use, shows a transparent struct as `(posn 3 4)` and a
prefab struct as `'#s(posn 3 4)`.

```racket
(equal? (posn 1 2) (posn 1 2))   ; #f when opaque, #t when transparent or prefab
```

- **Default to `#:transparent`** for a plain value type. An opaque struct
  compares by identity. So two values that look equal are `equal?`-distinct.
  That is a frequent surprise in tests and in hash keys.
- **A `#:prefab`** struct needs no declaration for a reconstruction. `#s(posn
  1 2)` reads back to an equal value. So prefab structs cross `read`,
  `write`, and `racket/serialize` boundaries. The cost is zero
  encapsulation. Everybody can forge one. Use them for wire or disk data,
  not for invariants.
- **Opaque** is right when the struct guards an invariant, and outside code
  must not see or fabricate its fields.

## Mutability

A field is immutable unless you opt in. `#:mutable` makes every field
mutable, and it generates `set-name-field!`. Mark an individual field with
`#:mutable` in the field spec for finer control.

```racket
(struct counter (n) #:mutable #:transparent)
(define c (counter 0))
(set-counter-n! c 5)

(struct cell ([v #:mutable] tag))   ; only v is mutable
```

Prefer immutable structs plus `struct-copy` (below), unless you need shared
mutable state. An immutable value is safe to share and to hash.

## Control the construction

- **`#:guard`** runs before the instance exists. It gets the field values
  plus the struct name, and it returns the field values (possibly coerced),
  or it raises. Use it to validate or normalize:

  ```racket
  (struct temp (celsius)
    #:transparent
    #:guard (lambda (c name)
              (unless (real? c) (error name "need a real"))
              c))
  ```

  The guard of a subtype runs after the guard of the supertype. It gets the
  super fields that the super guard already checked.

- **`#:auto` and `#:auto-value`** give fields that Racket fills
  automatically (not constructor arguments). An auto field must come last:

  ```racket
  (struct node (val [next #:auto]) #:auto-value 'none #:mutable)
  (node 10)   ; => next is 'none
  ```

- **`#:constructor-name` and `#:extra-constructor-name`** rename or add a
  constructor (for example, keep `make-posn` beside `posn`).

## Inheritance

A struct can extend another struct. The subtype satisfies the supertype
predicate, and it inherits the accessors of the supertype.

```racket
(struct posn (x y) #:transparent)
(struct posn3 posn (z) #:transparent)
(define q (posn3 1 2 3))
(posn? q)      ; #t. The subtype is a posn
(posn-x q)     ; 1. An inherited accessor
(posn3-z q)    ; 3
```

Prefer composition (a field that holds another struct) to a deep
hierarchy. One level of extension for a real "is a" relation is acceptable.

## Functional update

`struct-copy` builds a new instance from an existing one, with the named
fields overridden. It is the immutable way to "change" a field:

```racket
(struct-copy posn p [y 99])   ; a new posn with the x of p, and y = 99
```

## Customize the behavior with #:methods

Implement a generic interface inline. The common ones:

- **`gen:custom-write`** controls the print. `make-constructor-style-printer`
  (from `racket/struct`) is the standard helper. Note that it prints
  differently by mode: `#<point: 3 4>` under `write` and `display`, `(point
  3 4)` under `print`.

  ```racket
  (require racket/struct)
  (struct point (x y)
    #:methods gen:custom-write
    [(define write-proc
       (make-constructor-style-printer
        (lambda (self) 'point)
        (lambda (self) (list (point-x self) (point-y self)))))])
  ```

- **`gen:equal+hash`** gives an opaque struct value equality. It needs all
  three procedures: `equal-proc`, `hash-proc`, and `hash2-proc`. If one is
  absent, the struct definition fails with "required method is not
  implemented". `gen:equal-mode+hash` is the newer alternative with two
  methods, `equal-mode-proc` and `hash-mode-proc`. Each one takes one extra
  `mode` argument, which is `#t` under `equal?` and `#f` under
  `equal-always?`. So one struct can tell the two equalities apart:

  ```racket
  (struct box2 (v)
    #:methods gen:equal-mode+hash
    [(define (equal-mode-proc a b recur mode) (recur (box2-v a) (box2-v b)))
     (define (hash-mode-proc a recur mode)    (recur (box2-v a)))])
  ```

  Either one is necessary only when you want a custom equality.
  `#:transparent` already gives structural `equal?`.

- **`#:property prop:procedure`** makes the instances applicable like
  functions:

  ```racket
  (struct adder (n) #:property prop:procedure
    (lambda (self x) (+ (adder-n self) x)))
  ((adder 5) 10)   ; => 15
  ```

## Reflection and contracts

`(struct->vector v)` gives `#(struct:posn 1 2)` for inspection. Full field
access through `struct-info` requires a transparent struct (or the right
inspector). That is another reason that an opaque struct hides its data. To
put a contract on the fields of a struct at a module boundary, use the
`struct` clause of `contract-out` (see [contracts](../contracts/SKILL.md)).

## Rules that prevent rework

- **Choose the opacity before the fields.** Opaque `equal?` is identity. If
  you will compare instances, put them in hash keys, or assert on them in
  tests, use `#:transparent`. Use opaque only to protect an invariant.
- **`#:prefab` is for data that must serialize, not for invariants.**
  Everybody can write `#s(tag …)`. So a prefab struct guarantees nothing
  about its contents. Never use one to enforce a constraint.
- **`#:guard` runs before the struct exists.** It sees the field values and
  the type name, not an instance. Return the (coerced) values, or raise. It
  is the place to validate the arguments at construction time.
- **An auto field comes last, and it is not a constructor argument.** Order
  the auto fields after all the explicit fields. Give an `#:auto-value`, or
  they default to `#f`.
- **Prefer immutable plus `struct-copy` to `#:mutable`.** An immutable
  struct is safe to share and to hash. Add mutability only for state that is
  really shared.
- **Use a struct when the fields have a fixed meaning.** A struct documents
  the intent, and it checks the arity at construction. Use a list or a hash
  only for homogeneous or open-ended data.
