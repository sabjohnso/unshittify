# racket/class Reference — exact grammar

Companion to SKILL.md. Source: docs.racket-lang.org/reference/objects.html
and racket/trait. Checked against Racket v9.1 [cs].

## class

```racket
(class superclass-expr class-clause ...)
(class* superclass-expr (interface-expr ...) class-clause ...)
object%                              ; the root superclass

class-clause =
    (inspect inspector-expr)
  | (init        init-decl ...)      ; ctor arg, not stored
  | (init-field  init-decl ...)      ; ctor arg, stored as a field
  | (init-rest id) | (init-rest)
  | (field       field-decl ...)     ; internal field
  | (inherit-field maybe-renamed ...)
  | (public      method-id ...)      ; declare (with separate define)
  | (pubment     method-id ...)      ; public + augmentable
  | (public-final method-id ...)
  | (override / overment / override-final / augment / augride / augment-final ...)
  | (private     method-id ...)
  | (abstract    method-id ...)      ; no body; subclass must implement
  | (inherit / inherit/super / inherit/inner  maybe-renamed ...)
  | (rename-super [internal external] ...)
  | (rename-inner [internal external] ...)
  | (begin expr ...) | method-definition | expr | ...

init-decl  = id | (renamed) | (id default-expr) | ((internal external) default-expr)
field-decl = (id init-expr) | ((internal external) init-expr)
maybe-renamed = id | (internal external)
```

## Method definitions (the define/ family)

```racket
(define/public    (id . formals) body ...)   ; new, externally callable
(define/pubment   (id . formals) body ...)   ; new + augmentable (use inner inside)
(define/public-final (id . formals) body ...)
(define/private   (id . formals) body ...)   ; internal only
(define/override  (id . formals) body ...)   ; replace a superclass method
(define/overment  (id . formals) body ...)   ; override + further augmentable
(define/override-final (id . formals) body ...)
(define/augment   (id . formals) body ...)   ; fill a superclass inner hole
(define/augride   (id . formals) body ...)   ; augment + further overridable
(define/augment-final (id . formals) body ...)
(abstract id ...)                            ; declared, must be overridden

;; inside method bodies:
(super  method-id arg ...)                   ; call the overridden method
(inner  default-expr method-id arg ...)      ; call a subclass augmentation, or default
this   this%                                 ; the object / its class
(super-new [id expr] ...)                    ; initialize superclass (REQUIRED)
(super-make-object pos-arg ...)  (super-instantiate (pos ...) [id expr] ...)
```

## Creating objects and sending

```racket
(new       class-expr [id expr] ...)                 ; by keyword
(make-object class-expr pos-arg ...)                 ; by position
(instantiate class-expr (pos-arg ...) [id expr] ...) ; positional + keyword

(send obj method-id arg ...)
(send obj method-id arg ... . rest-list)
(send* obj (method-id arg ...) ...)                  ; several sends, one object
(send+ obj (method-id arg ...) ...)                  ; fluent: each call's target is
                                                     ;   the PREVIOUS call's result
(send/apply obj method-id arg ... list-expr)
(send/keyword-apply obj method-id kws kw-args arg ... list)
(dynamic-send obj method-name-expr arg ...)          ; method chosen at runtime
(with-method ([local-id (obj method-id)] ...) body)  ; capture a method as a procedure

(get-field id obj)   (set-field! id obj expr)   (field-bound? id obj)
```

## Interfaces and predicates

```racket
(interface  (super-interface-expr ...) id ...)
(interface* (super-interface-expr ...) ([prop-expr val-expr] ...) id ...)

(is-a? v class-or-interface)         ; v is an instance / implements it
(implementation? class interface)    ; class implements interface
(subclass? class class)              ; first extends second
(object? v) (class? v) (interface? v)
(object-interface obj) -> interface? (class->interface class)
(method-in-interface? sym interface)
(object=? a b)  (object-or-false=? a b)
```

## Composition

```racket
(mixin (from-interface ...) (to-interface ...) class-clause ...)
   ; -> a function (class -> class); argument must implement the from-interfaces,
   ;    result implements the to-interfaces.

(require racket/trait)
(trait trait-clause ...)             ; a set of methods (define/public etc.)
(trait->mixin trait) -> (class -> class)
(trait-sum trait ...)                ; combine; errors on name clash
(trait-exclude trait method-id)      (trait-exclude-field trait id)
(trait-alias trait method-id new-id) (trait-rename trait old new)
(trait-rename-field trait old new)
```

## Contracts (racket/contract)

```racket
(is-a?/c class-or-interface)         ; object implementing/extending it — the common one
(implementation?/c interface)        ; a CLASS implementing the interface
(subclass?/c class)
(object/c  member-spec ...)          ; constrain an object's methods/fields
(class/c   member-spec ...)          ; constrain a class
(instanceof/c class-contract)        ; apply a class contract to instances
  member-spec = [method-id method-contract] | (field [id contract] ...) | ...
(->m   dom ... rng)                  ; method arrow (implicit this)
(->*m  (mandatory ...) (optional ...) rng)
(case->m (-> dom ... rng) ...)       ; cases use -> (not ->m)
(dynamic-object/c (method-id ...) (method-contract ...) (field-id ...) (field-contract ...))
```

`->m`/`->*m` omit the implicit `this` argument; otherwise they mirror
`->`/`->*` from the contracts skill.
