---
description: Object-oriented programs in Racket with racket/class. Covers the definition of a class over object%, the creation of an object with new or make-object and a message with send, inheritance (super, override, the pubment, augment, and inner hole), interfaces (interface, is-a?), composition with mixins and traits, abstract methods, and class and object contracts (class/c, object/c, is-a?/c, ->m). Use when you write stateful objects, when you work with racket/gui, or when you extend a class through mixins and interfaces.
allowed-tools: Read, Grep, Glob
---

# Object-oriented Racket with racket/class

`racket/class` gives classes, objects, single inheritance, interfaces, and
composition through mixins and traits. A class and an object are first-class
values. A class is an expression, `new` builds an object, and `send` calls a
method. `racket/gui` is built on this model.

For the exact grammar of `class`, the `define/` method family, and the
interface and composition forms, read `reference.md` in this skill
directory.

Use `racket/class` when you need **stateful objects with behavior**, or when
you must work with a class-based library (notably `racket/gui`). For plain
data with operations, a design with [structs](../structs/SKILL.md) and
[generics](../generics/SKILL.md) is usually simpler and more functional. When
you use classes, prefer interfaces and composition (mixins and traits) to a
deep inheritance hierarchy. That gives open extension with no edit of the
existing classes.

## Define a class

```racket
(require racket/class)

(define animal%
  (class object%                       ; object% is the root class
    (init-field name [legs 4])         ; constructor arguments that become fields
    (field [steps 0])                  ; an internal field, not a constructor argument
    (super-new)                        ; NECESSARY: initialize the superclass
    (define/public (describe) (format "~a (~a legs)" name legs))
    (define/public (walk! n) (set! steps (+ steps n)) steps)))
```

- By convention, a class name ends in `%` and an interface name ends in `<%>`.
- **`super-new` (or `super-make-object`) must run** in every class body.
  Otherwise the construction fails.
- `init` is a constructor argument that the object does *not* store.
  `init-field` is one that becomes a field. `field` is internal state. A
  bracket form gives a default: `[legs 4]`.
- `this` refers to the current object. `define/public` exposes a method.

## Create objects and send messages

```racket
(define a (new animal% [name "cat"]))          ; keyword init arguments
(make-object animal% "mouse" 4)                ; by position
(instantiate animal% () [name "ant"] [legs 6]) ; by position, then by keyword

(send a describe)                              ; call a method
(send a walk! 3)
(send* a (walk! 1) (walk! 2))                  ; several sends to one object
(dynamic-send a 'describe)                     ; the method name is computed at run time
(get-field steps a)                            ; read a field; set-field! writes it
```

## Inheritance

A subclass is a `class` whose superclass expression is another class. Use
`super` to call the overridden method. Use `inherit` or `inherit-field` to
use a superclass member directly:

```racket
(define dog%
  (class animal%
    (super-new [legs 4])
    (inherit-field name)
    (define/override (describe) (format "~a the dog" (super describe))))) ; extend
```

- **`abstract`** declares a method with no body. A subclass must override it.
  A call to it on a class that does not override it gives an error:

  ```racket
  (class object% (super-new) (abstract area)
    (define/public (describe) (format "area=~a" (send this area))))
  ```

- **Augmentation** is the inverse of an override. A superclass leaves an
  extension *hole* with `inner`, and a subclass fills it with `augment`. It
  does not replace the method. Declare the method with `pubment` to make it
  augmentable:

  ```racket
  (class object% (super-new)
    (define/pubment (greet) (string-append "hi" (inner "" greet))))
  ;; subclass: (define/augment (greet) "!")  =>  "hi!"
  ```

  An override lets a subclass take control. An augment keeps the superclass
  in control, and the superclass calls down into a hook of the subclass.

## Interfaces

An `interface` names a set of method names. `class*` declares the interfaces
that a class implements. `is-a?` and the related predicates test the
membership. Write the program against the interface, not against the
concrete class:

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

A mixin is a function from a class to a class. It adds behavior to *every*
class, with no subclass of a fixed parent. This is the idiomatic open
extension in `racket/class`:

```racket
(define (logging-mixin %)
  (class % (super-new)
    (define/public (log-draw) (format "LOG: ~a" (send this draw)))))

(define logged-square% (logging-mixin square%))
```

The `mixin` form also states the interfaces that the argument class must
implement and the interfaces that the result gives:

```racket
(mixin (drawable<%>) () (super-new)
  (define/public (twice) (string-append (send this draw) (send this draw))))
```

### Traits

A trait (`racket/trait`) is a reusable, composable set of methods. Traits go
around the limits of single inheritance. Combine several with `trait-sum`,
then apply the result:

```racket
(require racket/trait)
(define t-label (trait (define/public (label) (string-append "<" (send this draw) ">"))))
(define labelled% ((trait->mixin t-label) square%))
```

Use a mixin when you extend one class at a time. Use traits when you must
mix several independent method sets and resolve the conflicts explicitly
(`trait-exclude`, `trait-alias`).

## Contracts

`racket/contract` works with objects (see
[contracts](../contracts/SKILL.md)):

- **`(is-a?/c iface-or-class)`** is the usual boundary contract: "an object
  that implements this interface (or extends this class)". Demand the
  interface, not a concrete class.
- **`(object/c [method (->m dom ... rng)] …)`** constrains specific methods
  of an object. `->m` is the method arrow (with no explicit `this`). `->*m`
  adds optional arguments.
- **`(class/c [method (->m …)] …)`** constrains a class. `instanceof/c`
  applies a class contract to the instances of the class.

```racket
(provide (contract-out [draw-all (-> (listof (is-a?/c drawable<%>)) void?)]))
```

## Rules that prevent rework

- **Always call `super-new`.** Every class body must initialize its
  superclass exactly once. A body without it is a common construction error.
- **Prefer interfaces plus mixins to a deep hierarchy.** Single inheritance
  is rigid. An `interface` plus mixins or traits gives open extension with no
  edit of the existing classes. That is the composition-over-inheritance
  rule.
- **Use `abstract` for a required method.** Declare the contract that a
  subclass must fill. Do not write a stub that returns a wrong value. A call
  to an abstract method with no implementation gives a clear error.
- **Augment or override is a design choice, not a detail.** `pubment` and
  `inner` keep the superclass in control (a hook). `override` and `super`
  give the control to the subclass. Pick on purpose, and declare the method
  accordingly.
- **Put an `is-a?/c` contract at each boundary.** Accept every implementer of
  the interface, so new classes and mixins continue to work
  ([contracts](../contracts/SKILL.md)).
- **Encapsulate the state.** Keep each `field` private, and expose the
  behavior through methods. An object earns its place when it hides mutable
  state behind a stable interface.
