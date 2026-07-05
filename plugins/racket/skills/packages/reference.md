# raco / Packages Reference — commands and manifest fields

Companion to SKILL.md. Source: docs.racket-lang.org/pkg/ and the `raco`
reference. Flags checked against Racket v9.1 [cs] (`raco <cmd> --help`).

## raco pkg subcommands

```
raco pkg install [opt ...] [<src> ...]   ; install; no src => current dir
raco pkg update  [opt ...] [<src> ...]   ; update installed packages
raco pkg remove  [opt ...] <name> ...    ; (alias: uninstall)
raco pkg new     <name>                  ; scaffold a package directory
raco pkg show    [opt ...] [<name> ...]  ; list installed packages
raco pkg create  [opt ...] <dir>         ; bundle a directory into an archive
raco pkg migrate <from-version>          ; reinstall packages from another version
raco pkg config  [--set] <key> [<val>]   ; view/modify pkg config (e.g. catalogs)
raco pkg catalog-show <name> ...         ; query a catalog
raco pkg empty-trash
```

### install / update options

```
-t, --type <type>     file | dir | file-url | dir-url | git | git-url | github | name
-n, --name <name>     override inferred package name
--checksum <sum>      expected/selected checksum
--deps <mode>         fail | force | search-ask | search-auto
--auto                = --deps search-auto (install missing deps silently)
--update-deps         also update dependencies (with search-* modes)
--link                link a directory source in place (default for a dir)
--static-link         link, promising collections won't change
--copy                copy the source instead of linking
--clone <dir>         clone a git/github source to <dir> and link
--source | --binary | --binary-lib   strip built / source / source+doc elements
--scope <s>           installation | user        (-i / -u shorthands)
-u, --user            per-user (the default scope)
-i, --installation    for all users of this Racket
-D, --no-docs         skip building docs
--batch               non-interactive (no prompts)
-j, --jobs <n>        parallel jobs
-a, --all             (update) update all installed packages
--dry-run             (update) show what would change
```

### create options

```
--format <fmt>        zip (default) | tgz | plt   (archive format)
--manifest            write a directory manifest instead of an archive
--original <pkg>      base the bundle on an installed package
--dest <dir>          output directory
```

## raco setup

```
raco setup [opt ...] [<collection> ...]   ; build everything if no target
  -l <collection> ...   set up only these collections
  --pkgs <pkg> ...      set up collections in these packages
  --check-pkg-deps      verify deps / build-deps are correct
  -c, --clean           delete existing compiled files first
  -D, --no-docs         skip documentation
  --doc-index           rebuild the doc index
  --tidy                clear references to removed items
  -j, --jobs <n>        parallel jobs (also --workers)
  --recompile-only      fail if anything would compile from source
```

## raco make / test / exe / distribute

```
raco make [opt ...] <file> ...            ; compile to compiled/*.zo
  -j <n>            parallel
  --disable-inline  ...

raco test [opt ...] <file-or-target> ...  ; run test submodules
  -c, --collection      treat args as collections
  -p, --package         treat args as packages
  -s, --submodule <n>   run submodule <n> (default: test)
  -j, --jobs <n>        parallel
  --timeout <secs>      per-test timeout
  -t, --table           summary table
  -e, --check-stderr    fail if anything is written to stderr
  -q, --quiet           less output

raco exe [opt ...] <file>                 ; standalone executable
  -o <file>             output name
  --gui                 build a GUI (racket/gui) executable
  -l, --launcher        make a launcher (uses installed collections, not embedded)
  --collects-dest <dir> write embedded collections to <dir>
  --embed-dlls          embed DLLs (Windows)
  --ico / --icns <f>    set the icon
  --cs / --3m / --cgc   choose the VM variant

raco distribute <dest-dir> <exe> ...      ; bundle exe + libraries for shipping
```

## info.rkt fields (#lang info)

```racket
(define collection name-string-or-'multi)  ; require path, or 'multi for many
(define deps        (list dep ...))         ; runtime dependencies
(define build-deps  (list dep ...))         ; doc/test-time dependencies
   dep = "pkg-name"
       | (list "pkg-name" #:version "x.y")
       | (list "pkg-name" #:platform platform-spec)
(define version     "x.y")                  ; package version (semantic)
(define pkg-desc    "one line")             (define pkg-authors '(id ...))
(define license     '(Apache-2.0 OR MIT))
(define scribblings '(("path.scrbl" (flags ...)) ...))   ; see scribble-docs
(define compile-omit-paths (list "p" ...))  ; or 'all
(define compile-omit-files (list "f.rkt" ...))
(define test-omit-paths    (list "p" ...))  ; or 'all
(define test-include-paths ...)
(define racket-launcher-names     (list "cmd" ...))      ; install CLI launchers
(define racket-launcher-libraries (list "cmd.rkt" ...))
(define gracket-launcher-names ...)         ; GUI launchers
(define raco-commands '(("name" mod "desc" prominence) ...))  ; add raco subcommands
(define implies (list "subpkg" ...))        ; re-export deps as part of this pkg
(define update-implies (list ...))
(define test-timeouts '(("file.rkt" secs) ...))
```

A single-collection package keeps `info.rkt` at its root with `(define
collection "name")`. A `'multi` package has one `info.rkt` at the root and an
`info.rkt` per collection subdirectory.

## Package sources (what install/update accept)

```
name              a catalog name             ("threading-lib")
directory         a local path               (linked or copied)
git / github      "git://…", "https://github.com/user/repo[?path=…#branch]"
file / url        a .zip / .tgz / .plt archive, local or remote
```

## Reading manifests programmatically

```racket
(require setup/getinfo)
(get-info  (list "collect" ...))    ; -> info proc or #f, by collection
(get-info/full dir)                 ; -> info proc or #f, by directory
((get-info/full "/path") 'deps)     ; read a field (2nd arg: default thunk)
```
