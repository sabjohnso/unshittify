# Sequences / for Reference — exact grammars

Companion to SKILL.md. Source: docs.racket-lang.org/reference/ "Iterations
and Comprehensions" and "Sequences". Checked against Racket v9.1 [cs].

## The for family

```racket
(for         (for-clause ...) body ...+)        ; -> void
(for/list    (for-clause ...) body ...+)
(for/vector [#:length n #:fill v] (for-clause ...) body ...+)
(for/hash    (for-clause ...) body ...+)        ; body -> (values key val)
(for/hasheq (...) ...)  (for/hasheqv (...) ...)
(for/and  ...)  (for/or ...)                    ; short-circuiting
(for/sum  ...)  (for/product ...)
(for/first ...) (for/last ...)
(for/string ...) (for/bytes ...)
(for/lists (id ...) (for-clause ...) body ...+) ; body -> (values ...)
(for/fold  ([accum-id init-expr] ... maybe-result) (for-clause ...) body ...+)
(for/foldr ([accum-id init-expr] ... maybe-result-or-delay) (for-clause ...) body ...+)
  maybe-result = #:result result-expr
;; every form above has a for*/... variant that nests the clauses.
(for/fold/derived orig-stx ...)                 ; for building custom comprehensions
(for*/fold/derived ...)
```

## for-clause grammar

```racket
for-clause =
    [id seq-expr]                    ; bind id to each element
  | [(id ...) seq-expr]              ; bind multiple values per element
  | [id ...   seq-expr]              ; shorthand
  | #:when guard-expr                ; keep iterating only when true (nests)
  | #:unless guard-expr
  | #:break guard-expr               ; stop, excluding this element
  | #:final guard-expr               ; run this element, then stop
  | #:do [body ...]                  ; side effects between clauses

;; Multiple [id seq] clauses before a #:when iterate in PARALLEL (zip,
;; stopping at the shortest). In for* they nest. A binding clause after a
;; #:when/#:unless always nests under it.
```

## Sequence constructors

```racket
(in-range end)  (in-range start end [step])
(in-inclusive-range start end [step])
(in-naturals [start])                  ; 0,1,2,... (infinite)
(in-list lst)  (in-mlist mlst)
(in-vector v [start stop step])  (in-string s ...)  (in-bytes bs ...)
(in-hash h)  (in-hash-keys h)  (in-hash-values h)  (in-hash-pairs h)
(in-immutable-hash h) ...
(in-set st)                            ; require racket/set
(in-port [read-proc port])  (in-lines [port mode])  (in-bytes-lines ...)
(in-input-port-bytes p)  (in-input-port-chars p)
(in-cycle seq ...)                     ; repeat forever
(in-value v)                           ; single-element sequence
(in-indexed seq)                       ; -> (values elem index)
(in-sequences seq ...)                 ; concatenate
(in-parallel seq ...)                  ; -> (values elem-from-each ...)
(in-values-sequence seq) (in-values*-sequence seq)
(in-producer producer [stop arg ...])  ; from a thunk; require racket/sequence
(stop-before seq pred)  (stop-after seq pred)
```

Constructors used in a `for` clause head are recognized specially and
compile to tight loops. Used elsewhere they produce ordinary sequence values.

## racket/sequence operations

```racket
(require racket/sequence)
(sequence? v) -> boolean?
(sequence->list seq) -> list?
(sequence-length seq)  (sequence-ref seq i)  (sequence-tail seq i)
(sequence-append seq ...)  (sequence-map f seq)  (sequence-andmap / -ormap f seq)
(sequence-filter pred seq)  (sequence-add-between seq v)
(sequence-fold proc init seq)  (sequence-count pred seq)  (sequence-for-each f seq)
(in-slice len seq)                     ; sequence of length-len subsequences
empty-sequence                         ; the zero-element sequence
(sequence-generate seq)  -> (values more? next)   ; external iteration
(sequence-generate* seq) -> (values vals next)
```

## Defining sequences

```racket
;; (1) struct property
#:property prop:sequence (lambda (self) sequence-or-thunk)

;; (2) general constructor — the thunk returns the position protocol:
(make-do-sequence
 (lambda ()
   (values pos->element        ; (-> pos any) — current element(s)
           next-pos            ; (-> pos pos)  — advance
           init-pos            ; the starting position
           continue-with-pos?  ; (or/c (-> pos any/c) #f) — check before element
           continue-with-val?  ; (or/c (-> elem any/c) #f) — check after element
           continue-after?)))  ; (or/c (-> pos elem any/c) #f) — check before next
   ; any predicate may be #f to skip that test. A newer keyword form,
   ; (make-do-sequence thunk #:pos->element ...), also exists.

;; (3) inlinable in-X macro
(define-sequence-syntax id
  expr-transformer-thunk          ; (-> syntax) : the value/fallback form
  clause-transformer)             ; (-> clause-stx clause-stx) : inline expansion
  ; clause-transformer rewrites  [(id ...) (in-foo arg ...)]  into a :do-in clause.

(:do-in ([(outer-id ...) outer-expr] ...)   ; bound once, outside the loop
        outer-check                          ; expr run once before looping
        ([loop-id loop-expr] ...)            ; loop state, threaded each step
        pos-guard                            ; continue? (pre-body)
        ([(inner-id ...) inner-expr] ...)    ; per-iteration bindings (the elements)
        pre-guard                            ; continue? after inner binds, pre-body
        post-guard                           ; continue? post-body
        (loop-arg ...))                      ; next values for loop-ids
```

## Generators (require racket/generator)

```racket
(in-generator [#:arity k] body ...+)   ; body uses (yield v ...); a sequence
(generator (arg ...) body ...+)        ; a resumable procedure; (yield v) inside
(yield v ...) -> any                    ; suspend, return v to the caller
(sequence->generator seq)  (sequence->repeated-generator seq)
```
