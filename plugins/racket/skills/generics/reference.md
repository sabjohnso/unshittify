# racket/generic Reference — exact grammar

Companion to SKILL.md. Source: docs.racket-lang.org/reference/struct-generics.html.
Checked against Racket v9.1 [cs].

## define-generics

```racket
(define-generics id            ; id becomes gen:id, plus id? and the methods
  method-defn ...              ; each: (method-id formal ... . maybe-rest)
  generics-opt ...)

  method-defn  = (method-id arg-id ...+)              ; one arg is the dispatch arg
               | (method-id arg-id ... [opt-id] ...)  ; optional args in brackets
               | (method-id arg-id ... . rest-id)     ; rest arg
   ; exactly one arg position must be the generic id (the dispatched argument),
   ; and it must be the same position-name across methods.

  generics-opt =
      #:defaults      ([type-pred method-impl ...] ...)
    | #:fast-defaults ([type-pred method-impl ...] ...)   ; checked before dispatch
    | #:fallbacks     [method-impl ...]                   ; used when a method is absent
    | #:defined-predicate  pred-id        ; (pred-id instance 'method) -> boolean?
    | #:defined-table      table-id       ; (table-id instance) -> hash of method->bool
    | #:requires      (method-id ...)     ; methods every implementation must define
    | #:derive-property prop-expr prop-value-expr   ; attach a struct type property
```

`define-generics` generates:

```
gen:id        ; for use with #:methods gen:id [ ... ] on a struct
id?           ; predicate: #t for any value implementing the interface
method-id ... ; the generic methods, dispatching on their generic-id argument
```

`#:derive-property` may be repeated; each adds one struct type property whose
value is computed (often a lambda closing over the generic methods).

## Implementing (in a struct)

```racket
(struct name (field ...)
  #:methods gen:id
  [(define (method-id arg ...) body ...)        ; per-method implementation
   (define/generic local-id method-id) ...])    ; capture siblings to call them
```

`#:methods gen:id [defn ...]` is a `struct` option (see the structs skill).
The method bodies may reference the struct's accessors directly.

## define/generic

```racket
(define/generic local-id method-id)
   ; valid only inside a #:methods or #:fallbacks body. Binds local-id to the
   ; GENERIC method-id so it dispatches when called. A bare method-id inside
   ; a method body does not dispatch and raises a "not implemented" error.
```

## Support checks and errors

```racket
;; via #:defined-predicate pred-id :
(pred-id instance 'method-id) -> boolean?
;; via #:defined-table table-id :
(table-id instance) -> (hash/c symbol? boolean?)

(exn:fail:support? v) -> boolean?         ; raised by an unimplemented method
(raise-support-error name v) -> any       ; raise such an error manually
   name : the method name (symbol/string);  v : the offending value
```

## Contracts

```racket
(generic-instance/c gen:id [method-id method-contract] ...)
   ; a contract for values that implement gen:id; optionally constrain
   ; individual methods. gen:id must be a literal identifier, not an expression.
```

## Relationship to struct type properties

`define-generics` is built on `make-struct-type-property`: `gen:id` is a
struct type property holding the method table, and `#:methods` installs it.
For a single ad-hoc capability (not a named method set), a raw
`make-struct-type-property` + `#:property` is lighter; reach for
`define-generics` when you want a named interface, a predicate, dispatched
methods, defaults, and fallbacks together.
