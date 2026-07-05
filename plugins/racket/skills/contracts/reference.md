# Contract Reference — exact signatures and grammars

Companion to SKILL.md. Source: docs.racket-lang.org/reference/contracts.html.
Checked against Racket v9.1 [cs].

## Attaching contracts

```racket
(provide (contract-out p-c-item ...))
  p-c-item =
      [id contract-expr]
    | [rename orig-id export-id contract-expr]
    | [struct struct-id ([field contract-expr] ...) struct-option ...]
    | [struct (struct-id parent-struct-id) ([field contract-expr] ...)]
    | [#:exists id-or-ids] | [#:∃ ...] | [#:forall ...]
  ; checks each export at the module boundary; internal uses are unchecked.

(define/contract id contract-expr body)            ; or (define/contract (head . args) ...)
  ; attaches a contract to a local definition; re-checks on every call,
  ; including self-recursion (boundary is the definition itself).

(with-contract blame-id ([id contract-expr] ...) body ...+)   ; region contract
(invariant-assertion contract-expr expr)                      ; one-shot check
(contract contract-expr val pos-blame neg-blame [src loc])    ; apply by hand
```

## Function contracts

```racket
(-> dom-contract ... range-contract)
(-> dom-contract ... any)                  ; range unchecked, any # of values
   ; keywords allowed inline: (-> string? #:k boolean? string?)

(->* (mandatory-dom ...)
     (optional-dom ...)                    ; may be omitted entirely
     [#:rest rest-contract]                ; tail of remaining args
     [#:pre pre-cond-expr]
     range)
   ; mandatory/optional include keyword pairs: (->* (string?) (#:loud? boolean?) string?)
   ; range is one contract, (values c ...), or any

(->i (mandatory-dependent-dom ...)
     (optional-dependent-dom ...)
     [#:rest (id (dep-id ...) rest-contract-expr)]
     [#:pre (dep-id ...) pre-cond-expr ...]
     dependent-range
     [#:post (dep-id ...) post-cond-expr ...])
   mandatory-dependent-dom =
       [id contract-expr]                       ; independent
     | [id (dep-id ...) contract-expr]          ; depends on dep-ids
     | [id keyword contract-expr]
     | [id keyword (dep-id ...) contract-expr]
   dependent-range =
       any
     | [_ contract-expr] | [_ (dep-id ...) contract-expr]
     | (values [id contract-expr] ...) | [id (dep-id ...) contract-expr]
   ; the (dep-id ...) list names the args/results this clause reads.

(case-> (-> dom ... range) ...)            ; one binding, several arities
(unconstrained-domain-> range-contract ...)
(->d ...)   ; DEPRECATED — use ->i
```

## Value, numeric, and boolean combinators

```racket
any/c   none/c   any                      ; any = range only, multi-value ok
(or/c c ...)   (and/c c ...)   (not/c c)
(one-of/c v ...)   (symbols sym ...)   (literal datum)
(=/c n) (</c n) (>/c n) (<=/c n) (>=/c n)
(between/c lo hi)   (integer-in lo hi)   (real-in lo hi)   (char-in a b)
exact-integer?  exact-nonnegative-integer?  natural-number/c
(string-len/c n)   (false/c)   (printable/c)
(flat-named-contract name flat-contract)  ; rename for nicer messages
```

## Data-structure combinators

```racket
(listof c)  (non-empty-listof c)  (list*of c)  (cons/c a d)  (list/c c ...)
(vectorof c [#:flat? bool])  (vector/c c ...)
(hash/c key/c val/c [#:immutable bool #:flat? bool])
(box/c c)  (set/c c)  (sequence/c c ...)  (stream/c c)
(promise/c c)  (parameter/c in/c [out/c])  (struct/c struct-id field-c ...)
(struct/dc struct-id [field maybe-deps contract-or-dep] ...)  ; dependent fields
(syntax/c c)   (hash/dc ...)
```

## Higher-order, polymorphic, and lazy

```racket
(parametric->/c (x ...) contract-expr)     ; sealed type variables
(->* ...) (->i ...)                        ; higher-order: wrap the function
(recursive-contract contract-expr [type])  ; type: #:flat #:chaperone #:impersonator
   ; needed for self-referential contracts; #:flat when it stays flat
(opt/c contract-expr)                      ; optimize a frequently-applied contract
(rename-contract c name)
(if/c predicate then/c else/c)
```

## Predicates and introspection

```racket
(contract? v)            ; any contract, including higher-order
(flat-contract? v)       ; checkable with a single predicate, no wrapping
(chaperone-contract? v)  (impersonator-contract? v)
(contract-name c)        ; the datum shown in messages
(value-contract v)       ; the contract guarding v, or #f
(contract-first-order-passes? c v)
(has-contract? v)  (has-blame? v)
```

## Blame

Every boundary contract has a **positive party** (made the promise — the
`provide` side) and a **negative party** (the caller). A domain (argument)
violation blames the negative party; a range (result) violation blames the
positive party. `->i`/`->*` `#:pre` failures blame the caller; `#:post`
failures blame the provider. Messages report `contract from:` (where the
contract was attached) and `blaming:` (the party at fault); the
`(assuming the contract is correct)` line is a reminder that a wrong
*contract* can misdirect blame.
