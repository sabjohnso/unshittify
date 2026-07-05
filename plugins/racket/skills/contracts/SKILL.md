---
description: Add Racket contracts with racket/contract — function contracts (->, ->*, ->i, case->), contract-out on module exports, struct and data-structure contracts (listof, hash/c, struct/c, recursive-contract), combinators (or/c, and/c, between/c), and reading blame. Use when contracting a module boundary, specifying argument/result constraints, debugging a contract violation / blame message, or choosing between contract-out and define/contract.
---

# Racket Contracts

A contract is a runtime agreement checked when a value crosses a boundary —
usually a module's `provide`. When the check fails, the contract system
raises an error that **blames** the party that broke the agreement. Built
into `#lang racket`; under `racket/base` add `(require racket/contract)`.
For exact grammars and the full combinator list, read `reference.md` in this
skill directory.

## Where to attach a contract

Prefer **`contract-out` in `provide`** for exported bindings — the contract
sits exactly at the module boundary, so internal calls run unchecked and the
blame names the right module:

```racket
#lang racket/base
(require racket/contract)

(provide
 (contract-out
  [deposit  (-> account? (>/c 0) account?)]
  [withdraw (->i ([a account?]
                  [amt (a) (and/c (>/c 0) (<=/c (account-balance a)))])
                 [result account?])]
  [struct account ([owner string?] [balance (and/c real? (not/c negative?))])]))
```

Use **`define/contract`** only for a binding you are *not* exporting and
want checked locally. It re-checks on every call (including recursion), so
it is slower and can change recursion behavior — not a drop-in for export
contracts.

```racket
(define/contract (double n) (-> number? number?) (* 2 n))
```

## The function-contract ladder

Pick the simplest rung that expresses the constraint:

- **`->`** — fixed arity, each domain and the range a contract:
  `(-> number? string? boolean?)`.
- **`->*`** — mandatory + optional + keyword args:
  `(->* (string?) (#:loud? boolean?) string?)` is one required positional,
  an optional `#:loud?`, returning a string. `#:rest rest/c` for the tail.
- **`->i`** — dependent: a later contract may reference earlier arguments by
  name. `[amt (a) (<=/c (account-balance a))]` reads "`amt` depends on `a`."
  Use it when a bound, length, or result is computed from another argument.
- **`case->`** — one binding with several distinct arities, each its own
  arrow.

### `any` vs `any/c` in the range — a real trap

`any/c` means **exactly one value, unconstrained**. `any` means **any number
of values, unconstrained** — use it for procedures that may return multiple
values (or when you simply don't constrain the result). `(-> ... any/c)`
*rejects* a multiple-values return; `(-> ... any)` accepts it.

## Flat contracts and combinators

Any predicate of one argument is already a flat contract: `number?`,
`string?`, `account?`, or your own `(lambda (x) ...)`. Build richer ones with
combinators:

| Combinator                       | Means                               |
|----------------------------------|-------------------------------------|
| `(or/c c ...)` / `(and/c c ...)` | disjunction / conjunction           |
| `(not/c c)`                      | negation                            |
| `(one-of/c v ...)`               | `eqv?` to one of the listed values  |
| `'sym` / `42` / `"s"`            | a literal datum is its own contract |
| `(=/c n)` `(>/c n)` `(<=/c n)` … | numeric comparison                  |
| `(between/c lo hi)`              | real in `[lo, hi]`                  |
| `(integer-in lo hi)`             | exact integer in range              |
| `(string-len/c n)`               | string shorter than `n`             |

`(or/c 'a 'b)` is the idiomatic "enum"; quoted symbols compare by value.

## Data-structure contracts

Contract the contents of compound values:

`(listof c)`, `(non-empty-listof c)`, `(vectorof c)`, `(hash/c key/c val/c)`,
`(cons/c car/c cdr/c)`, `(list/c c ...)` (fixed-length), `(box/c c)`,
`(parameter/c c)`. For structs, list field contracts in `contract-out`'s
`struct` clause (above). For self-referential data, wrap the recursive
position in `recursive-contract`:

```racket
(define tree/c
  (recursive-contract (or/c number? (cons/c tree/c tree/c)) #:flat))
```

`parametric->/c` expresses parametric polymorphism — `(parametric->/c [X]
(-> X X))` guarantees the result came from the input, not fabricated.

## Reading a blame message

Each contract has two parties: the **positive** party (the module that
*made* the promise — usually the one with the `provide`) and the
**negative** party (the *caller*). A bad argument blames the caller; a bad
result blames the provider.

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

Read it as: *the contract lives at `bank.rkt`; the caller passed `-5` for
the 2nd argument, which must be `> 0`, so the caller is blamed.* When blame
points at the provider instead, the function returned a value its own range
contract forbids — the bug is inside the module.

## Rules that prevent rework

- **Contract at the boundary, not everywhere.** `contract-out` checks once,
  at the `provide`. Sprinkling `define/contract` on internal helpers adds
  per-call overhead and re-checks recursion for no extra safety.
- **Climb the ladder only as needed.** Use `->`; move to `->*` for
  optional/keyword args; reach `->i` only when one part genuinely depends on
  another. `->i` is the slowest and least readable — don't default to it.
- **`any` for the range when the result is unconstrained or multi-valued.**
  Reserve `any/c` for "exactly one value, any type." Mixing them up rejects
  legitimate `(values …)` returns.
- **A bad-result blame means your code is wrong, not the caller's.** Don't
  loosen the argument contracts to silence it — fix the function or its
  range contract.
- **Quoted literals are contracts.** Write `(or/c 'red 'green)` rather than a
  hand-rolled `symbol?`-plus-`memq` predicate.
- **Higher-order contracts wrap, and wrapping has a cost.** A contract on a
  function or struct that flows through hot paths re-checks at each crossing;
  measure before contracting performance-critical internals, and consider
  `opt/c` for heavily reused contracts.
