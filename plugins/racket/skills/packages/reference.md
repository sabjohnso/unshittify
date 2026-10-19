# raco / Packages Reference: commands and manifest fields

This file accompanies `SKILL.md`. The sources are docs.racket-lang.org/pkg/ and the `raco`
reference. The flags were checked against Racket v9.1 [cs] (`raco <cmd> --help`).

## raco pkg subcommands

```
raco pkg install [opt ...] [<src> ...]   ; install; no src => the current directory
raco pkg update  [opt ...] [<src> ...]   ; update the installed packages
raco pkg uninstall [opt ...] <name> ...  ; remove packages
                                         ; `raco pkg remove` runs this command
raco pkg new     <name>                  ; make the skeleton of a package directory
raco pkg show    [opt ...] [<name> ...]  ; list the installed packages
raco pkg create  [opt ...] <dir>         ; put a directory in an archive
raco pkg migrate <from-version>          ; install again the packages of another version
raco pkg config  [--set] <key> [<val>]   ; show or change the package configuration (e.g. catalogs)
raco pkg catalog-show <name> ...         ; query a catalog
raco pkg empty-trash
```

### install / update options

```
-t, --type <type>     file | dir | file-url | dir-url | git | git-url | github | name
-n, --name <name>     replace the inferred package name
--checksum <sum>      the expected or selected checksum
--deps <mode>         fail | force | search-ask | search-auto
--auto                = --deps search-auto (install missing deps without a prompt)
--update-deps         also update the dependencies (with search-* modes)
--link                link a directory source in place (default for a dir)
--static-link         link, and promise that the collections will not change
--copy                copy the source and do not link it
--clone <dir>         clone a git/github source to <dir> and link it
--source | --binary | --binary-lib   remove built / source / source+doc elements
--scope <s>           installation | user        (-i / -u shorthands)
-u, --user            for one user (the default scope)
-i, --installation    for all users of this Racket
-D, --no-docs         do not build the docs
--batch               no prompts
-j, --jobs <n>        number of parallel jobs
-a, --all             (update) update all installed packages
--dry-run             (update) show what will change
```

### create options

```
--format <fmt>        zip (default) | tgz | plt   (archive format)
--manifest            write a directory manifest and not an archive
--original <pkg>      record <pkg> as the original package source
--dest <dir>          output directory
```

## raco setup

```
raco setup [opt ...] [<collection> ...]   ; build everything if no target
  -l <collection> ...   set up only these collections
  --pkgs <pkg> ...      set up the collections in these packages
  --check-pkg-deps      make sure deps / build-deps are correct
  -c, --clean           first delete the existing compiled files
  -D, --no-docs         do not build the documentation
  --doc-index           build the doc index again
  --tidy                remove references to removed items
  -j, --jobs <n>        number of parallel jobs (also --workers)
  --recompile-only      fail if anything must compile from source
```

## raco make / test / exe / distribute

```
raco make [opt ...] <file> ...            ; compile to compiled/*.zo
  -j <n>            run in parallel
  --disable-inline  ...

raco test [opt ...] <file-or-target> ...  ; run test submodules
  -c, --collection      use the arguments as collections
  -p, --package         use the arguments as packages
  -s, --submodule <n>   run submodule <n> (default: test)
  -j, --jobs <n>        run in parallel
  --timeout <secs>      timeout for each test
  -t, --table           show a summary table
  -e, --check-stderr    fail if a test writes to stderr
  -q, --quiet           show less output

raco exe [opt ...] <file>                 ; standalone executable
  -o <file>             name of the output
  --gui                 build a GUI (racket/gui) executable
  -l, --launcher        make a launcher (it uses the installed collections and does not embed them)
  --collects-dest <dir> write the embedded collections to <dir>
  --embed-dlls          embed DLLs (Windows)
  --ico / --icns <f>    set the icon
  --cs / --3m / --cgc   choose the VM variant

raco distribute <dest-dir> <exe> ...      ; put the exe and the libraries in a bundle to ship
```

## info.rkt fields (#lang info)

```racket
(define collection name-string-or-'multi)  ; the require path, or 'multi for many
(define deps        (list dep ...))         ; dependencies at run time
(define build-deps  (list dep ...))         ; dependencies for docs and tests
   dep = "pkg-name"
       | (list "pkg-name" #:version "x.y")
       | (list "pkg-name" #:platform platform-spec)
(define version     "x.y")                  ; version of the package (semantic)
(define pkg-desc    "one line")             (define pkg-authors '(id ...))
(define license     '(Apache-2.0 OR MIT))
(define scribblings '(("path.scrbl" (flags ...)) ...))   ; see scribble-docs
(define compile-omit-paths (list "p" ...))  ; or 'all
(define compile-omit-files (list "f.rkt" ...))
(define test-omit-paths    (list "p" ...))  ; or 'all
(define test-include-paths ...)
(define racket-launcher-names     (list "cmd" ...))      ; install command-line launchers
(define racket-launcher-libraries (list "cmd.rkt" ...))
(define gracket-launcher-names ...)         ; GUI launchers
(define raco-commands '(("name" mod "desc" prominence) ...))  ; add raco subcommands
(define implies (list "subpkg" ...))        ; export the deps again as part of this pkg
(define update-implies (list ...))
(define test-timeouts '(("file.rkt" secs) ...))
```

A single-collection package has `info.rkt` at its root with `(define
collection "name")`. A `'multi` package has one `info.rkt` at the root. It also has an
`info.rkt` in each collection subdirectory.

## Package sources (the sources that install and update accept)

```
name              a catalog name             ("threading-lib")
directory         a local path               (linked or copied)
git / github      "git://…", "https://github.com/user/repo[?path=…#branch]"
file / url        a .zip / .tgz / .plt archive, local or remote
```

## Reading manifests from a program

```racket
(require setup/getinfo)
(get-info  (list "collect" ...))    ; -> info proc or #f, for a collection
(get-info/full dir)                 ; -> info proc or #f, for a directory
((get-info/full "/path") 'deps)     ; read a field (2nd arg: default thunk)
```
