# rackcheck Reference — exact signatures

This file accompanies SKILL.md. The source is the rackcheck-lib package
(docs.racket-lang.org/rackcheck/). The text was compared with the installed source.
The text was checked with Racket v9.1 [cs].

## Properties

```racket
(property maybe-name ([id gen-expr] ...) body ...+)
   maybe-name = <nothing> | name-id | #:name name-expr
   ; Binds each id to a value from its generator. A body value other than #f = pass.
   ; Produces a `prop` value (property? is the predicate, property-name gives the name).

(define-property name ([id gen-expr] ...) body ...+)
   ; = (define name (property name ([id gen-expr] ...) body ...))
```

## Running properties (rackunit integration)

```racket
(require rackcheck rackunit)
(check-property maybe-config prop)        ; a rackunit check (define-check)
   ; maybe-config is optional. The default is (make-config). If the property fails,
   ; the check reports the name, the seed, the failing args, and the smallest shrunk args.

(make-config [#:seed seed]                ; integer in [0, 2^31-1]; sets the RNG seed
             [#:tests n]                  ; exact-positive-integer?, default 100
             [#:size size-fn]             ; (-> exact-positive-integer? exact-nonnegative-integer?)
             [#:deadline abs-ms])         ; (>=/c 0). It is an ABSOLUTE time, not a
                                          ;   duration. The default is
                                          ;   (+ (current-inexact-milliseconds) 60000)
   -> config?

(label! str-or-#f) -> void?               ; gives a class to the current case; #f = skip
```

## Generators — primitives (require rackcheck)

```racket
gen:natural                               ; 0,1,2,... (grows with the size)
(gen:integer-in lo hi)                    ; inclusive integer range
gen:real
gen:boolean
gen:char                                  ; any char
gen:char-letter  gen:char-digit  gen:char-alphanumeric
(gen:char-in lo hi)                       ; lo and hi are integer code points, not chars
gen:unicode  gen:unicode-letter  gen:unicode-mark  gen:unicode-number
gen:unicode-punctuation  gen:unicode-separator  gen:unicode-symbol
(gen:string [char-gen])                   ; string from a char generator (default gen:char)
(gen:symbol [char-gen])                   ; a PROCEDURE. The bare gen:symbol is not a gen?
(gen:bytes [byte-gen])                    ; default (gen:integer-in 0 255)
```

Each name on this list that has arguments is a procedure. These names are
`gen:integer-in`, `gen:char-in`, `gen:string`, `gen:symbol`, and `gen:bytes`.
You must call them. Each name without arguments is already a `gen?` value.
`sample` and `property` reject a procedure and show `expected: gen?`.

## Generators — collections

```racket
(gen:list elem-gen [#:max-length n])
(gen:vector elem-gen [#:max-length n])
(gen:hash key val-gen key val-gen ...)    ; also gen:hasheq, gen:hasheqv
   ; The arguments ALTERNATE between literal keys and generators. The number of arguments is even:
   ;   (gen:hash 'a gen:natural 'b gen:boolean)  =>  #hash((a . 0) (b . #t))
   ; The keys are fixed. Only the values are generated. An odd number of arguments
   ; raises "expected: an even number of arguments". A generator in a key
   ; position raises no error. The hash then uses the generator itself as the key.
(gen:tuple gen ...)                       ; fixed-length list, one element per gen
```

## Generator combinators

```racket
(gen:const v)                             ; always v (no shrinking)
(gen:map g proc)                          ; change each value
(gen:bind g proc)                         ; proc : value -> next generator
(gen:let ([id g] ...) body ...+)          ; do-notation for gen:bind. The body can
                                          ;   return a value or a generator
(gen:choice g ...)                        ; choose one generator with equal probability
(gen:one-of lst)                          ; choose a value from a list
(gen:frequency (list (cons weight g) ...))      ; weighted choice
(gen:filter g pred [max-attempts])        ; try again until pred holds (default 1000)
(gen:sized (lambda (size) g))             ; make a generator from the size parameter
(gen:resize g size)                       ; run g at a fixed size
(gen:scale g (lambda (size) size*))       ; change the size parameter
(gen:no-shrink g)                         ; make values and never shrink them
(gen:with-shrink g shrink-fn)
(gen:delay g)                             ; macro: delays evaluation (for recursive generators)
```

If a `gen:filter` cannot satisfy its predicate within `max-attempts`,
it raises `exn:fail:gen:exhausted` (predicate `exn:fail:gen:exhausted?`).

## Inspecting generators

```racket
(sample g [n] [rng]) -> (listof any)      ; n values (default 10) at sizes that grow
(shrink g size [rng] [#:limit l] [#:max-depth d])  ; searches the shrink tree
(gen? v) -> boolean?
```

## Notes

- A generator is a struct that holds `(-> rng size shrink-tree)`. The
  `rackcheck` module exports `make-gen`. The `rackcheck/shrink-tree` module adds the
  shrink-tree API (`shrink-tree`, `make-shrink-tree`, `shrink-tree-map`,
  `shrink-proc/c`). The procedure of a custom generator must return a shrink tree.
- `gen:map`, `gen:bind`, and `gen:let` keep shrinking. A value made
  with them shrinks when its inputs shrink. `gen:const` and `gen:no-shrink`
  do not shrink.
- The size parameter that goes to generators grows during a run (`sample` uses
  `(expt i 2)`). The size limits the magnitude and the length of a collection.
