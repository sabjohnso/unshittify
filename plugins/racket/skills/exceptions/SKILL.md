---
description: Raise and handle errors in Racket. Covers the raise family (error, raise-argument-error, raise-arguments-error, raise-user-error, raise), the catch with with-handlers and with-handlers*, the exn struct hierarchy and its predicates, the definition of your own exn subtype, guaranteed cleanup with dynamic-wind, the escape with let/ec and call/ec, and how contract violations fit in. Use when you catch an exception, when you choose a procedure that raises an error, when you define a custom exception type, when you guarantee cleanup on a non-local exit, or when you read a Racket error message. For contract violations and blame messages, see ../contracts/SKILL.md. For a compile-time error that a macro raises, see ../macros/SKILL.md.
allowed-tools: Read, Grep, Glob
---

# Exceptions and error handling in Racket

Racket signals a failure when it **raises a value**, by convention an `exn`
struct, to the innermost installed handler. `with-handlers` installs the
handlers. The `raise-*` family builds well-formed messages. `dynamic-wind`
guarantees the cleanup, whether the body returns or escapes. For the exact
signatures, the full `exn` subtype tree, and the handler parameters, read
`reference.md` in this skill directory.

```racket
(define (halve n)
  (unless (even? n)
    (raise-argument-error 'halve "even?" n))
  (/ n 2))

(with-handlers ([exn:fail:contract? (lambda (e) 'rejected)])
  (halve 3))                             ; => 'rejected
```

## Choose how to raise

Pick the most specific raise procedure. Each one formats the message in the
shape that the rest of Racket uses. So a caller that reads the error gets
the same layout as from `car` or `vector-ref`.

| Situation                                   | Use                                                |
|---------------------------------------------|----------------------------------------------------|
| an argument fails a stated contract         | `(raise-argument-error 'who "even?" v)`            |
| a *result* fails one                        | `(raise-result-error 'who "string?" v)`            |
| an index is outside a collection            | `(raise-range-error 'who "vector" "" i vec 0 hi)`  |
| a failure with several named details        | `(raise-arguments-error 'who "msg" "field" v ...)` |
| a mistake of the user, with no internal blame | `(raise-user-error 'who "fmt ~a" v)`             |
| everything else                             | `(error 'who "fmt ~a" v)`                          |
| a value of your own exception type          | `(raise my-exn)`                                   |

The third argument of `raise-argument-error` is a **string that names a
contract**, not a contract value. The message that it prints is exactly the
one that `racket/contract` prints for a violated domain:

```racket
(raise-argument-error 'halve "even?" 3)
;; halve: contract violation
;;   expected: even?
;;   given: 3
```

`raise-arguments-error` takes field names and values in turn after the
message. A field name is a lowercase string with no colon at the end. The
message itself has no period at the end:

```racket
(raise-arguments-error 'take-n "list is too short"
                       "requested" 5
                       "length" 2)
;; take-n: list is too short
;;   requested: 5
;;   length: 2
```

## Catch with with-handlers

`with-handlers` takes pairs of a predicate and a handler. Racket applies the
predicate to the raised value. The **first** clause whose predicate accepts
the value wins. So put the narrow clauses above the broad clauses:

```racket
(define (write-config-once path text)
  (with-handlers ([exn:fail:filesystem:exists? (lambda (e) 'already-there)]
                  [exn:fail:filesystem?        (lambda (e) 'unwritable)])
    (call-with-output-file path #:exists 'error
      (lambda (out) (write-string text out)))
    'written))
```

In the reverse order, the `:exists` clause is dead code, and nothing warns
about it.

Before the handler runs, `with-handlers` **escapes to its own
continuation**. The post thunks of a `dynamic-wind` in the body have already
run, and each `parameterize` in the body is already undone, when the handler
body runs. A handler that needs the dynamic context of the raise itself must
use `call-with-exception-handler` instead (see `reference.md`).

`with-handlers*` differs from `with-handlers` in exactly two ways. It calls
the handler in tail position with respect to the form, and breaks stay
enabled while the handler runs. Use it only when a handler loops or must stay
breakable. `with-handlers` is the default.

## The exn hierarchy

`exn` is a plain struct with `exn-message` and `exn-continuation-marks`.
Every built-in error is one of its subtypes. Catch with the narrowest
predicate that covers the failure that you expect:

```
exn
├ exn:break              subtypes: :hang-up :terminate
└ exn:fail
  ├ exn:fail:contract    subtypes: :arity :divide-by-zero :continuation
  │                                :variable :non-fixnum-result
  ├ exn:fail:syntax      subtypes: :unbound :missing-module
  ├ exn:fail:read        subtypes: :eof :non-char
  ├ exn:fail:filesystem  subtypes: :exists :version :errno :missing-module
  ├ exn:fail:network     subtypes: :errno
  ├ exn:fail:user        raise-user-error; printed with no context trace
  ├ exn:fail:out-of-memory
  └ exn:fail:unsupported
```

`exn:break` is **not** under `exn:fail`. That is the reason to write
`exn:fail?` and not `exn?`. A handler on `exn?` swallows the Ctrl-C of the
user together with the error that it meant to catch.

`raise` accepts *every* value, not only an `exn`. So a predicate such as
`exn:fail?` does not see `(raise 'timeout)`. Catch a raise of a value that
is not an `exn` with a predicate that matches the value (`symbol?`, or the
predicate of your own struct), or, on purpose, with `void` to catch
everything.

## Your own exception type

Make a subtype of `exn:fail`, so the existing `exn:fail?` handlers continue
to work. Carry the data that the caller needs in extra fields:

```racket
(struct exn:fail:config exn:fail (key) #:transparent)

(define (config-ref h k)
  (hash-ref h k
            (lambda ()
              (raise (exn:fail:config (format "config-ref: no key ~a" k)
                                      (current-continuation-marks)
                                      k)))))

(with-handlers ([exn:fail:config? exn:fail:config-key])
  (config-ref (hash) 'port))             ; => 'port
```

The first two fields are inherited and positional: the message string, then
`(current-continuation-marks)`.

## Cleanup with dynamic-wind

`with-handlers` is *not* cleanup. It runs only when something is raised. An
escape continuation or a returned value skips it. `dynamic-wind` runs its
post thunk on **every** exit from the body: a normal return, a raise, or an
escape.

```racket
(define (call-with-log-file path proc)
  (define out (open-output-file path #:exists 'truncate))
  (dynamic-wind
    void
    (lambda () (proc out))
    (lambda () (close-output-port out))))
```

There is one real gap. `kill-thread` (and a custodian shutdown) does **not**
run the post thunks in the killed thread. `break-thread` does. A resource
that must be released also when the thread is killed belongs to a custodian,
not to a `dynamic-wind`.

Prefer an existing `call-with-…` wrapper (`call-with-input-file`,
`call-with-output-file`, `call-with-semaphore`) to a hand-written
`dynamic-wind`. The wrappers already do this correctly.

## An escape with no error

An early return is a continuation jump, not an error. Do not raise for it.
`let/ec` binds an escape procedure. A call to it abandons the rest of the
body:

```racket
(define (first-index lst v)
  (let/ec return
    (for ([x (in-list lst)] [i (in-naturals)])
      (when (equal? x v) (return i)))
    #f))
```

`call/ec` is the procedural spelling (`call-with-escape-continuation`). An
escape still runs the post thunks of each enclosing `dynamic-wind`, so the
cleanup holds.

## Contracts and exceptions

A violation from `racket/contract` raises `exn:fail:contract:blame`, a
subtype of `exn:fail:contract` that carries the blame record:

```racket
(require racket/contract)

(with-handlers ([exn:fail:contract:blame?
                 (lambda (e) (blame-positive (exn:fail:contract:blame-object e)))])
  (contracted-call "wrong"))
```

The two mechanisms answer different questions. A contract states an
invariant at a module boundary and blames the party that broke it. A raise
reports a condition that the caller is expected to handle. Do not catch
`exn:fail:contract?` to hide a contract violation. The violation means that
the code is wrong, not that the input was wrong. The blame messages belong to
[contracts](../contracts/SKILL.md). `raise-syntax-error`, the compile-time
counterpart of this file, belongs to [macros](../macros/SKILL.md).

## Rules that prevent rework

- **`exn:fail?`, never `exn?`.** `exn:break` is a sibling of `exn:fail`. A
  handler on `exn?` eats Ctrl-C with no message.
- **Narrow clauses first.** `with-handlers` takes the first predicate that
  matches. So a broad clause above a narrow clause makes the narrow clause
  dead.
- **Raise with the specific raise procedure, not with `error`.**
  `raise-argument-error` and `raise-arguments-error` produce the message
  layout that the rest of Racket produces. A hand-formatted `error` string
  does not.
- **Cleanup is `dynamic-wind` or a `call-with-…` wrapper, not a handler.** A
  handler runs only on a raise. The post thunk runs on every exit.
- **Make a subtype of `exn:fail`, and put the data in fields.** A caller
  must branch on a predicate and read a field. It must not `regexp-match`
  the message string.
- **Do not catch what you cannot handle.** A handler that returns a
  plausible substitute for a bug hides the bug. Let it reach the top level,
  unless there is a real recovery.
- **An early return is `let/ec`, not a raise.** An exception costs more and
  reads as a failure. An escape continuation says "done" and claims no
  failure.
