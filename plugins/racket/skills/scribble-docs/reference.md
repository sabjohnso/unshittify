# Scribble Reference — exact signatures and grammars

Companion to SKILL.md. Sources: docs.racket-lang.org/scribble/ and the
Racket Style Guide §5 ("Scribbling Documentation").

## scribble/manual definition forms

```racket
(defproc options prototype result-contract-expr-datum maybe-value pre-flow ...)
  prototype = (id arg-spec ...) | (prototype arg-spec ...)   ; curried
  arg-spec  = (arg-id contract-expr-datum)                   ; required
            | (arg-id contract-expr-datum default-expr)      ; optional
            | (keyword arg-id contract-expr-datum)           ; keyword
            | (keyword arg-id contract-expr-datum default-expr)
            | ellipses                                       ; ...  = 0+ of preceding
            | ellipses+                                      ; ...+ = 1+ of preceding
  options: #:kind, #:link-target?, #:id [src-id dest-id-expr], #:value

(defproc* options ([prototype result-contract-expr-datum maybe-value] ...+)
          pre-flow ...)
  ; one box, multiple calling cases — use for one binding with several arities

(defform options form-datum maybe-grammar maybe-contracts pre-flow ...)
  options: #:kind (default "syntax"), #:link-target?, #:id,
           #:literals (literal-id ...),
           #:grammar ([nonterm-id clause-datum ...+] ...),
           #:contracts ([subform-datum contract-expr-datum] ...)
(defform* options [form-datum ...+] maybe-grammar maybe-contracts pre-flow ...)
(defidform maybe-kind maybe-link id pre-flow ...)        ; identifier-only syntax

(defthing  options id contract-expr-datum maybe-auto-value pre-flow ...)
(defthing* options ([id contract-expr-datum maybe-auto-value] ...+) pre-flow ...)

(defstruct* maybe-link struct-name
            ([field contract-expr-datum field-opt ...] ...)
            struct-opt ... pre-flow ...)
  ; defstruct* documents (struct ...); plain defstruct documents define-struct
  field-opts:  #:mutable #:auto
  struct-opts: #:mutable #:prefab #:transparent #:inspector #f
               #:constructor-name #:extra-constructor-name #:omit-constructor

(defparam  maybe-link id arg-id contract-expr-datum maybe-auto-value pre-flow ...)
(defparam* maybe-link id arg-id in-contract out-contract maybe-auto-value pre-flow ...)
(defboolparam maybe-link id arg-id pre-flow ...)

(deftogether [def-expr ...+] pre-flow ...)   ; one box, shared prose body

(history clause ...+)
  clause = #:added version-expr
         | #:changed version-expr content-expr
  ; goes at the end of a defproc/defform body; version is the package's,
  ; per the enclosing defmodule. Changed text: capitalized fragment ending
  ; in a period.
```

## defmodule

```racket
(defmodule mod-path option ...)
  options: #:multi (spec ...), #:lang, #:reader, #:require-form,
           #:no-declare, #:use-sources (mod ...), #:link-target?,
           #:indirect, #:packages (pkg ...)
```

- `mod-path` is the absolute collection path. `#:lang` shows a `#lang`
  line instead of a `require` line (`#:lang` and `#:reader` are mutually
  exclusive). Empty `#:packages ()` suppresses the package name.
- Expands to `declare-exporting`; use `#:no-declare` to supply your own.

## Code typesetting

```racket
(racket datum ...)                 ; inline, linked via for-label
(racketblock [#:escape esc] datum ...)  ; block; layout preserved; escape = unsyntax
(RACKETBLOCK ...)                  ; escape is UNSYNTAX
(racketblock0 ...)                 ; no indentation inset
(racketinput datum ...)            ; REPL-prompt style
(racketmod [#:file f] [#:escape e] lang datum ...)  ; shows a #lang line
(racketresult datum ...)           ; result color, no links
(racketid datum)                   ; deliberately unbound identifier
(racketmodname id [#:indirect])    ; module path, typeset + linked
(litchar "text")                   ; literal characters
(codeblock [#:keep-lang-line? k] [#:indent i] [#:expand e] [#:context c]
           [#:line-numbers n] [#:line-number-sep s] str-expr ...+)
(code [#:lang lang-line] [#:expand e] [#:context c] str-expr ...+)
```

Special datums inside `racketblock`: `(code:line datum ...)`,
`(code:comment text)` → `;`, `(code:comment2 text)` → `;;`,
`(code:contract ...)`, `(code:hilite datum)`; `_id` typesets as a
meta-variable. `racketblock` may normalize literals (`2/4` → `1/2`) — use
`codeblock` when exact source text matters.

## Sections, cross-references, terms

```racket
@section[#:tag "x"]{...}  @subsection{...}  @subsubsection{...}
(secref tag [#:doc module-path #:tag-prefixes prefixes #:underline? u?])
(other-doc module-path)            ; link to a whole manual
(racketlink id pre-content ...)    ; arbitrary text → binding's docs

(deftech pre-content ... [#:key key #:normalize? n? #:style? s?])
(tech pre-content ... [#:key key #:normalize? n? #:doc mod #:tag-prefixes p])
```

- Cross-manual: `@secref[#:doc '(lib "scribblings/reference/reference.scrbl") "pairs"]`,
  `@tech[#:doc '(lib "scribblings/reference/reference.scrbl")]{blame object}`.
- `deftech` keys are normalized: case-folded, trailing `ies` → `y`,
  trailing `s` dropped — so `@tech{binding}` finds `@deftech{bindings}`.
  Suffix trick for inflection: `@tech{bind}ing`.
- Multi-page TOC pages: `@title[#:style '(toc)]` + `@local-table-of-contents[]`
  (ignored by LaTeX; plain `table-of-contents` is not).
- Multi-file manuals: `@include-section["sub.scrbl"]`; each sub-file has
  its own `#lang scribble/manual` and a `@title` that becomes the section.

## Lists and basic blocks

```racket
(itemlist itm ... [#:style style])   ; #:style 'ordered numbers the items
(item pre-flow ...)
```

Items go in the Racket-mode bracket position:
`@itemlist[@item{one} @item{two}]`. `itemize` is the legacy form.

## scribble/example

```racket
(examples option ... datum ...)
  option = #:eval eval-expr | #:once | #:escape escape-id | #:label label-expr
         | #:hidden | #:result-only | #:no-inset | #:no-prompt
         | #:preserve-source-locations | #:no-result | #:lang language-name

(make-base-eval [#:pretty-print? pp? #:lang lang] input-program ...)
(make-base-eval-factory mod-paths [#:pretty-print? pp? #:lang lang])
(make-eval-factory mod-paths [#:pretty-print? pp? #:lang lang])
(close-eval eval)
```

- No `#:eval` → fresh `make-base-eval`, `#:once` assumed (closed after the
  block). With `#:eval` the evaluator stays open across blocks.
- Special datums: `(eval:error datum)` expects an exception;
  `(eval:alts show-datum eval-datum)` shows one, evaluates the other;
  `(eval:check eval-datum expect-datum)` asserts equality;
  `(eval:result content [out err])` / `(eval:results ...)` fake results;
  `(eval:no-prompt datum ...)`.
- `#:label #f` drops the "Examples:" label. `#:lang 'typed/racket/base`
  selects another language.
- Sandbox: `make-base-eval` sets `sandbox-output`/`sandbox-error-output`
  to `'string` and disables resource limits; filesystem/network are
  restricted; the documented modules must be loadable at doc-build time.
- `scribble/eval` (`interaction`, `interaction-eval`, ...) is legacy —
  new docs use `scribble/example`.

## info.rkt scribblings grammar (from raco setup)

```
entry    = (list doc ...)
doc      = (list src-string)
         | (list src-string flags)
         | (list src-string flags category)
         | (list src-string flags category name)
         | (list src-string flags category name out-k)
         | (list src-string flags category name out-k order-n)
flags    = (list mode-symbol ...)
category = (list category-string-or-symbol)
         | (list category-string-or-symbol sort-number)
name     = string | #f      ; overrides output dir name (must be unique)
```

- Common flag: `'multi-page`. Others: `'main-doc 'user-doc 'depends-all
  'depends-all-main 'depends-all-user 'always-run 'no-depend-on
  'main-doc-root 'user-doc-root 'keep-style 'no-search 'every-main-layer`.
- Category symbols: `'getting-started 'language 'tool 'gui-library
  'net-library 'parsing-library 'tool-library 'interop 'library` (default)
  `'legacy 'experimental 'other 'omit` (hidden + unindexed) `'omit-start`
  (hidden, still indexed). A string is a literal category label.
- Typical full entry:
  `(define scribblings '(("scribblings/my-lib.scrbl" (multi-page) (library) "my-lib")))`

## Building and rendering

```bash
raco setup <collection>          # build docs for one collection
raco setup --doc-index <coll>    # also rebuild the doc index
raco setup --check-pkg-deps --unused-pkg-deps <coll>
raco setup --doc-pdf <dir>       # PDFs
raco docs <term>                 # search/open local docs
scribble file.scrbl              # standalone HTML (single page)
scribble --htmls file.scrbl      # directory, page per top section
scribble --pdf|--latex|--markdown|--text file.scrbl
scribble --dest <dir> --dest-name <fn> file.scrbl
scribble ++xref-in setup/xref load-collections-xref file.scrbl
  # standalone render that resolves links into installed docs
```

Rendered package docs land in `doc/<name>/index.html` under the collection
(user scope) or the installation `doc` directory (installation scope).

## scribble/srcdoc (in-source docs, brief)

Write contracts + docs in the implementation module with `proc-doc/names`,
`proc-doc`, `thing-doc`, `form-doc` inside `provide`, plus
`(require (for-doc ...))` for doc-time bindings; they accumulate in a
`srcdoc` submodule with no runtime cost. The manual pulls them in with
`scribble/extract`'s `include-extracted` (or `provide-extracted` +
`include-previously-extracted`). `provide/doc` is the legacy spelling.

## Style guide vocabulary (Racket Style Guide §5)

- Bodies start "Returns ..." / "Produces ..." — implicit subject, never
  "This function ...".
- "form" not "expression" when definitions are allowed; "sub-form" not
  "argument" inside syntactic forms; "function" over "procedure";
  "identifier" for syntax (never "variable"/"symbol"); "sequence of
  sub-forms" not "list of sub-forms".
- Avoid predicate-as-noun: say "a path or string", not "a path-string?".
- Meta-variable conventions: `id` identifiers, `expr` expressions,
  `body ...+` internal-definition positions, `v` any value, `x` number,
  `lst` list, `proc` procedure.
- `defform`: literal identifiers go in `#:literals`; `#:contracts` is for
  run-time constraints only — syntactic shape belongs in `#:grammar`.
- `....` (four dots) elides code; `...` means repetition. Em dash `---`
  without surrounding spaces. Don't write "above"/"below" — link instead.
- Titles capitalize all words except articles/prepositions/conjunctions.
- Every function and form gets an `@examples` block with realistic data.
- Prefer prose ("x is like y, except ...") over duplicated boxes;
  `deftogether` only for genuinely paired bindings.

## Pitfall checklist

- Unlinked identifier → missing `for-label` require for its module.
- `raco setup` dependency error → add the target manual's doc package
  (e.g. `"racket-doc"`) to `build-deps`.
- Doc build aborts inside `@examples` → wrap expected errors in
  `eval:error`; require the library *inside* the evaluator.
- Two docs claim one output dir → rename the `.scrbl` file or set the
  `name` field in the scribblings entry.
- Duplicate-definition warning → collapse repeated `defproc` into
  `defproc*` (or `defform*`).
- Wrong literal rendering in `racketblock` → switch to `codeblock`
  (string-based, exact).
