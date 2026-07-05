---
name: classes
description: Object-oriented programming in Racket with racket/class — define classes over object%, create objects with new/make-object and message them with send, inheritance (super, override, the pubment/augment/inner hole), interfaces (interface, is-a?), composition via mixins and traits, abstract methods, and class/object contracts (class/c, object/c, is-a?/c, ->m). Use when writing stateful objects, working with racket/gui, or extending classes through mixins and interfaces.
---

# Object-Oriented Racket with racket/class

`racket/class` provides classes, objects, single inheritance, interfaces, and
composition through mixins and traits. Classes and objects are first-class
values: a class is an expression, `new` builds an object, and `send`
dispatches a method. This is the model `racket/gui` is built on.

Reach for `racket/class` when you need **stateful objects with behavior** or
must interoperate with a class-based library (notably `racket/gui`). For
plain data with operations, a [[structs]] + [[generics]] design is usually
simpler and more functional. When you do use classes, favor interfaces and
composition (mixins/traits) over deep inheritance hierarchies — open
extension without editing existing classes.

## Defining a class

```racket
(require racket/class)

(define animal%
  (class object%                       ; object% is the root class
    (init-field name [legs 4])         ; constructor args that become fields
    (field [steps 0])                  ; internal field, not a constructor arg
    (super-new)                        ; REQUIRED: initialize the superclass
    (define/public (describe) (format "~a (~a legs)" name legs))
    (define/public (walk! n) (set! steps (+ steps n)) steps)))
```

- Conventionally class names end in `%` and interface names in `<%>`.
- **`super-new` (or `super-make-object`) must run** in every class body, or
  construction fails.
- `init` is a constructor argument that is *not* stored; `init-field` is one
  that becomes a field; `field` is internal state. Bracketed forms give
  defaults: `[legs 4]`.
- `this` refers to the current object; `define/public` exposes a method.

## Creating objects and sending messages

```racket
(define a (new animal% [name "cat"]))          ; keyword init args
(make-object animal% "mouse" 4)                ; by position
(instantiate animal% () [name "ant"] [legs 6]) ; by position then keyword

(send a describe)                              ; call a method
(send a walk! 3)
(send* a (walk! 1) (walk! 2))                  ; several sends to one object
(dynamic-send a 'describe)                     ; method name computed at runtime
(get-field steps a)                            ; read a field; set-field! to write
```

## Inheritance

A subclass is a `class` whose superclass expression is another class. Use
`super` to call the overridden method, and `inherit`/`inherit-field` to use a
superclass member directly:

```racket
(define dog%
  (class animal%
    (super-new [legs 4])
    (inherit-field name)
    (define/override (describe) (format "~a the dog" (super describe))))) ; extend
```

- **`abstract`** declares a method with no body; a subclass must override it,
  and calling it on a non-overriding class errors:

  ```racket
  (class object% (super-new) (abstract area)
    (define/public (describe) (format "area=~a" (send this area))))
  ```

- **Augmentation** is the inverse of overriding: a superclass leaves an
  extension *hole* with `inner`, and subclasses fill it with `augment`
  instead of replacing the method. Declare the method `pubment` to make it
  augmentable:

  ```racket
  (class object% (super-new)
    (define/pubment (greet) (string-append "hi" (inner "" greet))))
  ;; subclass: (define/augment (greet) "!")  =>  "hi!"
  ```

  Override lets a subclass take control; augment lets the superclass stay in
  control and call down into a subclass hook.

## Interfaces

An `interface` names a set of method names. `class*` declares which
interfaces a class implements; `is-a?` and friends test membership — program
against the interface, not the concrete class:

```racket
(define drawable<%> (interface () draw bounds))
(define square%
  (class* object% (drawable<%>)
    (init-field side) (super-new)
    (define/public (draw) (format "square ~a" side))
    (define/public (bounds) (list side side))))

(is-a? (new square% [side 5]) drawable<%>)   ; #t
(implementation? square% drawable<%>)         ; #t
(subclass? square% object%)                   ; #t
```

## Composition over inheritance

### Mixins

A mixin is a function from a class to a class — it adds behavior to *any*
class without subclassing a fixed parent. This is the idiomatic open
extension in `racket/class`:

```racket
(define (logging-mixin %)
  (class % (super-new)
    (define/public (log-draw) (format "LOG: ~a" (send this draw)))))

(define logged-square% (logging-mixin square%))
```

The `mixin` form additionally states the interfaces the argument class must
implement and the result provides:

```racket
(mixin (drawable<%>) () (super-new)
  (define/public (twice) (string-append (send this draw) (send this draw))))
```

### Traits

Traits (`racket/trait`) are reusable, composable method sets that sidestep
single inheritance's limits — combine several with `trait-sum`, then apply:

```racket
(require racket/trait)
(define t-label (trait (define/public (label) (string-append "<" (send this draw) ">"))))
(define labelled% ((trait->mixin t-label) square%))
```

Use a mixin when you extend one class at a time; use traits when you need to
mix several independent method sets and resolve conflicts explicitly
(`trait-exclude`, `trait-alias`).

## Contracts

`racket/contract` interoperates with objects (see [[contracts]]):

- **`(is-a?/c iface-or-class)`** — the everyday boundary contract: "an object
  that implements this interface (or extends this class)". Demand the
  interface, not a concrete class.
- **`(object/c [method (->m dom ... rng)] …)`** — constrain specific methods
  of an object. `->m` is the method arrow (no explicit `this`); `->*m` adds
  optional arguments.
- **`(class/c [method (->m …)] …)`** — constrain a class; `instanceof/c`
  applies a class contract to its instances.

```racket
(provide (contract-out [draw-all (-> (listof (is-a?/c drawable<%>)) void?)]))
```

## Rules that prevent rework

- **Always call `super-new`.** Every class body must initialize its
  superclass exactly once; omitting it is the most common construction error.
- **Prefer interfaces + mixins to deep hierarchies.** Single inheritance is
  rigid; an `interface` plus mixins/traits gives open extension without
  editing existing classes — the composition-over-inheritance tenet.
- **`abstract` for required methods.** Declare the contract a subclass must
  fill instead of a stub that returns a wrong value; calling it unimplemented
  errors clearly.
- **Augment vs override is a design choice, not a detail.** `pubment`/`inner`
  keeps the superclass in control (a hook); `override`/`super` hands control
  to the subclass. Pick deliberately and declare the method accordingly.
- **Contract with `is-a?/c` at boundaries.** Accept any implementer of the
  interface so new classes and mixins keep working ([[contracts]]).
- **Encapsulate state.** Keep `field`s private and expose behavior through
  methods; objects earn their place by hiding mutable state behind a stable
  interface.
