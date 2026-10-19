---
description: Build, develop, and distribute Racket code with raco and packages. Covers collections and packages, the info.rkt manifest (deps, build-deps, version, scribblings), a scaffold with raco pkg new, development in place with raco pkg install --link, a build with raco make, setup, and test, a standalone executable with raco exe, and a publication to the package catalog. Use when you structure a package, when you edit info.rkt, when you fix a dependency-check error, or when you ship a Racket library or application.
allowed-tools: Bash(racket:*), Bash(raco:*), Read, Grep, Glob
---

# raco and packages

Two layers organize Racket code for reuse:

For the full list of `raco` subcommands and every field of the `info.rkt`
manifest, read `reference.md` in this skill directory.

- A **collection** is a directory of modules that you require by a stable
  path. You reach the files under a `foo/` collection with `(require
  foo/bar)`. The collection name *is* the require path (see
  [modules](../modules/SKILL.md)).
- A **package** is a unit of *distribution* that gives one or more
  collections. An `info.rkt` manifest declares it. An install of a package
  makes its collections available everywhere.

`raco` is the command hub for all of it: the build, the tests, the install,
and the package.

## Scaffold a package

```
raco pkg new my-lib
```

This generates a package that works: `info.rkt` (the manifest), `main.rkt`
(the entry module of the collection, with `test` and `main` submodules),
`scribblings/` (a Scribble manual, see
[scribble-docs](../scribble-docs/SKILL.md)), `README.md`, `LICENSE-*`, and
a CI workflow. The collection name defaults to the package name, so
`(require my-lib)` loads `main.rkt`.

## The info.rkt manifest

`info.rkt` is written in `#lang info`. It is a set of `define`s that the
package tools read. It does not run as a program:

```racket
#lang info
(define collection "my-lib")              ; the collection name (or 'multi)
(define deps '("base"))                    ; the runtime dependencies
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"))
(define scribblings '(("scribblings/my-lib.scrbl" ())))
(define version "1.0")
(define pkg-desc "One-line description")
(define license '(Apache-2.0 OR MIT))
```

- **The split between `deps` and `build-deps` is easy to get wrong.** `deps`
  are necessary to *run* the library. `build-deps` are necessary only to
  *build the docs and run the tests* (`scribble-lib`, `racket-doc`,
  `rackunit-lib`). A doc-only dependency in `deps` forces every user to
  install it at run time. A real runtime dependency that is absent breaks
  the install. `raco setup --check-pkg-deps` flags both mistakes.
- `(define collection 'multi)` in the place of a name makes a
  **multi-collection** package. Each top-level subdirectory is its own
  collection.
- Other common fields: `compile-omit-paths`, `test-omit-paths`,
  `racket-launcher-names` and `racket-launcher-libraries` (they install a
  CLI), `implies` (it exports sub-packages again).

## Develop in place

Link the working directory, so an edit takes effect at once, with no
reinstall:

```
raco pkg install --link            # from inside the package directory
raco pkg install --link /path/to/my-lib
```

`--link` registers the directory as the package source. `raco pkg show`
lists it as a `link`. (`--copy` takes a snapshot instead. `--clone <dir>`
links a git checkout.) Remove it with `raco pkg uninstall my-lib`.

Resolve the dependencies during the install with `--auto` (install the
missing dependencies with no question) or `--deps search-auto`. Choose where
the package lands with `--scope user` (the default, per user) or
`--installation` / `-i` (all users).

## Build and test

- **`raco make file.rkt`** compiles to `compiled/*.zo` bytecode (faster
  loads). Usually you do not call it directly. `setup` does.
- **`raco setup`** builds a collection from end to end: the bytecode, the
  docs, and the info. Limit its scope: `raco setup my-lib` or `raco setup
  --pkgs my-lib`. Add `--check-pkg-deps` to validate `deps` and
  `build-deps`, `--no-docs` to skip the docs, `-j N` for parallel work, and
  `--clean` to remove the built files first.
- **`raco test`** runs the `test` submodules (see
  [rackunit](../rackunit/SKILL.md)). The targets: `raco test file.rkt`,
  `raco test -c my-lib` (a collection), `raco test -p my-lib` (a package),
  `-s name` for a submodule that is not `test`, `-j N` for parallel work.

A typical loop: `raco pkg install --link`, edit, `raco test -p my-lib`, and
`raco setup my-lib` before the commit, to catch a doc or dependency failure.

## Ship an application

- **`raco exe -o my-app main.rkt`** builds a standalone executable that
  embeds the Racket runtime. Add `--gui` for a `racket/gui` application. Add
  `-l` for a launcher that uses the installed collections instead of an
  embed.
- **`raco distribute dist-dir my-app`** collects the executable and its
  shared-library dependencies into a directory. You can zip it and ship it
  to a machine with no Racket install.

## Publish a package

A catalog entry (pkgs.racket-lang.org) maps a package *name* to a *source*,
almost always a public git repository. A user then runs `raco pkg install
my-lib`. The steps: put `info.rkt` at the root of the repository (or in a
subdirectory for a repository with several packages), push to git, and
register the name and the URL on the catalog. `raco pkg create --format zip`
bundles a directory into an archive with a checksum, if you distribute
outside a catalog. Increase `version` in `info.rkt` on each release
(semantic versions), because the catalog and `raco pkg update` track changes
by checksum and version.

## Rules that prevent rework

- **`--link` for development, not `--copy`.** A linked package picks up each
  edit live. A copied package needs a reinstall after every change.
- **Get `deps` and `build-deps` right, and run `--check-pkg-deps`.** The
  runtime needs go in `deps`. The needs of the docs and the tests go in
  `build-deps`. `raco setup --check-pkg-deps` (and the CI of the catalog)
  rejects a mismatch. Fix it before the publication.
- **The collection name is the require path.** Name the collection for the
  way that users will `require` it. A later rename breaks every dependent.
  That is a data-version-transparency concern. Keep the path stable.
- **Run `raco setup` before a release, not only `raco test`.** `setup`
  builds the docs and checks the dependencies. The tests alone miss an
  unlinked identifier and a missing dependency, which only show up at build
  time (see [scribble-docs](../scribble-docs/SKILL.md)).
- **Increase `version` on every release.** The catalog and `raco pkg update`
  compare by version and checksum. An unchanged version hides the changes
  from the updaters.
