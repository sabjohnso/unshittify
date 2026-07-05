# rackunit Reference — exact signatures

Companion to SKILL.md. Source: docs.racket-lang.org/rackunit/ and the
rackunit-spec package. Checked against Racket v9.1 [cs].

## Checks (require rackunit)

```racket
(check-equal?     v1 v2 [message])        ; equal?
(check-not-equal? v1 v2 [message])
(check-eqv?       v1 v2 [message])        ; eqv?
(check-eq?        v1 v2 [message])        ; eq?
(check-not-eq?    v1 v2 [message])  (check-not-eqv? ...)
(check-true   expr [message])             ; expr is exactly #t
(check-false  expr [message])             ; expr is exactly #f
(check-not-false expr [message])          ; expr is not #f
(check-pred   pred  v [message])          ; (pred v) is non-#f
(check-=      v1 v2 tolerance [message])  ; |v1 - v2| <= tolerance
(check-exn     pred-or-regexp thunk [message])  ; thunk raises matching exn
(check-not-exn thunk [message])           ; thunk raises nothing
(check-match  val pattern [when-expr])    ; match-pattern, optional guard
(check-regexp-match regexp string)        ; regexp-match succeeds
(check pred v1 v2 [message])              ; (pred v1 v2) is non-#f
(check-within v1 v2 epsilon [message])    ; structural numeric closeness
(fail [message])                          ; always fails
```

`check-exn`'s first argument is a predicate (`exn:fail?`,
`exn:fail:contract?`, a custom `(-> any boolean)`) or a regexp matched
against the exception message; the second is a `(-> any)` thunk.

## Test grouping

```racket
(test-case name body ...)                 ; name : string; a named group
(test-begin body ...)                     ; anonymous grouping
(test-suite name             ; -> a test-suite value (does not run yet)
   [#:before before-thunk]
   [#:after  after-thunk]
   test ...)                              ; tests = test-case / test-suite / check
(make-test-suite name tests [#:before ...] [#:after ...])

(define-test-suite id test ...)           ; defines id = (test-suite "id" test ...)
(define-test-suite (id arg ...) test ...)

;; per-test fixtures inside a suite body:
(test-suite "s"
  (around (setup!) (test-case "x" ....) (teardown!)))   ; from rackunit
(before  (setup!)    test ...)            ; run before each enclosed test
(after   test ...    (teardown!))
```

## Running tests

```racket
;; rackunit/text-ui
(run-tests test [verbosity]) -> natural   ; failures + errors; verbosity:
                                          ;   'quiet 'normal(default) 'verbose
;; rackunit (programmatic)
(run-test test) -> (listof (or/c test-result? ...))
(fold-test-results proc seed test ...) ; custom aggregation
(foldts-test-suite ....)               ; low-level traversal

;; rackunit/gui : (test/gui test ...)  — a graphical runner
;; raco test file.rkt : runs the `test` submodule + top-level checks
```

## Custom checks and failure info

```racket
(with-check-info ([name-expr value-expr] ...) body ...)
   ; attach fields (shown on failure) to checks evaluated in body.
(check-info? v)  (make-check-info name value)
(check-info-name ci)  (check-info-value ci)
(make-check-name s) (make-check-location l) (make-check-message s) ...

(fail-check [message])                    ; raise the current check's failure
(define-check (name formal ...) body ...) ; new check; (fail-check) inside to fail
(define-simple-check (name formal ...) body)  ; body's #f result => failure
(define-binary-check (name actual expected) compare-expr)
(define-binary-check (name pred actual expected))

;; exception raised by a failed check (caught by the enclosing test):
(struct exn:test:check (...))   exn:test:check?   exn:test:check-stack
```

## rackunit/spec (package: rackunit-spec)

```racket
(require rackunit/spec)

(describe description-string body ...+)    ; nests the description
(context  description-string body ...+)    ; alias for describe
(it       description-string body ...+)    ; => (test-case nested-name body ...)
```

`describe`/`context` push their string onto a compile-time description stack;
`it` pops the full path and emits a `test-case` whose name is the
descriptions joined with two-space indentation per level. Bodies use ordinary
rackunit checks. There are no setup/teardown hooks — use local bindings in
`it` or a `test-suite` `#:before`/`#:after` for fixtures.
