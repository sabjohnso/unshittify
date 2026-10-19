# Module Reference: exact grammars

This file accompanies `SKILL.md`. The sources are docs.racket-lang.org/reference/module.html
and require/provide. The text was checked against Racket v9.1 [cs].

## Module and submodule forms

```racket
(module id module-path form ...)       ; a top-level or independent module
(module* id module-path-or-#f form ...) ; submodule; #f = language and scope of the enclosing module
(module+ id form ...)                   ; submodule that collects the pieces of all uses;
                                        ;   runs after the body of the enclosing module
#lang lang-name                         ; reader shorthand for (module name lang ....)
```

- `module` / `module* … <lang>`: isolated. Its body sees only what it
  `require`s. It does not see the enclosing module.
- `module* … #f`: sees the bindings of the enclosing module (also the
  unexported bindings) and its language. It is evaluated after the enclosing module.
- `module+`: like `module* … #f`, but pieces with the same name combine.
  It is the standard form for `main` and `test`.

Order: the body of the enclosing module runs first. The bodies of `module+`
and `module* #f` run after it. The enclosing module can also `require` its own
submodules.

## module-path (for require / submod)

```racket
module-path =
    "rel/path.rkt"                  ; relative to the enclosing file
  | id                              ; a collection, for example racket/list
  | (lib "collection/file.rkt")
  | (file "/abs/or/rel/path.rkt")
  | (planet ....)                   ; old form
  | (submod base-module-path id ...); a submodule
  | (submod "." id ...)             ; sibling submodule (same file)
  | (submod ".." id ...)            ; enclosing module or its submodule
  | (quote id)                      ; a module declared in the REPL
```

## require-spec

```racket
(require raw-module-path ...
         (only-in    require-spec id-or-[old new] ...)
         (except-in  require-spec id ...)
         (prefix-in  prefix-id require-spec)
         (rename-in  require-spec [old new] ...)
         (combine-in require-spec ...)
         (relative-in module-path require-spec ...)
         (only-meta-in phase require-spec ...)
         (for-syntax  require-spec ...)   ; phase +1
         (for-template require-spec ...)  ; phase -1
         (for-label   require-spec ...)   ; phase #f (no run, for example docs)
         (for-meta    phase require-spec ...))
```

Wrappers combine. For example, `(prefix-in p: (only-in m a b))` imports `p:a` and `p:b`.

## provide-spec

```racket
(provide id ...
         (rename-out  [local-id export-id] ...)
         (struct-out  struct-id)               ; constructor, predicate, accessors, setters
         (all-defined-out)                      ; all module-level definitions in this module
         (all-from-out module-path ...)         ; export again the imports of a module
         (prefix-out  prefix-id provide-spec)
         (except-out  provide-spec id ...)
         (combine-out provide-spec ...)
         (contract-out [id contract] ...)       ; see the contracts skill
         (protect-out provide-spec ...)         ; the importer needs protected access
         (for-syntax provide-spec ...)          ; export at phase 1
         (for-label  provide-spec ...)
         (for-meta phase provide-spec ...))
```

`all-from-out` exports again only the bindings that came from `require`. It
does not export local definitions. `all-defined-out` exports only local
definitions. It does not export imports.

## Reflection and tooling

```racket
(dynamic-require module-path provided-sym-or-#f [fail-thunk]) -> any
   ; If the provided value is #f, the call only instantiates the module for its effects.
(dynamic-require-for-syntax module-path sym) -> any
(module->exports module-path)
   -> (values phase-exports phase-syntax-exports)   ; one list for each phase
(module->imports module-path) -> assoc of phase -> module-path-index list
(module-predefined? module-path) -> boolean?
(module-path? v) (resolved-module-path? v) (module-path-index? v)
```

Run and build:
- `racket file.rkt` instantiates the module and runs `(module+ main ...)`.
- `raco test file.rkt` runs the `test` submodule and any submodule that the
  `test` configuration lists. The usual place for tests is `(module+ test ...)`.
- `raco make file.rkt` compiles the file to `compiled/*.zo`.
- `raco exe file.rkt` builds a stand-alone executable from `main`.
