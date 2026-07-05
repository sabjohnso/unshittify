# Macro / syntax-parse Reference — exact signatures and grammars

Companion to SKILL.md. Source: docs.racket-lang.org/syntax/ (`syntax/parse`)
and the Reference §"Macros". Checked against Racket v9.1 [cs].

## Defining macros

```racket
(define-syntax (name stx) body ...)       ; transformer: stx -> syntax
(define-syntax name transformer-expr)     ; transformer-expr at phase 1

;; from syntax/parse/define:
(define-syntax-parse-rule (name . pattern) pattern-directive ... template)
  ; one clause, like syntax-rules + syntax classes + auto errors
(define-syntax-parser name parse-option ... clause ...)
  ; = (define-syntax (name stx) (syntax-parse stx clause ...))
```

## syntax-parse

```racket
(syntax-parse stx-expr parse-option ... clause ...+)

  parse-option = #:context context-expr
               | #:literals (literal-id ...)
               | #:datum-literals (datum-id ...)
               | #:literal-sets (literal-set ...)
               | #:conventions (conv ...)
               | #:disable-colon-notation

  clause = (syntax-pattern pattern-directive ... body ...+)
```

### Pattern directives (in a clause or syntax-class pattern)

```racket
#:declare pvar syntax-class-or-(syntax-class arg ...)   ; same as pvar:sc
#:with     syntax-pattern stx-expr      ; match expr's value, bind new pvars
#:attr     attr-id expr                 ; bind attribute to a value (any/c)
#:when     condition-expr               ; backtrack unless true
#:fail-when     condition-expr message-expr   ; fail (cut) when true
#:fail-unless   condition-expr message-expr   ; fail (cut) when false
#:cut                                    ; commit: no backtracking past here
#:do [defn-or-expr ...]                  ; run side effects / local defs
#:post action-pattern
#:and  pattern
```

## Syntax-pattern forms

```racket
literal-id                 ; matches a #:literals identifier by binding
(~datum datum)             ; matches that exact datum by sexp equality
(~literal id)              ; matches an identifier bound the same as id

pvar                       ; binds, matches anything
pvar:syntax-class          ; binds + checks; class attrs become pvar.attr
(~var pvar syntax-class)   ; long form of pvar:syntax-class
_                          ; matches anything, binds nothing

(H-pat ... . pat)          ; list/improper; H-pat may be a head pattern
(pat ...)                  ; proper list
(pat ...+)                 ; one or more
(pat ellipsis . rest)      ; ellipsis = literal ...

(~and pat ...)             ; all must match the same term
(~or* pat ...)             ; any one (this is EllipsisCountPattern-safe;
                           ;          bare ~or is deprecated)
(~not pat)                 ; matches iff pat does NOT
(~seq pat ...)             ; head pattern: an inline run of terms
(~optional H-pat maybe-defaults)        ; H-pat or nothing
   maybe-defaults = #:defaults ([attr-id def-expr] ...)
(~once H-pat maybe-msg)                  ; exactly once within ellipsis
(~between H-pat min max maybe-msg)       ; between min and max occurrences
(~bind [attr-id expr] ...)               ; bind attributes unconditionally
(~parse syntax-pattern stx-expr)         ; like #:with, inside a pattern
(~fail maybe-when message-expr)          ; force a failure
(~describe maybe-opt expr pat)           ; relabel pat's role in errors
(~commit pat)  (~delimit-cut pat)        ; control backtracking scope
(~rest pat)                              ; bind the tail
```

Head patterns (`H-pat`) appear where a *sequence* of terms is consumed:
`~seq`, `~optional`, `~once`, `~between`, splicing-class references.

## Template forms (for #' and #`)

```racket
pvar                       ; substitute the captured syntax
(tmpl ...)                 ; ellipsis iteration (depth must match pvar depth)
(~? tmpl)                  ; emit tmpl only if its attrs are all present
(~? tmpl alt)              ; else emit alt
(~@ tmpl ...)              ; splice into the enclosing sequence
(~@ . tmpl)
#`tmpl  #,expr  #,@list    ; quasisyntax / unsyntax / unsyntax-splicing
(syntax/loc loc-stx tmpl)  ; copy srcloc onto the result
(quasisyntax/loc loc-stx tmpl)
```

## define-syntax-class / define-splicing-syntax-class

```racket
(define-syntax-class name-or-(name . formals) class-option ...
  (pattern syntax-pattern pattern-directive ...) ...+)

(define-splicing-syntax-class name-or-(name . formals) class-option ...
  (pattern splicing-pattern pattern-directive ...) ...+)
  ; patterns here are head patterns (use ~seq); referenced pvars splice.

  class-option = #:description string-or-expr   ; noun phrase for errors
               | #:opaque                        ; report as one unit
               | #:attributes (attr-decl ...)    ; declare exported attrs
               | #:commit | #:no-delimit-cut
  attr-decl    = attr-id | (attr-id depth)
```

Attributes: every pattern variable bound in a `pattern` is exported as an
attribute of the class. From outside, `p:cls` exposes them as `p.attr`. An
attribute with ellipsis depth N must be used under N ellipses in templates.
`(attribute attr-id)` yields its value (syntax, list, or arbitrary for
`#:attr`); `this-syntax` is the whole matched term inside a pattern.

## Common built-in syntax classes (syntax/parse)

```
id (identifier)   keyword    str (string)    char     boolean
nat               integer    number          exact-integer
exact-nonnegative-integer    exact-positive-integer
expr      ; any term usable as an expression (not a definition keyword)
```

`expr` does not check that the term *is* a valid expression — only that it
is not obviously a non-expression; full checking happens when the output is
expanded.

## racket/syntax and syntax helpers

```racket
(format-id    ctx fmt-string v ... [#:source #:props #:cert]) -> identifier?
   ; ~a in fmt splices each v (id/string/symbol/number); scopes from ctx
(format-symbol fmt-string v ...) -> symbol?
(generate-temporaries stx-pair-or-list) -> (listof identifier?)
(with-syntax ([pat stx-expr] ...) body ...+)   ; like #:with, expression form
(syntax->list stx) -> (or/c (listof syntax?) #f)
(syntax->datum stx) -> datum         (datum->syntax ctx datum [srcloc props])
(syntax-e stx)      ; one level of unwrapping
(check-duplicate-identifier (listof identifier?)) -> (or/c identifier? #f)
```

## raise-syntax-error

```racket
(raise-syntax-error name message [expr sub-expr extra-sources ...]) -> any
   name     : (or/c symbol? #f)     ; #f = use the macro/form name from expr
   message  : string?
   expr     : the whole form to blame  (shown as "in:")
   sub-expr : the specific bad term    (shown as "at:")
```

`syntax-parse` raises `exn:fail:syntax` automatically on no-match, using the
relevant `#:description`/built-in class name; prefer that to manual checks.

## Phases

```racket
(require (for-syntax mod ...))   ; bindings at phase 1 (transformer time)
(begin-for-syntax defn ...)      ; phase-1 definitions in this module
(require (for-template mod ...)) ; phase -1, for code a macro emits to require
(define-for-syntax id expr)      ; = (begin-for-syntax (define id expr))
```

Transformer code (the macro body, syntax classes, helper functions it calls)
lives at phase 1, so `syntax/parse`, `racket/syntax`, and `racket/base` for
that code must be required `for-syntax`.
