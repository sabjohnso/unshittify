# Pattern-Matching Reference: exact grammars

This file accompanies SKILL.md. Source: docs.racket-lang.org/reference/match.html.
This file was checked against Racket v9.1 [cs].

## Match forms

```racket
(match val-expr clause ...)
   clause = [pat body ...+]
          | [pat (=> fail-id) body ...+]      ; fail-id : (-> any). A call to fail-id resumes at the next clause
          | [pat #:when cond-expr body ...+]  ; the clause runs only if cond is true.
                                              ;   If not, matching resumes at the next clause

(match* (val-expr ...+) clause* ...)          ; match several values at the same time
   clause* = [(pat ...+) body ...+]
           | [(pat ...+) (=> fail-id) body ...+]

(match-define pat expr)                        ; bind the variables of pat in the enclosing scope
(match-define-values (pat ...) expr)

(match-let     ([pat expr] ...) body ...+)     ; parallel
(match-let*    ([pat expr] ...) body ...+)     ; sequential
(match-letrec  ([pat expr] ...) body ...+)     ; recursive
(match-let-values ([(pat ...) expr] ...) body ...+)

(match-lambda   [pat body ...+] ...)           ; (lambda (x) (match x ...))
(match-lambda*  [(pat ...) body ...+] ...)     ; match the list of arguments
(match-lambda** [(pat ...+) body ...+] ...)    ; match several arguments (like match*)
```

## Pattern grammar

```racket
pat =
    _                       ; wildcard. It binds nothing
  | id                      ; bind id (an identifier matches any value and binds it)
  | literal                 ; #t #f number string bytes char keyword. It matches with equal?
  | (quote datum)           ; match the quoted datum
  | (list lvp ...)          ; a list. Its elements can use ellipses
  | (list-rest lvp ... pat) ; also written (list* ...). A fixed prefix and a tail pat
  | (list-no-order pat ...) ; the elements match in any order
  | (list-no-order pat ... lvp)
  | (vector lvp ...)        ; match a vector by position (an ellipsis can be used)
  | (hash-table (key-pat val-pat) ... maybe-rest)   ; rest = _ , ... , or (... ...)
  | (cons pat pat)
  | (mcons pat pat) (box pat) (hash* ...) 
  | (struct-id pat ...)            ; fields by position (use struct-id directly)
  | (struct struct-id (pat ...))   ; the explicit form
  | (struct* struct-id ([field pat] ...))  ; fields by name. Any subset of fields can be used
  | (regexp rx-expr)               ; match a string with rx-expr (uses regexp-match, not anchored)
  | (regexp rx-expr pat)           ; match the (regexp-match ...) result list
  | (pregexp rx-expr) (pregexp rx-expr pat)
  | (and pat ...)                  ; all pats must match. It binds the union of their variables (from left to right)
  | (or pat ...)                   ; one pat must match. Every arm must bind the SAME variables
  | (not pat ...)                  ; none of the pats match
  | (? expr pat ...)               ; apply expr as a predicate, then match pats
  | (app expr pat ...)             ; apply expr to the value, then match the results
  | (== val-expr [eq-expr])        ; match a value that is equal? (or eq-expr) to the value of val-expr
  | (quasiquote qq)                ; `... where ,pat and ,@pat unquote to patterns
  | (var id)                       ; bind explicitly (this is rarely necessary)
  | (struct-id ...) / patterns that define-match-expander defines

lvp =                              ; list-value pattern (an element position)
    pat ooo                        ; pat followed by an ellipsis. The pat repeats
  | pat

ooo (ellipsis) =
    ...        ; zero or more   (also written ___)
  | ..k        ; k or more, for example ..2   (also written __k)
```

In the body, a variable that one ellipsis binds is a list. A variable that N
nested ellipses bind is a list nested N levels deep. If a pattern variable name
occurs more than once in a pattern, those positions must match values that are `equal?`.

## Quasiquote patterns

```racket
`datum              ; literal structure
`,pat               ; unquote: match pat at this position
`,@pat              ; unquote-splicing: pat matches a sub-list
`(a b ,x)           ; a list. Its first two elements are 'a and 'b. The third element is bound to x
`(,elem ...)        ; each element is bound. In the body, elem is a list
```

## define-match-expander

```racket
(define-match-expander id match-transformer-expr)
(define-match-expander id match-transformer-expr macro-transformer-expr)
   ; match-transformer-expr : a phase-1 (-> syntax? syntax?) that produces a pattern
   ; macro-transformer-expr : optional. It lets you also use id as an expression
   ; (for-syntax racket/base) is necessary for lambda and syntax at phase 1.

(match-expander? v)          ; PHASE 1 ONLY. See below
```

`racket/match` provides `match-expander?` (with `legacy-match-expander?`,
`match-...-nesting`, `prop:match-expander`, `prop:legacy-match-expander`,
and `syntax-local-match-introduce`) *for-syntax*. A plain
`(require racket/match)` binds them at phase 1, inside a transformer body.
It leaves them **unbound at phase 0**. A call to `(match-expander? v)` in
ordinary code is an unbound-identifier error. `(require (for-syntax
racket/match))` does *not* reach them either. That form lifts the phase-0
exports of `racket/match`, not its phase-1 exports.

## Failure continuation

In `[pat (=> fail-id) body ...]`, `fail-id` is bound to a thunk. A call to
`(fail-id)` abandons the current clause and continues matching at the next
clause. This is also true after the pattern matched and the body started. Use
this call for side conditions that need values that the body computes.
