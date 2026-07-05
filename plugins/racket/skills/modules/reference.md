# Module Reference — exact grammars

Companion to SKILL.md. Source: docs.racket-lang.org/reference/module.html
and require/provide. Checked against Racket v9.1 [cs].

## Module and submodule forms

```racket
(module id module-path form ...)       ; a top-level/independent module
(module* id module-path-or-#f form ...) ; submodule; #f = enclosing language + scope
(module+ id form ...)                   ; submodule that accumulates across uses;
                                        ;   runs after the enclosing module body
#lang lang-name                         ; reader shorthand for (module name lang ....)
```

- `module` / `module* … <lang>`: isolated — its body sees only what it
  `require`s, not the enclosing module.
- `module* … #f`: sees the enclosing module's bindings (incl. unexported)
  and language; evaluated after the enclosing module.
- `module+`: like `module* … #f` but several same-named pieces combine; the
  standard form for `main` and `test`.

Submodule order: a `module`/`module+`/`module*` may be required by the
enclosing module, and `module+`/`module* #f` may use the enclosing module —
the enclosing module body runs first, then `module+`/`module*` bodies.

## module-path (for require / submod)

```racket
module-path =
    "rel/path.rkt"                  ; relative to the enclosing file
  | id                              ; a collection, e.g. racket/list
  | (lib "collection/file.rkt")
  | (file "/abs/or/rel/path.rkt")
  | (planet ....)                   ; legacy
  | (submod base-module-path id ...); a submodule
  | (submod "." id ...)             ; sibling submodule (same file)
  | (submod ".." id ...)            ; enclosing module / its submodule
  | (quote id)                      ; an interactively-declared module
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
         (for-label   require-spec ...)   ; phase #f (no run, e.g. docs)
         (for-meta    phase require-spec ...))
```

Wrappers compose: `(prefix-in p: (only-in m a b))` imports `p:a`, `p:b`.

## provide-spec

```racket
(provide id ...
         (rename-out  [local-id export-id] ...)
         (struct-out  struct-id)               ; ctor, predicate, accessors, setters
         (all-defined-out)                      ; all module-level definitions here
         (all-from-out module-path ...)         ; re-export a module's imports
         (prefix-out  prefix-id provide-spec)
         (except-out  provide-spec id ...)
         (combine-out provide-spec ...)
         (contract-out [id contract] ...)       ; see the contracts skill
         (protect-out provide-spec ...)         ; require protected access
         (for-syntax provide-spec ...)          ; export at phase 1
         (for-label  provide-spec ...)
         (for-meta phase provide-spec ...))
```

`all-from-out` only re-exports bindings that arrived via `require` (not
local definitions); `all-defined-out` only exports local definitions (not
imports).

## Reflection and tooling

```racket
(dynamic-require module-path provided-sym-or-#f [fail-thunk]) -> any
   ; #f for provided => just instantiate the module for effect.
(dynamic-require-for-syntax module-path sym) -> any
(module->exports module-path)
   -> (values phase-exports phase-syntax-exports)   ; list per phase
(module->imports module-path) -> assoc of phase -> module-path-index list
(module-predefined? module-path) -> boolean?
(module-path? v) (resolved-module-path? v) (module-path-index? v)
```

Run / build:
- `racket file.rkt` instantiates the module and runs `(module+ main ...)`.
- `raco test file.rkt` runs the `test` submodule (and any submodule listed
  in `test` config); `(module+ test ...)` is the common home for tests.
- `raco make file.rkt` compiles to `compiled/*.zo`.
- `raco exe file.rkt` builds a stand-alone executable from `main`.
