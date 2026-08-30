# rackcheck Reference — exact signatures

Companion to SKILL.md. Source: the rackcheck-lib package
(docs.racket-lang.org/rackcheck/) read against the installed source.
Checked against Racket v9.1 [cs].

## Properties

```racket
(property maybe-name ([id gen-expr] ...) body ...+)
   maybe-name = <nothing> | name-id | #:name name-expr
   ; binds each id to a value from its generator; body's non-#f value = pass.
   ; Produces a `prop` value (property? is the predicate, property-name the name).

(define-property name ([id gen-expr] ...) body ...+)
   ; = (define name (property name ([id gen-expr] ...) body ...))
```

## Running properties (rackunit integration)

```racket
(require rackcheck rackunit)
(check-property maybe-config prop)        ; a rackunit check (define-check)
   ; maybe-config optional; defaults to (make-config). On failure the check
   ; reports name, seed, the failing args, and the shrunk-smallest args.

(make-config [#:seed seed]                ; integer in [0, 2^31-1]; fixes the RNG
             [#:tests n]                  ; exact-positive-integer?, default 100
             [#:size size-fn]             ; (-> exact-positive-integer? exact-nonnegative-integer?)
             [#:deadline abs-ms])         ; (>=/c 0) — an ABSOLUTE time, not a
                                          ;   duration; default is
                                          ;   (+ (current-inexact-milliseconds) 60000)
   -> config?

(label! str-or-#f) -> void?               ; classify the current case; #f = skip
```

## Generators — primitives (require rackcheck)

```racket
gen:natural                               ; 0,1,2,... (grows with size)
(gen:integer-in lo hi)                    ; inclusive integer range
gen:real
gen:boolean
gen:char                                  ; any char
gen:char-letter  gen:char-digit  gen:char-alphanumeric
(gen:char-in lo hi)                       ; lo/hi are integer code points, not chars
gen:unicode  gen:unicode-letter  gen:unicode-mark  gen:unicode-number
gen:unicode-punctuation  gen:unicode-separator  gen:unicode-symbol
(gen:string [char-gen])                   ; string from a char generator (default gen:char)
(gen:symbol [char-gen])                   ; a PROCEDURE: bare gen:symbol is not a gen?
(gen:bytes [byte-gen])                    ; default (gen:integer-in 0 255)
```

Everything on this list that is written applied — `gen:integer-in`,
`gen:char-in`, `gen:string`, `gen:symbol`, `gen:bytes` — is a procedure and
must be called; everything written bare is already a `gen?` value. `sample`
and `property` reject a procedure with `expected: gen?`.

## Generators — collections

```racket
(gen:list elem-gen [#:max-length n])
(gen:vector elem-gen [#:max-length n])
(gen:hash key val-gen key val-gen ...)    ; also gen:hasheq, gen:hasheqv
   ; ALTERNATING literal keys and generators, an even number of arguments:
   ;   (gen:hash 'a gen:natural 'b gen:boolean)  =>  #hash((a . 0) (b . #t))
   ; The keys are fixed; only the values are generated. An odd argument count
   ; raises "expected: an even number of arguments"; a generator in a key
   ; position raises nothing and keys the hash by the generator itself.
(gen:tuple gen ...)                       ; fixed-length list, one elem per gen
```

## Generator combinators

```racket
(gen:const v)                             ; always v (no shrinking)
(gen:map g proc)                          ; transform each value
(gen:bind g proc)                         ; proc : value -> next generator
(gen:let ([id g] ...) body ...+)          ; do-notation over gen:bind; body may
                                          ;   return a value or a generator
(gen:choice g ...)                        ; uniformly choose among generators
(gen:one-of lst)                          ; choose a value from a list
(gen:frequency (list (cons weight g) ...))      ; weighted choice
(gen:filter g pred [max-attempts])        ; retry until pred holds (default 1000)
(gen:sized (lambda (size) g))             ; build a generator from the size param
(gen:resize g size)                       ; run g at a fixed size
(gen:scale g (lambda (size) size*))       ; transform the size param
(gen:no-shrink g)                         ; produce values but never shrink them
(gen:with-shrink g shrink-fn)
(gen:delay g)                             ; macro: delay evaluation (recursive generators)
```

A `gen:filter` that cannot satisfy its predicate within `max-attempts`
raises `exn:fail:gen:exhausted` (predicate `exn:fail:gen:exhausted?`).

## Inspecting generators

```racket
(sample g [n] [rng]) -> (listof any)      ; n values (default 10) at growing sizes
(shrink g size [rng] [#:limit l] [#:max-depth d])  ; explore the shrink tree
(gen? v) -> boolean?
```

## Notes

- A generator is a struct wrapping `(-> rng size shrink-tree)`. `make-gen` is
  exported from `rackcheck` itself; `rackcheck/shrink-tree` adds the
  shrink-tree API (`shrink-tree`, `make-shrink-tree`, `shrink-tree-map`,
  `shrink-proc/c`) that a custom generator's procedure must return.
- `gen:map`, `gen:bind`, and `gen:let` preserve shrinking; values built
  through them shrink as their inputs shrink. `gen:const` and `gen:no-shrink`
  do not shrink.
- The size parameter passed to generators grows across a run (`sample` uses
  `(expt i 2)`), bounding magnitude and collection length.
