---
description: Write or edit Scribble documentation for Racket packages — .scrbl manuals, defproc/defform API docs, live examples, info.rkt scribblings entries, and building docs with raco setup. Use when documenting a Racket library, editing a .scrbl file, or fixing doc-build errors (unlinked identifiers, sandbox failures, dependency warnings).
---

# Writing Scribble Documentation

Scribble is Racket's documentation language. A library manual is a `.scrbl`
file in `#lang scribble/manual`, built by `raco setup`, with identifiers
hyperlinked through `for-label` requires. For exact form signatures, the
`info.rkt` grammar, and style-guide vocabulary, read `reference.md` in this
skill directory.

## Workflow

1. Confirm `info.rkt` has a `scribblings` entry and `"scribble-lib"` +
   `"racket-doc"` in `build-deps`.
2. Write/edit the `.scrbl` file (skeleton below).
3. Build: `raco setup <collection>` (e.g. `raco setup mtt`). Errors in
   `@examples` blocks or undeclared doc dependencies fail the build here.
4. View: `raco docs <name>`, or open the rendered
   `doc/<name>/index.html` under the collection.

## Minimal manual skeleton

```racket
#lang scribble/manual
@(require scribble/example
          (for-label racket/base my-lib))

@(define my-eval (make-base-eval '(require my-lib)))

@title{My-Lib: Frobnication Tools}
@author{Author Name}
@defmodule[my-lib]

@defproc[(frob [v any/c] [#:count n exact-nonnegative-integer? 1]) string?]{
 Returns the frobnication of @racket[v], repeated @racket[n] times.
 @examples[#:eval my-eval
           (frob 'cow)
           (eval:error (frob 'cow #:count -1))]}
```

Matching `info.rkt`:

```racket
(define scribblings '(("scribblings/my-lib.scrbl" ())))
(define build-deps '("scribble-lib" "racket-doc"))
```

## The @-syntax in one table

`@cmd[racket-args]{text body}` reads as `(cmd racket-args "text body")`.
All three parts are optional; `[...]` is Racket mode, `{...}` is text mode,
and they nest.

| Source                  | Reads as                     |
|-------------------------|------------------------------|
| `@foo{blah}`            | `(foo "blah")`               |
| `@foo[1 #:k 2]{blah}`   | `(foo 1 #:k 2 "blah")`       |
| `@foo`                  | `foo`                        |
| `@(+ 1 2)`              | `(+ 1 2)` (escape to Racket) |
| `@|name|`               | `name`, delimited inline     |
| `@"@"`                  | literal `@`                  |
| `@;{ ... }`             | block comment                |
| `@;`                    | comment to EOL, joins lines  |

Multi-line `{...}` bodies become multiple string arguments with `"\n"`
between them; indentation relative to the leftmost line is preserved.
Braces must balance in text mode — use `@"{"` or `|{ ... }|` fences
(inside fences, `@` and `}` are literal; escapes are written `|@`).

## The rules that prevent rework

- **`for-label` is what makes links work.** Every module whose bindings
  the prose mentions must appear in `@(require (for-label ...))` —
  otherwise `@racket[id]` typesets unlinked and `defproc` entries are not
  link targets. Resolve name collisions with `only-in`/`except-in`.
- **`@defmodule` takes the collection path** (`my-lib/helper`), never a
  relative filename. At most one per section; it associates every
  `defproc`/`defform` in the section with that module.
- **Code typesetting — pick by content:** `racketblock` for S-expression
  datums (linked via for-label, layout preserved); `racketmod` to show a
  `#lang` line; `codeblock` for string content in any language (lexer
  coloring, no links); `verbatim` for plain fixed-width text. Inline:
  `@racket[...]` for bound code, `@racketresult[...]` for values,
  `@litchar{...}` for literal characters.
- **Live examples:** define one evaluator at the top of the file with
  `(make-base-eval '(require my-lib))` and pass it via
  `@examples[#:eval my-eval ...]`. The doc's own requires are invisible to
  the sandbox — require inside the evaluator. Wrap expected failures in
  `(eval:error ...)`; an unwrapped exception fails the whole doc build.
  `(eval:check expr expected)` asserts; `#:hidden` runs setup silently.
- **Sections and cross-refs:** `@section[#:tag "x"]` … `@secref["x"]`.
  Cross-manual: `@secref[#:doc '(lib "scribblings/guide/guide.scrbl") "tag"]`
  — but binding links via `@racket[id]` are usually better. Multi-page
  rendering needs `'multi-page` in the scribblings flags and benefits from
  `@title[#:style '(toc)]` + `@local-table-of-contents[]`.
- **Terminology:** introduce a term with `@deftech{...}` (indexed, link
  target), reference it with `@tech{...}`. `defterm` only italicizes —
  prefer `deftech`/`tech`.
- **Multiple signatures for one binding** use `defproc*`/`defform*`, not
  repeated `defproc`s (Scribble warns on duplicate definition points).
  `deftogether` is for distinct-but-paired bindings sharing one prose body.
- **Dependency hygiene:** linking into another manual (even via for-label)
  requires its doc package (e.g. `"racket-doc"`) in `build-deps`, or
  `raco setup --check-pkg-deps` fails.
- The `.scrbl` filename becomes the output directory name and must be
  unique across all installed docs — name it after the package, not
  `manual.scrbl`.

## Prose conventions (Racket style guide)

Start a `defproc` body with "Returns ..." or "Produces ..." — never
"This function ...". Refer to arguments by their names with `@racket[arg]`.
Prefix meta-variables in inline code with `_`:
`@racket[(_rator-expr _rand-expr ...)]`. Use `....` (four dots) for elided
code, since `...` means repetition. Give every function an `@examples`
block with real words, not foo/bar. End with
`@history[#:added "1.0"]` when versions matter. Full vocabulary rules are
in `reference.md`.
