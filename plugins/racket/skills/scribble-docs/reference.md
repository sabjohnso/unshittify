# Scribble Reference: Exact Signatures and Grammars

This file accompanies `SKILL.md`. The sources are docs.racket-lang.org/scribble/ and the
Racket Style Guide §5 ("Scribbling Documentation"). The forms and the command-line
flags were checked against Racket v9.1 [cs].

## scribble/manual definition forms

```racket
(defproc options prototype result-contract-expr-datum maybe-value pre-flow ...)
  prototype = (id arg-spec ...) | (prototype arg-spec ...)   ; curried
  arg-spec  = (arg-id contract-expr-datum)                   ; required
            | (arg-id contract-expr-datum default-expr)      ; optional
            | (keyword arg-id contract-expr-datum)           ; keyword
            | (keyword arg-id contract-expr-datum default-expr)
            | ellipses                                       ; ... = zero or more of the preceding
            | ellipses+                                      ; ...+ = one or more of the preceding
  options: #:kind, #:link-target?, #:id [src-id dest-id-expr], #:value

(defproc* options ([prototype result-contract-expr-datum maybe-value] ...+)
          pre-flow ...)
  ; one box with several calling cases. Use it for one binding with several arities

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
  ; defstruct* documents (struct ...). Plain defstruct documents define-struct
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
  ; Put it at the end of a defproc/defform body. The version is the version of
  ; the package, as the enclosing defmodule shows. The changed text is a
  ; capitalized fragment that ends in a period.
```

## defmodule

```racket
(defmodule mod-path option ...)
  options: #:multi (spec ...), #:lang, #:reader, #:require-form,
           #:no-declare, #:use-sources (mod ...), #:link-target?,
           #:indirect, #:packages (pkg ...)
```

- `mod-path` is the absolute collection path. `#:lang` shows a `#lang`
  line instead of a `require` line (you cannot use `#:lang` and `#:reader`
  together). An empty `#:packages ()` hides the package name.
- It expands to `declare-exporting`. To supply your own, use `#:no-declare`.

## Code typesetting

```racket
(racket datum ...)                 ; inline, linked via for-label
(racketblock [#:escape esc] datum ...)  ; block. The layout stays. The escape is unsyntax
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
`(code:contract ...)`, `(code:hilite datum)`; `_id` appears as a
meta-variable. `racketblock` can normalize literals (`2/4` → `1/2`). Use
`codeblock` when the exact source text matters.

## Sections, cross-references, terms

```racket
@section[#:tag "x"]{...}  @subsection{...}  @subsubsection{...}
(secref tag [#:doc module-path #:tag-prefixes prefixes #:underline? u?])
(other-doc module-path)            ; link to a whole manual
(racketlink id pre-content ...)    ; link from any text to the docs of a binding

(deftech pre-content ... [#:key key #:normalize? n? #:style? s?])
(tech pre-content ... [#:key key #:normalize? n? #:doc mod #:tag-prefixes p])
```

- Cross-manual examples: `@secref[#:doc '(lib "scribblings/reference/reference.scrbl") "pairs"]`,
  `@tech[#:doc '(lib "scribblings/reference/reference.scrbl")]{blame object}`.
- Racket normalizes `deftech` keys. It folds the case, changes a trailing `ies`
  to `y`, and drops a trailing `s`. Therefore `@tech{binding}` finds
  `@deftech{bindings}`. To inflect a word, add the suffix after the closing
  brace: `@tech{bind}ing`.
- For multi-page table-of-contents (TOC) pages, use `@title[#:style '(toc)]` and
  `@local-table-of-contents[]`. LaTeX ignores `@local-table-of-contents[]`.
  LaTeX does not ignore plain `table-of-contents`.
- For a multi-file manual, use `@include-section["sub.scrbl"]`. Each sub-file has
  its own `#lang scribble/manual` and a `@title`. The `@title` becomes the section.

## Lists and basic blocks

```racket
(itemlist itm ... [#:style style])   ; #:style 'ordered numbers the items
(item pre-flow ...)
```

Put the items in the bracket position of Racket mode:
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

- If there is no `#:eval`, the form uses a fresh `make-base-eval` and assumes
  `#:once`. The form closes the evaluator after the block. With `#:eval`, the
  evaluator stays open across blocks.
- Special datums: `(eval:error datum)` expects an exception.
  `(eval:alts show-datum eval-datum)` shows one datum and evaluates the other.
  `(eval:check eval-datum expect-datum)` asserts equality.
  `(eval:result content [out err])` and `(eval:results ...)` fake results.
  The last special datum is `(eval:no-prompt datum ...)`.
- `#:label #f` drops the "Examples:" label. `#:lang 'typed/racket/base`
  selects another language.
- Sandbox: `make-base-eval` sets `sandbox-output`/`sandbox-error-output`
  to `'string` and disables resource limits. The sandbox restricts the
  filesystem and the network. The documented modules must be loadable when the
  documentation is built.
- `scribble/eval` (`interaction`, `interaction-eval`, ...) is legacy.
  New documents use `scribble/example`.

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
name     = string | #f      ; overrides the name of the output directory (must be unique)
```

- The common flag is `'multi-page`. The other flags are: `'main-doc 'user-doc 'depends-all
  'depends-all-main 'depends-all-user 'always-run 'no-depend-on
  'main-doc-root 'user-doc-root 'keep-style 'no-search 'every-main-layer`.
- The category symbols are: `'getting-started 'language 'tool 'gui-library
  'net-library 'parsing-library 'tool-library 'interop 'library` (default)
  `'legacy 'experimental 'other 'omit` (hidden and not indexed) `'omit-start`
  (hidden, but indexed). A string is a literal category label.
- Example of a full entry:
  `(define scribblings '(("scribblings/my-lib.scrbl" (multi-page) (library) "my-lib")))`

## Building and rendering

```bash
raco setup <collection>          # build docs for one collection
raco setup --doc-index <coll>    # also rebuild the doc index
raco setup --check-pkg-deps --unused-pkg-deps <coll>
raco setup --doc-pdf <dir>       # PDFs
raco docs <term>                 # search/open local docs
scribble file.scrbl              # standalone HTML (single page)
scribble --htmls file.scrbl      # a directory with one page for each top section
scribble --pdf|--latex|--markdown|--text file.scrbl
scribble --dest <dir> --dest-name <fn> file.scrbl
scribble ++xref-in setup/xref load-collections-xref file.scrbl
  # standalone render. It resolves links into installed docs
```

The rendered package documentation goes to `doc/<name>/index.html` under the
collection (user scope) or the installation `doc` directory (installation scope).

## scribble/srcdoc (documentation in the source, brief)

Write the contracts and the documentation in the implementation module, with
`proc-doc/names`, `proc-doc`, `thing-doc`, and `form-doc` inside `provide`.
Use `(require (for-doc ...))` for the bindings that the documentation needs.
They collect in a `srcdoc` submodule and add no run-time cost. The manual gets
them with `include-extracted` of `scribble/extract` (or `provide-extracted` and
`include-previously-extracted`). `provide/doc` is the legacy spelling.

## Style guide vocabulary (Racket Style Guide §5)

- Start each body with "Returns ..." or "Produces ...". The subject is
  implicit. Never write "This function ...".
- Write "form", not "expression", when definitions are allowed. Write
  "sub-form", not "argument", inside syntactic forms. Write "function", not
  "procedure". Write "identifier" for syntax, never "variable" or "symbol".
  Write "sequence of sub-forms", not "list of sub-forms".
- Do not use a predicate as a noun. Write "a path or string", not "a path-string?".
- Meta-variable conventions: `id` identifiers, `expr` expressions,
  `body ...+` internal-definition positions, `v` any value, `x` number,
  `lst` list, `proc` procedure.
- In `defform`, put literal identifiers in `#:literals`. Use `#:contracts` for
  run-time constraints only. Put the syntactic shape in `#:grammar`.
- `....` (four dots) elides code. `...` means repetition. Write an em dash as
  `---` without surrounding spaces. Do not write "above" or "below". Use a link
  instead.
- In a title, capitalize all words except articles, prepositions, and conjunctions.
- Give every function and form an `@examples` block with realistic data.
- Prefer prose ("x is like y, except ...") to duplicated boxes. Use
  `deftogether` only for paired bindings.

## Pitfall checklist

- If an identifier has no link, the `for-label` require for its module is missing.
- If `raco setup` gives a dependency error, add the doc package of the target
  manual (e.g. `"racket-doc"`) to `build-deps`.
- If the documentation build stops inside `@examples`, wrap the expected errors
  in `eval:error`. Require the library *inside* the evaluator.
- If two documents claim one output directory, rename the `.scrbl` file or set
  the `name` field in the scribblings entry.
- If there is a duplicate-definition warning, collapse the repeated `defproc`
  forms into `defproc*` (or `defform*`).
- If `racketblock` renders a literal wrongly, switch to `codeblock`
  (string-based, exact).
