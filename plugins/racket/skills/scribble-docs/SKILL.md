---
description: Write or edit Scribble documentation for Racket packages. Covers .scrbl manuals, defproc and defform API docs, live examples, the scribblings entries of info.rkt, and a doc build with raco setup. Use when you document a Racket library, when you edit a .scrbl file, or when you fix a doc-build error (an unlinked identifier, a sandbox failure, a dependency warning).
allowed-tools: Bash(racket:*), Bash(raco:*), Read, Grep, Glob
---

# Write Scribble documentation

Scribble is the documentation language of Racket. A library manual is a
`.scrbl` file in `#lang scribble/manual`. `raco setup` builds it, and
`for-label` requires link the identifiers. For the exact form signatures,
the `info.rkt` grammar, and the style-guide vocabulary, read `reference.md`
in this skill directory.

## Workflow

1. Confirm that `info.rkt` has a `scribblings` entry, and that `build-deps`
   holds `"scribble-lib"` and `"racket-doc"`.
2. Write or edit the `.scrbl` file (the skeleton is below).
3. Build: `raco setup <collection>` (for example `raco setup mtt`). An error
   in an `@examples` block or an undeclared doc dependency fails the build
   here.
4. View: `raco docs <name>`, or open the rendered `doc/<name>/index.html`
   under the collection.

## A minimal manual skeleton

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

The matching `info.rkt`:

```racket
(define scribblings '(("scribblings/my-lib.scrbl" ())))
(define build-deps '("scribble-lib" "racket-doc"))
```

## The @-syntax in one table

`@cmd[racket-args]{text body}` reads as `(cmd racket-args "text body")`.
All three parts are optional. `[...]` is Racket mode, `{...}` is text mode,
and they nest.

| Source                | Reads as                       |
|-----------------------|--------------------------------|
| `@foo{blah}`          | `(foo "blah")`                 |
| `@foo[1 #:k 2]{blah}` | `(foo 1 #:k 2 "blah")`         |
| `@foo`                | `foo`                          |
| `@(+ 1 2)`            | `(+ 1 2)` (an escape to Racket) |
| `@|name|`             | `name`, delimited inline       |
| `@"@"`                | a literal `@`                  |
| `@;{ ... }`           | a block comment                |
| `@;`                  | a comment to the end of the line, and it joins the lines |

A `{...}` body with several lines becomes several string arguments with
`"\n"` between them. The indent relative to the leftmost line is kept.
Braces must balance in text mode. Use `@"{"` or `|{ ... }|` fences. Inside
a fence, `@` and `}` are literal, and an escape is written `|@`.

## Rules that prevent rework

- **`for-label` is what makes the links work.** Every module whose bindings
  the prose mentions must be in `@(require (for-label ...))`. Otherwise
  `@racket[id]` typesets with no link, and a `defproc` entry is not a link
  target. Resolve a name collision with `only-in` or `except-in`.
- **`@defmodule` takes the collection path** (`my-lib/helper`), never a
  relative filename. Use at most one per section. It associates every
  `defproc` and `defform` in the section with that module.
- **Code typesetting. Pick by content:** `racketblock` for S-expression
  datums (linked through for-label, with the layout kept). `racketmod` to
  show a `#lang` line. `codeblock` for string content in any language
  (lexer colors, no links). `verbatim` for plain fixed-width text. Inline:
  `@racket[...]` for bound code, `@racketresult[...]` for values,
  `@litchar{...}` for literal characters.
- **Live examples:** define one evaluator at the top of the file with
  `(make-base-eval '(require my-lib))`, and pass it through `@examples[#:eval
  my-eval ...]`. The sandbox does not see the requires of the doc itself.
  Require inside the evaluator. Wrap an expected failure in `(eval:error
  ...)`. An exception with no wrap fails the whole doc build. `(eval:check
  expr expected)` asserts. `#:hidden` runs a setup with no output.
- **Sections and cross-references:** `@section[#:tag "x"]` … `@secref["x"]`.
  Across manuals: `@secref[#:doc '(lib "scribblings/guide/guide.scrbl")
  "tag"]`. But a binding link through `@racket[id]` is usually better. A
  render with several pages needs `'multi-page` in the scribblings flags,
  and it benefits from `@title[#:style '(toc)]` plus
  `@local-table-of-contents[]`.
- **Terminology:** introduce a term with `@deftech{...}` (indexed, a link
  target), and refer to it with `@tech{...}`. `defterm` only sets italics.
  Prefer `deftech` and `tech`.
- **Several signatures for one binding** use `defproc*` or `defform*`, not
  repeated `defproc`s (Scribble warns on a duplicate definition point).
  `deftogether` is for distinct but paired bindings that share one prose
  body.
- **Doc dependencies:** a link into an other manual (also through for-label)
  requires its doc package (for example `"racket-doc"`) in `build-deps`.
  Otherwise `raco setup --check-pkg-deps` fails.
- The `.scrbl` filename becomes the name of the output directory, and it
  must be unique across all installed docs. Name it after the package, not
  `manual.scrbl`.

## Prose conventions (the Racket style guide)

Start a `defproc` body with "Returns ..." or "Produces ...". Never start
with "This function ...". Refer to the arguments by their names with
`@racket[arg]`. Put a `_` prefix on each meta-variable in inline code:
`@racket[(_rator-expr _rand-expr ...)]`. Use `....` (four dots) for elided
code, because `...` means repetition. Give every function an `@examples`
block with real words, not foo and bar. End with `@history[#:added "1.0"]`
when the versions matter. The full vocabulary rules are in `reference.md`.
