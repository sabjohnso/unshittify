# Macro and syntax-parse Reference: exact signatures and grammars

This file accompanies `SKILL.md`. The source is docs.racket-lang.org/syntax/
(`syntax/parse`) and the Reference section "Macros". The text was checked
against Racket v9.1 [cs].

## Defining macros

```racket
(define-syntax (name stx) body ...)       ; transformer: stx -> syntax
(define-syntax name transformer-expr)     ; transformer-expr runs at phase 1

;; from syntax/parse/define:
(define-syntax-parse-rule (name . pattern) pattern-directive ... template)
  ; one clause. It is like syntax-rules, with syntax classes and automatic errors
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
#:with     syntax-pattern stx-expr      ; match the value of expr and bind new pvars
#:attr     attr-id expr                 ; bind the attribute to a value (any/c)
#:when     condition-expr               ; backtrack unless the condition is true
#:fail-when     condition-expr message-expr   ; fail (cut) if the condition is true
#:fail-unless   condition-expr message-expr   ; fail (cut) if the condition is false
#:cut                                    ; commit. The parser does not backtrack past this point.
#:do [defn-or-expr ...]                  ; run side effects or local definitions
#:post action-pattern
#:and  pattern
```

## Syntax-pattern forms

```racket
literal-id                 ; matches a #:literals identifier by binding
(~datum datum)             ; matches that exact datum by sexp equality
(~literal id)              ; matches an identifier bound the same as id

pvar                       ; binds and matches any term
pvar:syntax-class          ; binds and checks. Class attributes become pvar.attr
(~var pvar syntax-class)   ; long form of pvar:syntax-class
_                          ; matches any term and binds nothing

(H-pat ... . pat)          ; list or improper list. H-pat can be a head pattern
(pat ...)                  ; proper list
(pat ...+)                 ; one or more
(pat ellipsis . rest)      ; the ellipsis is the literal ...

(~and pat ...)             ; all must match the same term
(~or* pat ...)             ; any one. This is safe for EllipsisCountPattern.
                           ;          The bare ~or is deprecated.
(~not pat)                 ; matches if and only if pat does NOT match
(~seq pat ...)             ; head pattern. It is an inline run of terms
(~optional H-pat maybe-defaults)        ; H-pat or nothing
   maybe-defaults = #:defaults ([attr-id def-expr] ...)
(~once H-pat maybe-msg)                  ; exactly once in the ellipsis
(~between H-pat min max maybe-msg)       ; between min and max occurrences
(~bind [attr-id expr] ...)               ; bind attributes unconditionally
(~parse syntax-pattern stx-expr)         ; like #:with, inside a pattern
(~fail maybe-when message-expr)          ; force a failure
(~describe maybe-opt expr pat)           ; change the label of pat in errors
(~commit pat)  (~delimit-cut pat)        ; control the scope of backtracking
(~rest pat)                              ; bind the tail
```

Head patterns (`H-pat`) occur where the parser consumes a *sequence* of terms.
These places are `~seq`, `~optional`, `~once`, `~between`, and
splicing-class references.

## Template forms (for #' and #`)

```racket
pvar                       ; substitute the captured syntax
(tmpl ...)                 ; ellipsis iteration (the depth must match the depth of the pvar)
(~? tmpl)                  ; emit tmpl only if all its attributes are present
(~? tmpl alt)              ; if not, emit alt
(~@ tmpl ...)              ; splice into the enclosing sequence
(~@ . tmpl)
#`tmpl  #,expr  #,@list    ; quasisyntax / unsyntax / unsyntax-splicing
(syntax/loc loc-stx tmpl)  ; copy the source location to the result
(quasisyntax/loc loc-stx tmpl)
```

## define-syntax-class / define-splicing-syntax-class

```racket
(define-syntax-class name-or-(name . formals) class-option ...
  (pattern syntax-pattern pattern-directive ...) ...+)

(define-splicing-syntax-class name-or-(name . formals) class-option ...
  (pattern splicing-pattern pattern-directive ...) ...+)
  ; the patterns here are head patterns (use ~seq). Referenced pvars splice.

  class-option = #:description string-or-expr   ; noun phrase for errors
               | #:opaque                        ; report as one unit
               | #:attributes (attr-decl ...)    ; declare exported attributes
               | #:commit | #:no-delimit-cut
  attr-decl    = attr-id | (attr-id depth)
```

The class exports every pattern variable that a `pattern` binds as an
attribute. Outside the class, `p:cls` shows them as `p.attr`. In templates, you
must use an attribute with ellipsis depth N under N ellipses.
`(attribute attr-id)` yields the value of the attribute (syntax, a list, or any
value for `#:attr`). Inside a pattern, `this-syntax` is the whole matched term.

## Common built-in syntax classes (syntax/parse)

```
id (identifier)   keyword    str (string)    char     boolean
nat               integer    number          exact-integer
exact-nonnegative-integer    exact-positive-integer
expr      ; any term that you can use as an expression (not a definition keyword)
```

`expr` does not check that the term *is* a valid expression. It checks only
that the term is not obviously a non-expression. The expander does the full
check when it expands the output.

## racket/syntax and syntax helpers

```racket
(format-id    ctx fmt-string v ... [#:source #:props #:cert]) -> identifier?
   ; ~a in fmt splices each v (id, string, symbol, or number). The scopes come from ctx
(format-symbol fmt-string v ...) -> symbol?
(generate-temporaries stx-pair-or-list) -> (listof identifier?)
(with-syntax ([pat stx-expr] ...) body ...+)   ; like #:with, expression form
(syntax->list stx) -> (or/c (listof syntax?) #f)
(syntax->datum stx) -> datum         (datum->syntax ctx datum [srcloc props])
(syntax-e stx)      ; unwrap one level
(check-duplicate-identifier (listof identifier?)) -> (or/c identifier? #f)
```

## raise-syntax-error

```racket
(raise-syntax-error name message [expr sub-expr extra-sources ...]) -> any
   name     : (or/c symbol? #f)     ; #f means use the macro or form name from expr
   message  : string?
   expr     : the whole form to blame  (the message shows it as "in:")
   sub-expr : the specific bad term    (the message shows it as "at:")
```

If no clause matches, `syntax-parse` raises `exn:fail:syntax` automatically.
The message uses the relevant `#:description` or the name of the built-in
class. Use this instead of manual checks.

## Phases

```racket
(require (for-syntax mod ...))   ; bindings at phase 1 (transformer time)
(begin-for-syntax defn ...)      ; phase-1 definitions in this module
(require (for-template mod ...)) ; phase -1, for code that a macro emits to require
(define-for-syntax id expr)      ; = (begin-for-syntax (define id expr))
```

Transformer code runs at phase 1. This code is the macro body, the syntax
classes, and the helper functions that the body calls. Therefore you must
require `syntax/parse`, `racket/syntax`, and `racket/base` `for-syntax` for
that code.
