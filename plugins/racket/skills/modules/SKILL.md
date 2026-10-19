---
description: Organize Racket code with modules and submodules. Covers the require sub-forms (only-in, except-in, prefix-in, rename-in, submod), the provide forms (rename-out, struct-out, contract-out, all-defined-out, all-from-out, for-syntax), and the three submodule kinds (module+, module, module*), with the main and test idiom. Use when you structure code across files, when you control the exports and the imports, when you add tests or a script entry point inside a file, or when you reach a submodule with submod or dynamic-require.
allowed-tools: Bash(racket:*), Bash(raco:*), Read, Grep, Glob
---

# Racket modules and submodules

A file is a module. The `#lang` line picks its language, and everything at
the module level is private until a `provide` exports it. A module imports
with `require` and exports with `provide`. A submodule nests related code
(tests, a script entry point, helpers of an other phase) inside one file. For
the full require and provide grammar and the submodule forms, read
`reference.md` in this skill directory.

## require: bring names in

A require spec is a module path, or a wrapper that adjusts which names
arrive:

```racket
(require "helper.rkt"               ; a relative file (in the same directory)
         racket/list                ; a collection path
         (only-in racket/string string-trim string-split)
         (except-in racket/list first)
         (prefix-in str: racket/string)     ; str:string-trim
         (rename-in racket/math [pi PI])
         (submod "subs.rkt" extra)          ; a submodule of an other file
         (for-syntax racket/base))          ; phase 1 (see ../macros/SKILL.md)
```

| Wrapper                       | Effect                                     |
|-------------------------------|--------------------------------------------|
| `(only-in m id ...)`          | import only those names (a rename is possible) |
| `(except-in m id ...)`        | import all but those names                 |
| `(prefix-in p m)`             | put the prefix `p` on every imported name  |
| `(rename-in m [old new] ...)` | import `old` under the name `new`          |
| `(combine-in m ...)`          | the union of several specs                 |
| `(submod path name ...)`      | a named submodule                          |
| `(for-syntax m)`              | import at phase 1 (transformer time)       |

## provide: expose names

Nothing leaves a module without a `provide`. Put the provides at any place
at the module level. The top is the convention:

```racket
(provide greet                          ; a single binding
         (rename-out [internal-add add]); export under a different name
         (struct-out posn)              ; the constructor, the predicate, and the accessors
         (contract-out                  ; guarded by a contract. See ../contracts/SKILL.md
          [halve (-> number? number?)])
         (all-defined-out)              ; every module-level definition here
         (all-from-out racket/list)     ; export everything from a require again
         (for-syntax (all-defined-out)))
```

`(struct-out posn)` is the idiomatic way to export a struct in full. Prefer
named exports (or `contract-out`) to `all-defined-out` for a stable boundary
with an intent. `all-defined-out` leaks every later definition.

## Submodules: three kinds

A submodule is a module nested in an other module. The form that you use
decides whether the submodule can see the bindings of the enclosing module.

### `module+`: accumulates, and sees the enclosing module

This is the everyday form. Several `(module+ name ...)` with the same name
append into one submodule. The body can use the bindings of the enclosing
module, also the ones that are not exported. The tools know two names:

```racket
(module+ main
  (printf "runs only as the entry point\n"))   ; `racket file.rkt`, not a require

(module+ test
  (require rackunit)
  (check-equal? (internal-add 2 3) 5))          ; sees a binding that is NOT exported
```

- **`main`** runs only when the file runs directly (`racket file.rkt` or
  DrRacket). It does **not** run when an other module `require`s the file.
  It is the standard place for the top-level actions of a script.
- **`test`** runs under `raco test file.rkt`. It sees the enclosing module,
  so it can test private helpers with no export.

### `module`: independent

`(module name lang ...)` declares its own language and is *self-contained*.
It cannot see the bindings of the enclosing module, and it must `require`
what it needs. Use it for code that must be isolated.

```racket
(module independent racket/base
  (provide indep-val)
  (define indep-val 'standalone))
```

### `module*`: sees the enclosing module (with `#f`)

`(module* name #f ...)` uses the language of the enclosing module *and* sees
its bindings. It is useful to expose an extra view (for example the internals
for a test) without the accumulation of `module+`. With a real language in
the place of `#f`, it is isolated like `module`.

```racket
(module* internals #f
  (provide secret)        ; expose a binding of the parent that is not exported
  )
```

## Reach a submodule from outside

Address a submodule with `submod`. From an other file:

```racket
(require (submod "subs.rkt" extra))                 ; static
(dynamic-require '(submod "subs.rkt" independent) 'indep-val)  ; dynamic
```

Inside the same file, `(submod "." name)` names a sibling, and `(submod ".."
name)` names the parent.

## Rules that prevent rework

- **`provide` is the boundary. Design it.** Everything else stays private.
  Export named bindings or `contract-out`
  ([contracts](../contracts/SKILL.md)). Avoid `all-defined-out` on all that
  you want to keep changeable.
- **`main` is for "run me", not for "require me".** Put the side effects of
  a script in `(module+ main ...)`. Then an import of the file stays pure. A
  top-level effect fires on every require.
- **Put the tests in `(module+ test ...)`.** They stay in the same file,
  they run under `raco test`, and they can check helpers that are not
  exported. No separate test file and no extra export is necessary.
- **Pick the submodule kind by visibility.** If you need the bindings of the
  parent, use `module+` or `module* … #f`. If you want isolation with its own
  language, use `module`. A `module` submodule that "cannot see" a binding
  of the parent works as designed. `require` the binding, or change the
  form.
- **Prefer `(struct-out s)` to a list of the struct bindings.** It exports
  the constructor, the predicate, the accessors, and the setters together,
  and it stays correct when the fields change.
- **Require the transformer imports `for-syntax`.** All that a macro uses at
  expansion time is a phase-1 import. See [macros](../macros/SKILL.md).
