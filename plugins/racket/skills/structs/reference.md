# Struct Reference: exact grammar and options

This file accompanies SKILL.md. Sources: docs.racket-lang.org/reference/define-struct.html
and racket/struct. The content was checked against Racket v9.1 [cs].

## struct form

```racket
(struct id maybe-super (field ...) struct-option ...)
  maybe-super = <nothing> | super-id
  field = field-id
        | [field-id field-option ...]
  field-option = #:mutable | #:auto

  struct-option =
      #:mutable                 ; all fields are mutable; adds set-id-field!
    | #:transparent             ; structural equal?, readable print, full reflection
    | #:prefab                  ; prefab: read/write as #s(id v ...), structural =
    | #:authentic               ; no chaperones or impersonators (faster, stricter)
    | #:sealed                  ; no subtype can extend this struct
    | #:guard guard-expr        ; (-> field-val ... name (values field-val ...)) or raise
    | #:constructor-name ctor-id
    | #:extra-constructor-name ctor-id
    | #:name id                 ; the name of the transformer binding
    | #:extra-name id
    | #:reflection-name expr    ; the name that printing and errors use
    | #:inspector expr          ; #f = transparent; (make-inspector) = controlled
    | #:property prop-expr val-expr
    | #:methods gen-id [defn ...]
    | #:omit-define-syntaxes    ; do not bind the transformer (struct-info) name
    | #:omit-define-values      ; do not bind the constructor, predicate, or accessors
    | #:super super-expr        ; dynamic supertype (alternative to maybe-super)
```

Auto fields (`#:auto`) take `#:auto-value` (default `#f`). Auto fields must come after all
non-auto fields. `#:transparent` is a short form of `#:inspector #f`.

## Generated bindings

For `(struct posn (x y) ...)`:

```
posn            constructor       (posn x-val y-val)
posn?           predicate         (posn? v)
posn-x  posn-y  accessors         (posn-x p)
set-posn-x! ...  setters          only when the field is mutable
posn            transformer binding. Use it as a super-id and in struct-copy,
                struct-out, match's (struct posn ...), and contract-out's struct
```

`#:constructor-name` replaces the constructor binding. `#:extra-constructor-name`
adds a second constructor binding. Both constructors build the same struct.

## Construction-time guard

```racket
#:guard (lambda (field-val ... type-name) (values field-val ...))
  ; Racket calls the guard before the instance exists. It receives every field value
  ; (super fields too, for subtypes) and the name symbol of the struct.
  ; Return the same number of values (they can be coerced), or raise.
  ; A subtype guard runs AFTER the supertype guard and receives the guarded super values.
```

## Operations

```racket
(struct-copy struct-id struct-expr [field-id expr] ... )   ; functional update
   ; field-id are the plain field names. The form produces a new instance.
(struct->vector v [opaque-default]) -> vector?             ; #(struct:id field ...)
(struct? v) -> boolean?
(prefab-struct-key v) -> (or/c prefab-key? #f)
(make-prefab-struct key field-val ...) -> struct?
(struct-info v) -> (values (or/c struct-type? #f) boolean?) ; the caller needs inspector access
(struct-type-info st) -> (values name init-cnt auto-cnt ref set! immutables super skipped?)
```

## Generic interfaces and properties (racket/struct, racket/generic)

```racket
;; gen:custom-write: printing
#:methods gen:custom-write
  [(define (write-proc self out mode) ....)]   ; mode: #t write, #f display, 0/1 print
;; helper:
(make-constructor-style-printer get-name get-contents) -> write-proc
   ; It prints  #<name: c ...>  in write/display mode and  (name c ...)  in print mode.
(struct->list v) -> list?                      ; the other racket/struct export

;; gen:equal+hash: value equality (for opaque structs). All three methods are necessary.
#:methods gen:equal+hash
  [(define (equal-proc a b recur) ....)        ; -> boolean?
   (define (hash-proc  a recur) ....)          ; -> exact-integer?
   (define (hash2-proc a recur) ....)]         ; -> exact-integer?

;; gen:equal-mode+hash: the alternative with two methods. The mode is #t under equal?
;; and #f under equal-always?
#:methods gen:equal-mode+hash
  [(define (equal-mode-proc a b recur mode) ....)   ; -> boolean?
   (define (hash-mode-proc  a recur mode) ....)]    ; -> exact-integer?

;; applicable struct
#:property prop:procedure proc-or-field-index
   ; proc: (lambda (self arg ...) ....);  or an integer index of a field that holds a procedure

;; other common props (all in racket/base except prop:dict, from racket/dict)
prop:custom-write  prop:equal+hash  prop:evt  prop:sequence  prop:dict
```

`#:methods gen:foo [defn ...]` implements the generic interface `gen:foo`
(from `racket/generic`). The method bodies can use the accessors of the struct
directly.

## Legacy

```racket
(define-struct id (field ...) option ...)   ; older form. The constructor is make-id
                                            ; and a subtype is (define-struct (sub id) ...).
                                            ; The options are the same as for struct. Fields are
                                            ; immutable unless #:mutable. Use struct.
(struct-out id)                             ; provides the constructor, predicate, and accessors together
```
