---
description: Add Racket contracts with racket/contract. Covers function contracts (->, ->*, ->i, case->), contract-out on module exports, struct and data-structure contracts (listof, hash/c, struct/c, recursive-contract), combinators (or/c, and/c, between/c), and how to read a blame message. Use when you put a contract on a module boundary, when you specify argument or result constraints, when you debug a contract violation or a blame message, or when you choose between contract-out and define/contract.
allowed-tools: Read, Grep, Glob
---

# Racket contracts

A contract is a runtime agreement that the system checks when a value
crosses a boundary, usually the `provide` of a module. When the check fails,
the contract system raises an error that **blames** the party that broke the
agreement. The contract system is part of `#lang racket`. Under
`racket/base`, add `(require racket/contract)`. For the exact grammars and
the full combinator list, read `reference.md` in this skill directory.

## Where to attach a contract

Prefer **`contract-out` in `provide`** for an exported binding. The contract
sits exactly at the module boundary. So an internal call runs with no check,
and the blame names the right module:

```racket
#lang racket/base
(require racket/contract)

(struct account (owner balance) #:transparent)
(define (deposit a amt)
  (account (account-owner a) (+ (account-balance a) amt)))
(define (withdraw a amt)
  (account (account-owner a) (- (account-balance a) amt)))

(provide
 (contract-out
  [deposit  (-> account? (>/c 0) account?)]
  [withdraw (->i ([a account?]
                  [amt (a) (and/c (>/c 0) (<=/c (account-balance a)))])
                 [result account?])]
  [struct account ([owner string?] [balance (and/c real? (not/c negative?))])]))
```

Use **`define/contract`** only for a binding that you do *not* export and
want checked locally. It checks the contract again on every call, also in a
recursion. So it is slower, and it can change the behavior of a recursion.
It is not a direct replacement for an export contract.

```racket
(define/contract (double n) (-> number? number?) (* 2 n))
```

## The ladder of function contracts

Pick the simplest step that expresses the constraint:

- **`->`**: a fixed arity, with a contract for each domain and for the
  range: `(-> number? string? boolean?)`.
- **`->*`**: mandatory, optional, and keyword arguments.
  `(->* (string?) (#:loud? boolean?) string?)` is one required positional
  argument, an optional `#:loud?`, and a string result. `#:rest rest/c`
  covers the tail.
- **`->i`**: dependent. A later contract can refer to an earlier argument by
  name. `[amt (a) (<=/c (account-balance a))]` reads "`amt` depends on `a`".
  Use it when a bound, a length, or a result is computed from another
  argument.
- **`case->`**: one binding with several distinct arities, each with its own
  arrow.

### `any` and `any/c` in the range: a real trap

`any/c` means **exactly one value, with no constraint**. `any` means **any
number of values, with no constraint**. Use `any` for a procedure that can
return several values, or when you do not constrain the result at all.
`(-> ... any/c)` *rejects* a return of several values. `(-> ... any)`
accepts it.

## Flat contracts and combinators

Each predicate of one argument is already a flat contract: `number?`,
`string?`, `account?`, or your own `(lambda (x) ...)`. Build richer
contracts with combinators:

| Combinator                       | Meaning                              |
|----------------------------------|--------------------------------------|
| `(or/c c ...)` / `(and/c c ...)` | disjunction / conjunction            |
| `(not/c c)`                      | negation                             |
| `(one-of/c v ...)`               | `eqv?` to one of the listed values   |
| `'sym` / `42` / `"s"`            | a literal datum is its own contract  |
| `(=/c n)` `(>/c n)` `(<=/c n)` … | a numeric comparison                 |
| `(between/c lo hi)`              | a real in `[lo, hi]`                 |
| `(integer-in lo hi)`             | an exact integer in the range        |
| `(string-len/c n)`               | a string shorter than `n`            |

`(or/c 'a 'b)` is the idiomatic "enum". Quoted symbols compare by value.

## Data-structure contracts

Put a contract on the contents of a compound value:

`(listof c)`, `(non-empty-listof c)`, `(vectorof c)`, `(hash/c key/c val/c)`,
`(cons/c car/c cdr/c)`, `(list/c c ...)` (a fixed length), `(box/c c)`,
`(parameter/c c)`. For a struct, list the field contracts in the `struct`
clause of `contract-out` (above). For self-referential data, wrap the
recursive position in `recursive-contract`:

```racket
(define tree/c
  (recursive-contract (or/c number? (cons/c tree/c tree/c)) #:flat))
```

`parametric->/c` expresses parametric polymorphism. `(parametric->/c [X]
(-> X X))` guarantees that the result came from the input and was not
fabricated.

## How to read a blame message

Each contract has two parties. The **positive** party *made* the promise.
That is usually the module with the `provide`. The **negative** party is the
*caller*. A bad argument blames the caller. A bad result blames the
provider.

```
deposit: contract violation
  expected: a number strictly greater than 0
  given: -5
  in: the 2nd argument of
      (-> account? (>/c 0) account?)
  contract from: /path/bank.rkt        ; who attached the contract
  blaming: top-level                   ; who broke it (the caller here)
  at: /path/bank.rkt:15:3
```

Read it as: *the contract is at `bank.rkt`. The caller passed `-5` for the
2nd argument, which must be `> 0`. So the caller is blamed.* When the blame
points at the provider instead, the function returned a value that its own
range contract forbids. The bug is inside the module.

## Rules that prevent rework

- **Put the contract at the boundary, not everywhere.** `contract-out`
  checks once, at the `provide`. A `define/contract` on each internal helper
  adds a cost per call and checks a recursion again, with no extra safety.
- **Climb the ladder only as far as necessary.** Use `->`. Move to `->*` for
  optional or keyword arguments. Use `->i` only when one part really depends
  on another. `->i` is the slowest and the least readable. Do not use it by
  default.
- **Use `any` for the range when the result is unconstrained or has several
  values.** Keep `any/c` for "exactly one value, of any type". A mix of the
  two rejects a legitimate `(values …)` return.
- **A blame on the result means that your code is wrong, not the caller.**
  Do not loosen the argument contracts to silence it. Fix the function or
  its range contract.
- **A quoted literal is a contract.** Write `(or/c 'red 'green)`. Do not
  write a hand-made predicate with `symbol?` plus `memq`.
- **A higher-order contract wraps the value, and the wrap has a cost.** A
  contract on a function or a struct that flows through a hot path checks
  again at each crossing. Measure before you put a contract on
  performance-critical internals. Consider `opt/c` for a contract that is
  used a lot.
