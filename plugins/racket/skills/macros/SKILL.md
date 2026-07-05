---
name: macros
description: Write Racket macros with syntax-parse — pattern matching on syntax, syntax classes, ellipses, hygiene, phase levels, and good compile-time error messages. Covers define-syntax, syntax-parse, define-syntax-parse-rule, define-syntax-class/define-splicing-syntax-class, templates (#', ~?, ~@), format-id, and raise-syntax-error. Use when writing or debugging a Racket macro, designing new syntactic forms, or choosing between syntax-rules and syntax-parse.
---

# Racket Macros with syntax-parse

A macro is a compile-time function from syntax to syntax. `syntax-parse`
(from `syntax/parse`) is the tool for non-trivial macros: it matches input
against patterns, validates with syntax classes, and produces precise error
messages automatically. For exact grammars, the full pattern/directive
lists, and built-in syntax classes, read `reference.md` in this skill
directory.

## Reach for the right tool

- **A function** if the arguments can be evaluated normally — most of the
  time. Macros only when you must control evaluation order, bind names, or
  read the *shape* of unevaluated code.
- **A reader macro** ([[reader-macros]]) if the change is *lexical* — a new
  bracket or sigil the reader must handle before s-expressions exist.
- **`define-syntax-parse-rule`** (from `syntax/parse/define`) for a simple
  one-pattern rewrite — like `syntax-rules` but with syntax-class
  annotations and good errors.
- **Full `syntax-parse`** when you need multiple clauses, side conditions,
  computed sub-syntax, or custom validation.

Avoid bare `syntax-rules`/`syntax-case` for new code: they give worse errors
and lack syntax classes. Keep them only when editing existing code in that
style.

## One-pattern macros

```racket
(require syntax/parse/define)

(define-syntax-parse-rule (swap! a:id b:id)
  (let ([tmp a]) (set! a b) (set! b tmp)))
```

The `:id` annotation means a non-identifier argument is rejected at compile
time with "expected identifier", pointing at the offending term.

## Full syntax-parse macros

A `syntax-parse` macro receives the whole call as `stx`, matches it against
clauses, and returns a syntax object (a `#'` template):

```racket
(require (for-syntax racket/base syntax/parse racket/syntax))

(define-syntax (my-let stx)
  (syntax-parse stx
    [(_ (b:binding ...) body:expr ...+)
     #:fail-when (check-duplicate-identifier (syntax->list #'(b.name ...)))
                 "duplicate binding name"
     #:with (getter ...) (map (lambda (id) (format-id id "get-~a" id))
                              (syntax->list #'(b.name ...)))
     #'(let ([b.name b.rhs] ...)
         (define (getter) b.name) ...
         body ...)]))
```

- `_` ignores the macro name in the head position.
- `b:binding` annotates pattern variable `b` with the syntax class
  `binding` (below); `b.name`/`b.rhs` reach its **attributes**.
- `...` is ellipsis: `(b:binding ...)` matches zero or more; `body ...+`
  matches one or more.
- `#:fail-when cond msg` aborts with `msg` (located at `cond`'s syntax) when
  `cond` is truthy — here, duplicate-name detection.
- `#:with pat expr` binds new pattern variables from a computed value, so
  the template can splice `(getter ...)`.

## Syntax classes

Factor recurring patterns and their validation into a class; its `pattern`
clauses bind **attributes** that callers reach with dotted names. Define
classes at phase 1 (`begin-for-syntax` or a `for-syntax` module):

```racket
(begin-for-syntax
  (define-syntax-class binding
    #:description "a [id expr] binding pair"
    (pattern [name:id rhs:expr])))
```

A **splicing** class matches a run of terms spread across the enclosing
list (for optional keyword arguments), via `define-splicing-syntax-class`
and `~seq`:

```racket
(begin-for-syntax
  (define-splicing-syntax-class maybe-default
    (pattern (~seq #:default d:expr) #:attr value #'d)
    (pattern (~seq)                  #:attr value #'#f)))
```

`#:description` is what shows up in the auto-generated error when the class
fails to match — write it as a noun phrase.

## Pattern language essentials

| Form                         | Matches                                                |
|------------------------------|--------------------------------------------------------|
| `x:id` `e:expr` `n:nat`      | one term, validated by a built-in syntax class         |
| `(p ...)` / `(p ...+)`       | ellipsis: zero-or-more / one-or-more                   |
| `(~optional p)`              | `p` or nothing; pair with `~?` in the template         |
| `(~seq a b)`                 | an in-line run of terms (splicing contexts)            |
| `(~or* p1 p2)`               | alternatives (use `~or*`; bare `~or` is deprecated)    |
| `(~and pa pb)`               | both patterns against the same term                    |
| `(~once p)` / `(~between p)` | cardinality constraints within ellipses                |
| `(~datum x)` / `(~literal x)`| match a literal datum / a literal *binding*            |
| `#:literals (else =>)`       | declare identifiers matched literally by name          |
| `(~bind [a #'v])`            | bind an attribute from the clause                      |

## Templates

A template builds the output syntax. `#'tmpl` is the common case;
`#\`tmpl`/`#,e`/`#,@es` (quasisyntax/unsyntax) splice in computed syntax.

- Ellipsis in templates: `(let ([b.name b.rhs] ...) ...)` iterates in step
  with the pattern's ellipsis depth.
- `(~? tmpl)` emits `tmpl` only if every `~optional`/`~bind` attribute in it
  is present; `(~? tmpl alt)` falls back to `alt`.
- `(~@ a b)` splices `a b` into the surrounding sequence, so
  `(list (~@ k v) ...)` flattens pairs to `k v k v ...`.
- `(syntax/loc stx tmpl)` copies source location from `stx` onto the output
  so errors point at the user's code, not the macro.

Compute fresh identifiers with `racket/syntax`:

```racket
(format-id ctx "get-~a" #'x)          ; -> #'get-x, scopes from ctx
(generate-temporaries #'(a b c))      ; -> 3 fresh, hygienic ids
```

## Hygiene

Identifiers a macro introduces are **invisible** to user code, and user
identifiers don't collide with the macro's. A `tmp` introduced by `swap!`
cannot capture a user `tmp` — correct by default. The flip side: a name the
macro defines (e.g. an internal `default`) is *not* visible to the user's
body unless you deliberately give it the user's scopes. To expose a name on
purpose, derive it from a user identifier with `format-id` (as `get-x`
above) — its lexical context comes from the `ctx` argument. Drop to
`syntax->datum`/`datum->syntax` only when you must move scopes by hand.

## Phases

Macro code runs one phase earlier than the program. Require its libraries
`for-syntax`, and put helper definitions used by the transformer in
`begin-for-syntax` or a `for-syntax`-required module:

```racket
(require (for-syntax racket/base syntax/parse racket/syntax))
```

Forgetting `for-syntax` yields "unbound identifier" for things like
`syntax-parse` or `format-id` at compile time.

## Error reporting

Let `syntax-parse` do the work first: a failed class match already produces
"expected <description>" located at the bad term. Add checks with
`#:fail-when`/`#:fail-unless`/`#:when`. Use `raise-syntax-error` for custom
messages tied to a sub-form:

```racket
(raise-syntax-error #f "expected a literal pair" stx #'x)
;; -> "<macro>: expected a literal pair  at: <x>  in: <stx>"
```

## Rules that prevent rework

- **Annotate pattern variables and write `#:description`.** Good errors are
  a side effect of describing your input; `x:id` beats `x` plus a manual
  check every time.
- **Clause order matters — most specific first.** `(_ x:expr)` matches
  almost anything; put narrower clauses (literals, fixed shapes) above it or
  they never fire.
- **Reach attributes by dotted name, don't re-destructure.** `b.name` from a
  `b:binding` class is already validated; pulling `b` apart again loses that.
- **Output through templates, not list surgery.** Build with `#'`/`#\`` and
  ellipses so hygiene and source locations are preserved; hand-built lists
  with `datum->syntax` discard both.
- **Trust hygiene; capture only on purpose.** If a macro-introduced binding
  "isn't visible," that's hygiene working — expose it via `format-id` from a
  user identifier rather than disabling hygiene.
- **`syntax/loc` for forms whose errors should blame the caller.** Wrap the
  output template so a downstream error points at the use site.
- **Require transformer libraries `for-syntax`.** `syntax/parse`,
  `racket/syntax`, and any helper module the macro body calls live at
  phase 1.
