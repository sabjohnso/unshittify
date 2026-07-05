---
description: Build, develop, and distribute Racket code with raco and packages — collections vs packages, the info.rkt manifest (deps/build-deps/version/scribblings), scaffolding with raco pkg new, in-place development with raco pkg install --link, building with raco make/setup/test, standalone executables with raco exe, and publishing to the package catalog. Use when structuring a package, editing info.rkt, fixing dependency-check errors, or shipping a Racket library or app.
---

# raco and Packages

Two layers organize Racket code for reuse:

- A **collection** is a directory of modules requirable by a stable path:
  files under a `foo/` collection are reached as `(require foo/bar)` — the
  collection name *is* the require path (see [[modules]]).
- A **package** is a unit of *distribution* that provides one or more
  collections, declared by an `info.rkt` manifest. Installing a package makes
  its collections available everywhere.

`raco` is the command hub for all of it: build, test, install, package.

## Scaffold a package

```
raco pkg new my-lib
```

generates a working package: `info.rkt` (the manifest), `main.rkt` (the
collection's entry module with `test`/`main` submodules), `scribblings/` (a
Scribble manual, see [[scribble-docs]]), `README.md`, `LICENSE-*`, and a CI
workflow. The collection name defaults to the package name, so `(require
my-lib)` loads `main.rkt`.

## The info.rkt manifest

`info.rkt` is written in `#lang info` — a set of `define`s read by the package
tools, not run as a program:

```racket
#lang info
(define collection "my-lib")              ; collection name (or 'multi)
(define deps '("base"))                    ; runtime dependencies
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"))
(define scribblings '(("scribblings/my-lib.scrbl" ())))
(define version "1.0")
(define pkg-desc "One-line description")
(define license '(Apache-2.0 OR MIT))
```

- **`deps` vs `build-deps` is the split that bites people.** `deps` are
  needed to *run* the library; `build-deps` are needed only to *build docs
  and run tests* (`scribble-lib`, `racket-doc`, `rackunit-lib`). Putting a
  doc-only dependency in `deps` forces every user to install it at runtime;
  omitting a real runtime dep breaks installs. `raco setup --check-pkg-deps`
  flags both mistakes.
- `(define collection 'multi)` instead of a name makes a **multi-collection**
  package: each top-level subdirectory is its own collection.
- Other common fields: `compile-omit-paths`, `test-omit-paths`,
  `racket-launcher-names`/`racket-launcher-libraries` (install a CLI),
  `implies` (re-export sub-packages).

## Develop in place

Link the working directory so edits take effect immediately, no reinstall:

```
raco pkg install --link            # from inside the package dir
raco pkg install --link /path/to/my-lib
```

`--link` registers the directory as the package source; `raco pkg show` lists
it as a `link`. (`--copy` snapshots instead; `--clone <dir>` links a git
checkout.) Remove with `raco pkg remove my-lib`.

Resolve dependencies during install with `--auto` (install missing deps
without asking) or `--deps search-auto`; choose where it lands with
`--scope user` (default, per-user) vs `--installation`/`-i` (all users).

## Build and test

- **`raco make file.rkt`** compiles to `compiled/*.zo` bytecode (faster
  loads). Usually you don't call it directly — `setup` does.
- **`raco setup`** builds a collection end to end: bytecode, docs, and info.
  Scope it: `raco setup my-lib` or `raco setup --pkgs my-lib`. Add
  `--check-pkg-deps` to validate `deps`/`build-deps`, `--no-docs` to skip
  docs, `-j N` for parallelism, `--clean` to wipe built files first.
- **`raco test`** runs the `test` submodules (see [[rackunit]]). Targets:
  `raco test file.rkt`, `raco test -c my-lib` (a collection), `raco test -p
  my-lib` (a package), `-s name` for a non-`test` submodule, `-j N` to
  parallelize.

A typical loop: `raco pkg install --link`, edit, `raco test -p my-lib`, and
`raco setup my-lib` before committing to catch doc/dependency breakage.

## Ship an application

- **`raco exe -o my-app main.rkt`** builds a standalone executable that
  embeds the Racket runtime (add `--gui` for a `racket/gui` app, `-l` for a
  launcher that uses the installed collections instead of embedding).
- **`raco distribute dist-dir my-app`** gathers the executable and its
  shared-library dependencies into a directory you can zip and ship to
  machines without Racket installed.

## Publish a package

A catalog entry (pkgs.racket-lang.org) maps a package *name* to a *source* —
almost always a public git repository; users then `raco pkg install my-lib`.
Steps: put `info.rkt` at the repo root (or in a subdir for a multi-package
repo), push to git, and register the name + URL on the catalog. `raco pkg
create --format zip` bundles a directory into an archive with a checksum if
you distribute outside a catalog. Bump `version` in `info.rkt` on each
release (semantic versioning), since the catalog and `raco pkg update` track
changes by checksum and version.

## Rules that prevent rework

- **`--link` for development, not `--copy`.** A linked package picks up edits
  live; a copied one must be reinstalled after every change.
- **Get `deps` vs `build-deps` right, and run `--check-pkg-deps`.** Runtime
  needs go in `deps`; docs/test-only needs go in `build-deps`. `raco setup
  --check-pkg-deps` (and the catalog's CI) will reject a mismatch — fix it
  before publishing.
- **The collection name is the require path.** Name the collection for how
  users will `require` it; renaming later breaks every dependent (a
  data-version-transparency concern — keep the path stable).
- **Run `raco setup` before release, not just `raco test`.** `setup` builds
  docs and checks dependencies; tests alone miss unlinked-identifier and
  missing-dep errors that only surface at build time (see [[scribble-docs]]).
- **Bump `version` on every release.** The catalog and `raco pkg update`
  reconcile by version/checksum; an unchanged version hides changes from
  updaters.
