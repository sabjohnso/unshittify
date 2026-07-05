# Pattern-Matching Reference — exact grammars

Companion to SKILL.md. Source: docs.racket-lang.org/reference/match.html.
Checked against Racket v9.1 [cs].

## Match forms

```racket
(match val-expr clause ...)
   clause = [pat body ...+]
          | [pat (=> fail-id) body ...+]      ; fail-id : (-> any) resumes next clause
          | [pat #:when cond-expr body ...+]  ; clause fires only if cond is true,
                                              ;   else resumes at the next clause

(match* (val-expr ...+) clause* ...)          ; match several values together
   clause* = [(pat ...+) body ...+]
           | [(pat ...+) (=> fail-id) body ...+]

(match-define pat expr)                        ; bind pat's vars in the enclosing scope
(match-define-values (pat ...) expr)

(match-let     ([pat expr] ...) body ...+)     ; parallel
(match-let*    ([pat expr] ...) body ...+)     ; sequential
(match-letrec  ([pat expr] ...) body ...+)     ; recursive
(match-let-values ([(pat ...) expr] ...) body ...+)

(match-lambda   [pat body ...+] ...)           ; (lambda (x) (match x ...))
(match-lambda*  [(pat ...) body ...+] ...)     ; matches the argument LIST
(match-lambda** [(pat ...+) body ...+] ...)    ; matches multiple args (like match*)
```

## Pattern grammar

```racket
pat =
    _                       ; wildcard, no binding
  | id                      ; binds id (a literal id matches & binds)
  | literal                 ; #t #f number string bytes char keyword; matches by equal?
  | (quote datum)           ; matches the quoted datum
  | (list lvp ...)          ; list with ellipsis-aware elements
  | (list-rest lvp ... pat) ; a.k.a. (list* ...): fixed prefix + tail pat
  | (list-no-order pat ...) ; elements in any order
  | (list-no-order pat ... lvp)
  | (vector lvp ...)        ; vector by position (ellipsis ok)
  | (hash-table (key-pat val-pat) ... maybe-rest)   ; rest = _ , ... , or (... ...)
  | (cons pat pat)
  | (mcons pat pat) (box pat) (hash* ...) 
  | (struct-id pat ...)            ; positional fields (struct-id used directly)
  | (struct struct-id (pat ...))   ; explicit form
  | (struct* struct-id ([field pat] ...))  ; fields by name, any subset
  | (regexp rx-expr)               ; string fully? matched by regexp
  | (regexp rx-expr pat)           ; match the (regexp-match ...) result list
  | (pregexp rx-expr) (pregexp rx-expr pat)
  | (and pat ...)                  ; all; binds union (left-to-right)
  | (or pat ...)                   ; any; every arm must bind the SAME vars
  | (not pat ...)                  ; none of the pats match
  | (? expr pat ...)               ; expr applied as predicate, then pats
  | (app expr pat ...)             ; apply expr to value, match result(s)
  | (== val-expr [eq-expr])        ; equal? (or eq-expr) to val-expr's value
  | (quasiquote qq)                ; `... with ,pat / ,@pat unquoting to patterns
  | (var id)                       ; explicit bind (rarely needed)
  | (struct-id ...) / derived patterns from define-match-expander

lvp =                              ; list-value pattern (an element position)
    pat ooo                        ; pat followed by an ellipsis -> repeats
  | pat

ooo (ellipsis) =
    ...        ; zero or more   (a.k.a.  ___)
  | ..k        ; k or more, e.g. ..2   (a.k.a.  __k)
```

A variable bound under one ellipsis is a list in the body; under N nested
ellipses it is a list nested N deep. Repeating a pattern variable name
within a pattern forces those positions to be `equal?`.

## Quasiquote patterns

```racket
`datum              ; literal structure
`,pat               ; unquote -> match pat at this position
`,@pat              ; unquote-splicing -> pat matches a sub-list
`(a b ,x)           ; list whose first two elems are 'a 'b, third bound to x
`(,elem ...)        ; each element bound; elem is a list in the body
```

## define-match-expander

```racket
(define-match-expander id match-transformer-expr)
(define-match-expander id match-transformer-expr macro-transformer-expr)
   ; match-transformer-expr : a phase-1 (-> syntax? syntax?) producing a pattern
   ; macro-transformer-expr : optional, lets id also be used as an expression
   ; requires (for-syntax racket/base) for lambda/syntax at phase 1.

(match-expander? v)
```

## Failure continuation

In `[pat (=> fail-id) body ...]`, `fail-id` is bound to a thunk. Calling
`(fail-id)` abandons the current clause — even after its pattern matched and
its body started — and continues matching at the next clause. Use it for
side conditions that need values computed in the body.
