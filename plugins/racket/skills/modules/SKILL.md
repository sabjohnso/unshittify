---
description: Organize Racket code with modules and submodules — require sub-forms (only-in, except-in, prefix-in, rename-in, submod), provide forms (rename-out, struct-out, contract-out, all-defined-out, all-from-out, for-syntax), and the three submodule kinds (module+, module, module*) including the main/test idiom. Use when structuring code across files, controlling exports/imports, adding in-file tests or a script entry point, or accessing a submodule with submod/dynamic-require.
---

# Racket Modules and Submodules

A file is a module: the `#lang` line picks its language, and everything at
module level is private until `provide`d. Modules import with `require` and
export with `provide`; submodules nest related code (tests, a script entry,
phase-separated helpers) inside one file. For the full require/provide
grammar and submodule forms, read `reference.md` in this skill directory.

## require — bringing names in

A require spec is a module path or a wrapper that adjusts which names arrive:

```racket
(require "helper.rkt"               ; relative file (same directory)
         racket/list                ; collection path
         (only-in racket/string string-trim string-split)
         (except-in racket/list first)
         (prefix-in str: racket/string)     ; str:string-trim
         (rename-in racket/math [pi PI])
         (submod "subs.rkt" extra)          ; a submodule of another file
         (for-syntax racket/base))          ; phase 1 (see [[macros]])
```

| Wrapper                         | Effect                                         |
|---------------------------------|------------------------------------------------|
| `(only-in m id ...)`            | import just those names (renamable)            |
| `(except-in m id ...)`          | import all but those                           |
| `(prefix-in p m)`               | prefix every imported name with `p`            |
| `(rename-in m [old new] ...)`   | import `old` under the name `new`              |
| `(combine-in m ...)`            | union of several specs                         |
| `(submod path name ...)`        | a named submodule                              |
| `(for-syntax m)`                | import at phase 1 (transformer time)           |

## provide — exposing names

Nothing leaves a module without `provide`. Place provides anywhere at module
level (top is conventional):

```racket
(provide greet                          ; a single binding
         (rename-out [internal-add add]); export under a different name
         (struct-out posn)              ; constructor + predicate + accessors
         (contract-out                  ; export guarded by a contract — see [[contracts]]
          [halve (-> number? number?)])
         (all-defined-out)              ; every module-level definition here
         (all-from-out racket/list)     ; re-export everything from a require
         (for-syntax (all-defined-out)))
```

`(struct-out posn)` is the idiomatic way to export a struct fully. Prefer
naming exports (or `contract-out`) over `all-defined-out` for a stable,
intentional boundary; `all-defined-out` leaks every later definition.

## Submodules — three kinds

A submodule is a module nested in another. Which form you use decides
whether it can see the enclosing module's bindings.

### `module+` — accumulating, sees the enclosing module

The everyday form. Multiple `(module+ name ...)` with the same name append
into one submodule, and the body can use the enclosing module's bindings
(including unexported ones). Two conventions are built into the tools:

```racket
(module+ main
  (printf "runs only as the entry point\n"))   ; `racket file.rkt`, not when required

(module+ test
  (require rackunit)
  (check-equal? (internal-add 2 3) 5))          ; sees a NON-exported binding
```

- **`main`** runs only when the file is run directly (`racket file.rkt` or
  DrRacket), **not** when another module `require`s the file — the standard
  place for a script's top-level actions.
- **`test`** runs under `raco test file.rkt`. Because it sees the enclosing
  module, it can test private helpers without exporting them.

### `module` — independent

`(module name lang ...)` declares its own language and is *self-contained*:
it cannot see the enclosing module's bindings and must `require` what it
needs. Use it for code that should be isolated.

```racket
(module independent racket/base
  (provide indep-val)
  (define indep-val 'standalone))
```

### `module*` — submodule that can peek

`(module* name #f ...)` uses the enclosing module's language *and* sees its
bindings — useful to expose an extra view (e.g. internals for testing)
without `module+`'s accumulation. With a real language instead of `#f`, it is
isolated like `module`.

```racket
(module* internals #f
  (provide secret)        ; re-expose an unexported binding of the parent
  )
```

## Reaching a submodule from outside

Submodules are addressed with `submod`. From another file:

```racket
(require (submod "subs.rkt" extra))                 ; static
(dynamic-require '(submod "subs.rkt" independent) 'indep-val)  ; dynamic
```

Within the same file, `(submod "." name)` names a sibling and `(submod ".."
name)` the parent.

## Rules that prevent rework

- **`provide` is the boundary — design it.** Everything else stays private.
  Export named bindings or `contract-out` ([[contracts]]); avoid
  `all-defined-out` on anything you want to keep changeable.
- **`main` for "run me," not "require me."** Put a script's side effects in
  `(module+ main ...)` so importing the file stays pure; top-level effects
  fire on every require.
- **Put tests in `(module+ test ...)`.** They ride along in the same file,
  run under `raco test`, and can check unexported helpers — no separate test
  file or extra exports needed.
- **Pick the submodule kind by visibility.** Need the parent's bindings →
  `module+` or `module* … #f`; want isolation with its own language →
  `module`. A `module` submodule that "can't see" a parent binding is
  working as designed — `require` it or switch forms.
- **Prefer `(struct-out s)` to listing struct bindings.** It exports the
  constructor, predicate, accessors, and setters together and stays correct
  when fields change.
- **Require transformer imports `for-syntax`.** Anything a macro uses at
  expansion time is a phase-1 import; see [[macros]].
