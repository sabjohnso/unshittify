---
description: Write Racket macros with syntax-parse. Covers pattern matches on syntax, syntax classes, ellipses, hygiene, phase levels, and good compile-time error messages. Covers define-syntax, syntax-parse, define-syntax-parse-rule, define-syntax-class and define-splicing-syntax-class, templates (#', ~?, ~@), format-id, and raise-syntax-error. Use when you write or debug a Racket macro, when you design a new syntactic form, or when you choose between syntax-rules and syntax-parse.
allowed-tools: Read, Grep, Glob
---

# Racket macros with syntax-parse

A macro is a compile-time function from syntax to syntax. `syntax-parse`
(from `syntax/parse`) is the tool for a macro that is not trivial. It
matches the input against patterns, validates with syntax classes, and
produces precise error messages automatically. For the exact grammars, the
full lists of patterns and directives, and the built-in syntax classes, read
`reference.md` in this skill directory.

## Use the right tool

- **A function**, if the arguments can be evaluated normally. That is the
  usual case. Use a macro only when you must control the evaluation order,
  bind names, or read the *shape* of unevaluated code.
- **A reader macro** ([reader-macros](../reader-macros/SKILL.md)), if the
  change is *lexical*: a new bracket or sigil that the reader must handle
  before s-expressions exist.
- **`define-syntax-parse-rule`** (from `syntax/parse/define`) for a simple
  rewrite with one pattern. It is like `syntax-rules`, but with syntax-class
  annotations and good errors.
- **The full `syntax-parse`** when you need several clauses, side
  conditions, computed sub-syntax, or custom validation.

Avoid a bare `syntax-rules` or `syntax-case` in new code. They give worse
errors, and they have no syntax classes. Keep them only when you edit
existing code in that style.

## Macros with one pattern

```racket
(require syntax/parse/define)

(define-syntax-parse-rule (swap! a:id b:id)
  (let ([tmp a]) (set! a b) (set! b tmp)))
```

The `:id` annotation means that the compiler rejects an argument that is not
an identifier, with "expected identifier", and it points at the offending
term.

## Full syntax-parse macros

A `syntax-parse` macro gets the whole call as `stx`, matches it against the
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
- `b:binding` annotates the pattern variable `b` with the syntax class
  `binding` (below). `b.name` and `b.rhs` reach its **attributes**.
- `...` is an ellipsis. `(b:binding ...)` matches zero or more. `body ...+`
  matches one or more.
- `#:fail-when cond msg` aborts with `msg` (located at the syntax of `cond`)
  when `cond` is true. Here it detects a duplicate name.
- `#:with pat expr` binds new pattern variables from a computed value. So the
  template can splice `(getter ...)`.

## Syntax classes

Factor a recurrent pattern and its validation into a class. Its `pattern`
clauses bind **attributes** that a caller reaches with a dotted name. Define
a class at phase 1 (`begin-for-syntax`, or a module that is required
`for-syntax`):

```racket
(begin-for-syntax
  (define-syntax-class binding
    #:description "a [id expr] binding pair"
    (pattern [name:id rhs:expr])))
```

A **splicing** class matches a run of terms spread across the enclosing list
(for optional keyword arguments), through `define-splicing-syntax-class` and
`~seq`:

```racket
(begin-for-syntax
  (define-splicing-syntax-class maybe-default
    (pattern (~seq #:default d:expr) #:attr value #'d)
    (pattern (~seq)                  #:attr value #'#f)))
```

`#:description` is the text that appears in the automatic error when the
class does not match. Write it as a noun phrase.

## The essentials of the pattern language

| Form                          | Matches                                                 |
|-------------------------------|---------------------------------------------------------|
| `x:id` `e:expr` `n:nat`       | one term, validated by a built-in syntax class          |
| `(p ...)` / `(p ...+)`        | an ellipsis: zero or more / one or more                 |
| `(~optional p)`               | `p` or nothing. Pair it with `~?` in the template       |
| `(~seq a b)`                  | an inline run of terms (in a splicing context)          |
| `(~or* p1 p2)`                | alternatives (use `~or*`; a bare `~or` is deprecated)   |
| `(~and pa pb)`                | both patterns against the same term                     |
| `(~once p)` / `(~between p)`  | cardinality constraints inside an ellipsis              |
| `(~datum x)` / `(~literal x)` | a match on a literal datum / a literal *binding*        |
| `#:literals (else =>)`        | identifiers that match literally by name                |
| `(~bind [a #'v])`             | an attribute bound from the clause                      |

## Templates

A template builds the output syntax. `#'tmpl` is the common case.
`#\`tmpl`, `#,e`, and `#,@es` (quasisyntax and unsyntax) splice computed
syntax in.

- An ellipsis in a template: `(let ([b.name b.rhs] ...) ...)` iterates in
  step with the ellipsis depth of the pattern.
- `(~? tmpl)` emits `tmpl` only if every `~optional` or `~bind` attribute in
  it is present. `(~? tmpl alt)` falls back to `alt`.
- `(~@ a b)` splices `a b` into the sequence around it. So `(list (~@ k v)
  ...)` flattens the pairs to `k v k v ...`.
- `(syntax/loc stx tmpl)` copies the source location from `stx` onto the
  output. Then an error points at the code of the user, not at the macro.

Compute fresh identifiers with `racket/syntax`:

```racket
(format-id ctx "get-~a" #'x)          ; -> #'get-x, with the scopes of ctx
(generate-temporaries #'(a b c))      ; -> 3 fresh, hygienic identifiers
```

## Hygiene

An identifier that a macro introduces is **invisible** to the user code, and
a user identifier does not collide with the identifiers of the macro. A
`tmp` that `swap!` introduces cannot capture a user `tmp`. That is correct
by default. The other side: a name that the macro defines (for example an
internal `default`) is *not* visible to the body of the user, unless you
give it the scopes of the user on purpose. To expose a name on purpose,
derive it from a user identifier with `format-id` (as `get-x` above). Its
lexical context comes from the `ctx` argument. Drop to `syntax->datum` and
`datum->syntax` only when you must move scopes by hand.

## Phases

Macro code runs one phase earlier than the program. Require its libraries
`for-syntax`. Put the helper definitions that the transformer uses in
`begin-for-syntax` or in a module that is required `for-syntax`:

```racket
(require (for-syntax racket/base syntax/parse racket/syntax))
```

A missing `for-syntax` gives "unbound identifier" for a name such as
`syntax-parse` or `format-id` at compile time.

## Error reports

Let `syntax-parse` do the work first. A failed class match already produces
"expected <description>", located at the bad term. Add checks with
`#:fail-when`, `#:fail-unless`, and `#:when`. Use `raise-syntax-error` for a
custom message tied to a sub-form:

```racket
(raise-syntax-error #f "expected a literal pair" stx #'x)
;; -> "<macro>: expected a literal pair  at: <x>  in: <stx>"
```

## Rules that prevent rework

- **Annotate the pattern variables, and write a `#:description`.** Good
  errors are a side effect of a description of your input. `x:id` beats `x`
  plus a manual check every time.
- **The clause order matters. Put the most specific clause first.** `(_
  x:expr)` matches almost everything. Put the narrower clauses (literals,
  fixed shapes) above it. Otherwise they never fire.
- **Reach an attribute by its dotted name. Do not destructure again.**
  `b.name` from a `b:binding` class is already validated. A second
  destructure of `b` loses that.
- **Output through templates, not through list surgery.** Build with `#'`
  or `#\`` and ellipses, so the hygiene and the source locations are kept. A
  hand-built list with `datum->syntax` discards both.
- **Trust the hygiene. Capture only on purpose.** If a binding that the
  macro introduced "is not visible", the hygiene works. Expose it through
  `format-id` from a user identifier. Do not disable the hygiene.
- **Use `syntax/loc` for a form whose errors must blame the caller.** Wrap
  the output template, so a downstream error points at the use site.
- **Require the transformer libraries `for-syntax`.** `syntax/parse`,
  `racket/syntax`, and each helper module that the macro body calls are at
  phase 1.
