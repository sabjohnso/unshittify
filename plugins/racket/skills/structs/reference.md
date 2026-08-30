# Struct Reference — exact grammar and options

Companion to SKILL.md. Source: docs.racket-lang.org/reference/define-struct.html
and racket/struct. Checked against Racket v9.1 [cs].

## struct form

```racket
(struct id maybe-super (field ...) struct-option ...)
  maybe-super = <nothing> | super-id
  field = field-id
        | [field-id field-option ...]
  field-option = #:mutable | #:auto

  struct-option =
      #:mutable                 ; all fields mutable; adds set-id-field!
    | #:transparent             ; structural equal?, readable print, full reflection
    | #:prefab                  ; prefab: read/write-able as #s(id v ...), structural =
    | #:authentic               ; disallow chaperones/impersonators (faster, stricter)
    | #:sealed                  ; no subtypes may extend this struct
    | #:guard guard-expr        ; (-> field-val ... name (values field-val ...)) or raise
    | #:constructor-name ctor-id
    | #:extra-constructor-name ctor-id
    | #:name id                 ; the transformer-binding name
    | #:extra-name id
    | #:reflection-name expr    ; the name used in printing/errors
    | #:inspector expr          ; #f = transparent; (make-inspector) = controlled
    | #:property prop-expr val-expr
    | #:methods gen-id [defn ...]
    | #:omit-define-syntaxes    ; don't bind the transformer (struct-info) name
    | #:omit-define-values      ; don't bind ctor/pred/accessors
    | #:super super-expr        ; dynamic supertype (alternative to maybe-super)
```

Auto fields (`#:auto`) take `#:auto-value` (default `#f`) and must follow all
non-auto fields. `#:transparent` is shorthand for `#:inspector #f`.

## Generated bindings

For `(struct posn (x y) ...)`:

```
posn            constructor       (posn x-val y-val)
posn?           predicate         (posn? v)
posn-x  posn-y  accessors         (posn-x p)
set-posn-x! ...  setters          only when the field is mutable
posn            transformer binding usable as a super-id and by struct-copy,
                struct-out, match's (struct posn ...), and contract-out's struct
```

`#:constructor-name` replaces the constructor binding; `#:extra-constructor-name`
adds a second one (both build the same struct).

## Construction-time guard

```racket
#:guard (lambda (field-val ... type-name) (values field-val ...))
  ; called before the instance exists; receives every field value (super
  ; fields included for subtypes) plus the struct's name symbol.
  ; Return the same number of (possibly coerced) values, or raise.
  ; A subtype guard runs AFTER the supertype guard, seeing guarded supers.
```

## Operations

```racket
(struct-copy struct-id struct-expr [field-id expr] ... )   ; functional update
   ; field-id are the plain field names; produces a new instance.
(struct->vector v [opaque-default]) -> vector?             ; #(struct:id field ...)
(struct? v) -> boolean?
(prefab-struct-key v) -> (or/c prefab-key? #f)
(make-prefab-struct key field-val ...) -> struct?
(struct-info v) -> (values (or/c struct-type? #f) boolean?) ; needs inspector access
(struct-type-info st) -> (values name init-cnt auto-cnt ref set! immutables super skipped?)
```

## Generic interfaces and properties (racket/struct, racket/generic)

```racket
;; gen:custom-write — printing
#:methods gen:custom-write
  [(define (write-proc self out mode) ....)]   ; mode: #t write, #f display, 0/1 print
;; helper:
(make-constructor-style-printer get-name get-contents) -> write-proc
   ; prints  #<name: c ...>  in write/display,  (name c ...)  in print mode.
(struct->list v) -> list?                      ; the other racket/struct export

;; gen:equal+hash — value equality (for opaque structs); all three required
#:methods gen:equal+hash
  [(define (equal-proc a b recur) ....)        ; -> boolean?
   (define (hash-proc  a recur) ....)          ; -> exact-integer?
   (define (hash2-proc a recur) ....)]         ; -> exact-integer?

;; gen:equal-mode+hash — the two-method alternative; mode is #t under equal?,
;; #f under equal-always?
#:methods gen:equal-mode+hash
  [(define (equal-mode-proc a b recur mode) ....)   ; -> boolean?
   (define (hash-mode-proc  a recur mode) ....)]    ; -> exact-integer?

;; applicable struct
#:property prop:procedure proc-or-field-index
   ; proc: (lambda (self arg ...) ....);  or an integer field holding a procedure

;; other common props (all in racket/base except prop:dict, from racket/dict)
prop:custom-write  prop:equal+hash  prop:evt  prop:sequence  prop:dict
```

`#:methods gen:foo [defn ...]` implements the generic interface `gen:foo`
(from `racket/generic`); the method bodies may refer to the struct's
accessors directly.

## Legacy

```racket
(define-struct id (field ...) option ...)   ; older form; constructor is make-id
                                            ; and a subtype is (define-struct (sub id) ...).
                                            ; Same options as struct — fields are
                                            ; immutable unless #:mutable. Prefer struct.
(struct-out id)                             ; provide constructor/pred/accessors together
```
