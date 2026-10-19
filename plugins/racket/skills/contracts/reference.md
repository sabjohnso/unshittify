# Contract Reference: exact signatures and grammars

This file accompanies `SKILL.md`. Source: docs.racket-lang.org/reference/contracts.html.
The author checked this file against Racket v9.1 [cs].

## Attaching contracts

```racket
(provide (contract-out p-c-item ...))
  p-c-item =
      [id contract-expr]
    | [rename orig-id export-id contract-expr]
    | [struct struct-id ([field contract-expr] ...) struct-option ...]
    | [struct (struct-id parent-struct-id) ([field contract-expr] ...)]
    | #:exists id-or-ids | #:∃ ... | #:forall ... | #:∀ ...
  ; struct-option is #:omit-constructor.
  ; The polymorphism keyword and its variables are two SEPARATE clauses.
  ; Do not put brackets around them: (contract-out #:exists T [make-t (-> T)]).
  ; The form [#:exists T] is a syntax error ("contract-out: expected identifier").
  ; contract-out checks each export at the module boundary.
  ; It does not check uses inside the module.

(define/contract id contract-expr body)            ; or (define/contract (head . args) ...)
  ; attaches a contract to a local definition. It checks the contract on every call,
  ; also on a self-recursive call (the boundary is the definition itself).

(with-contract blame-id ([id contract-expr] ...) body ...+)   ; region contract
(invariant-assertion contract-expr expr)                      ; one check
(contract contract-expr val pos-blame neg-blame [src loc])    ; apply the contract by hand
```

## Function contracts

```racket
(-> dom-contract ... range-contract)
(-> dom-contract ... any)                  ; no check of the range, any number of values
   ; keywords are possible inline: (-> string? #:k boolean? string?)

(->* (mandatory-dom ...)
     (optional-dom ...)                    ; can be omitted entirely
     [#:rest rest-contract]                ; the remaining arguments
     [#:pre pre-cond-expr]                 ; before the range
     range
     [#:post post-cond-expr])              ; AFTER the range
   ; mandatory and optional include keyword pairs: (->* (string?) (#:loud? boolean?) string?)
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
     | keyword [id contract-expr]               ; keyword OUTSIDE the brackets
     | keyword [id (dep-id ...) contract-expr]
   dependent-range =
       any
     | [_ contract-expr] | [_ (dep-id ...) contract-expr]
     | (values [id contract-expr] ...) | [id (dep-id ...) contract-expr]
   ; the (dep-id ...) list names the arguments and results that this clause reads.

(case-> (-> dom ... range) ...)            ; one binding, several arities
(unconstrained-domain-> range-contract ...)
(->d ...)   ; DEPRECATED. Use ->i
```

## Value, numeric, and boolean combinators

```racket
any/c   none/c   any                      ; any is for a range only, multiple values are permitted
(or/c c ...)   (and/c c ...)   (not/c c)
(one-of/c v ...)   (symbols sym ...)
'sym  42  "s"                             ; a quoted datum is a contract
(=/c n) (</c n) (>/c n) (<=/c n) (>=/c n)
(between/c lo hi)   (integer-in lo hi)   (real-in lo hi)   (char-in a b)
exact-integer?  exact-nonnegative-integer?  natural-number/c
(string-len/c n)   ; strings STRICTLY shorter than n
false/c   printable/c                     ; VALUES, not constructors. false/c is
                                          ;   #f, printable/c is a flat contract.
                                          ;   (false/c) gives "not a procedure".
                                          ;   (printable/c) gives an arity mismatch.
(flat-named-contract name flat-contract)  ; change the name to get clearer messages
```

## Data-structure combinators

```racket
(listof c)  (non-empty-listof c)  (list*of c)  (cons/c a d)  (list/c c ...)
(vectorof c [#:flat? bool])  (vector/c c ...)
(hash/c key/c val/c [#:immutable bool #:flat? bool])
(box/c c)
(promise/c c)  (parameter/c in/c [out/c])  (struct/c struct-id field-c ...)
(struct/dc struct-id [field maybe-deps contract-or-dep] ...)  ; dependent fields
(syntax/c c)   (hash/dc [key-id key-c] [val-id (key-id) val-c])
```

Three collection combinators are *not* in `racket/contract`. Require the
module of the collection: `(set/c c)` from `racket/set`, `(sequence/c c ...)`
from `racket/sequence`, `(stream/c c)` from `racket/stream`. In
`#lang racket`, all three are available.

## Higher-order, polymorphic, and lazy

```racket
(parametric->/c (x ...) contract-expr)     ; sealed type variables
(->* ...) (->i ...)                        ; higher-order: these wrap the function
(recursive-contract contract-expr [type])  ; type: #:flat #:chaperone #:impersonator
   ; necessary for self-referential contracts. Use #:flat when the contract stays flat
(opt/c contract-expr)                      ; makes a frequently applied contract faster
(rename-contract c name)
(if/c predicate then/c else/c)
```

## Predicates and introspection

```racket
(contract? v)            ; any contract, including higher-order
(flat-contract? v)       ; a single predicate can check it, no wrapper
(chaperone-contract? v)  (impersonator-contract? v)
(contract-name c)        ; the datum shown in messages
(value-contract v)       ; the contract guarding v, or #f
(contract-first-order-passes? c v)
(has-contract? v)  (has-blame? v)
```

## Blame

Every boundary contract has a **positive party** (the party that made the promise, the
`provide` side) and a **negative party** (the caller). A violation of the domain (argument)
blames the negative party. A violation of the range (result) blames the
positive party. A failure of `#:pre` in `->i` or `->*` blames the caller. A failure of `#:post`
blames the provider. Messages show `contract from:` (where the
contract was attached) and `blaming:` (the party at fault). The
line `(assuming the contract is correct)` is a reminder that a wrong
*contract* can cause wrong blame.
