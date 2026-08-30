---
description: Raise and handle errors in Racket — the raise family (error, raise-argument-error, raise-arguments-error, raise-user-error, raise), catching with with-handlers and with-handlers*, the exn struct hierarchy and its predicates, defining your own exn subtype, guaranteed cleanup with dynamic-wind, escaping with let/ec and call/ec, and how contract violations fit in. Use when catching an exception, choosing an error-raising procedure, defining a custom exception type, guaranteeing cleanup on a non-local exit, or reading a Racket error message; for contract violations and blame messages see ../contracts/SKILL.md, and for compile-time errors raised by a macro see ../macros/SKILL.md.
allowed-tools: Read, Grep, Glob
---

# Exceptions and Error Handling in Racket

Racket signals a failure by **raising a value** — conventionally an `exn`
struct — to the innermost installed handler. `with-handlers` installs
handlers, the `raise-*` family builds well-formed messages, and
`dynamic-wind` guarantees cleanup whether the body returns or escapes. For
exact signatures, the full `exn` subtype tree, and the handler parameters,
read `reference.md` in this skill directory.

```racket
(define (halve n)
  (unless (even? n)
    (raise-argument-error 'halve "even?" n))
  (/ n 2))

(with-handlers ([exn:fail:contract? (lambda (e) 'rejected)])
  (halve 3))                             ; => 'rejected
```

## Choosing how to raise

Pick the most specific raiser: each one formats the message in the shape the
rest of Racket uses, so a caller reading the error gets the same layout it
gets from `car` or `vector-ref`.

| Situation                                | Use                                                |
|------------------------------------------|----------------------------------------------------|
| an argument fails a stated contract      | `(raise-argument-error 'who "even?" v)`            |
| a *result* fails one                     | `(raise-result-error 'who "string?" v)`            |
| an index is outside a collection         | `(raise-range-error 'who "vector" "" i vec 0 hi)`  |
| a failure with several named details     | `(raise-arguments-error 'who "msg" "field" v ...)` |
| a user-facing mistake, no internal blame | `(raise-user-error 'who "fmt ~a" v)`               |
| anything else                            | `(error 'who "fmt ~a" v)`                          |
| a value of your own exception type       | `(raise my-exn)`                                   |

`raise-argument-error`'s third argument is a **string naming a contract**,
not a contract value, and the message it prints is exactly the one
`racket/contract` prints for a violated domain:

```racket
(raise-argument-error 'halve "even?" 3)
;; halve: contract violation
;;   expected: even?
;;   given: 3
```

`raise-arguments-error` takes alternating field names and values after the
message. Field names are lowercase strings without a trailing colon; the
message itself has no trailing period:

```racket
(raise-arguments-error 'take-n "list is too short"
                       "requested" 5
                       "length" 2)
;; take-n: list is too short
;;   requested: 5
;;   length: 2
```

## Catching with with-handlers

`with-handlers` takes predicate/handler pairs. The predicate is applied to
the raised value; the **first** clause whose predicate accepts it wins, so
narrow clauses go above broad ones:

```racket
(define (write-config-once path text)
  (with-handlers ([exn:fail:filesystem:exists? (lambda (e) 'already-there)]
                  [exn:fail:filesystem?        (lambda (e) 'unwritable)])
    (call-with-output-file path #:exists 'error
      (lambda (out) (write-string text out)))
    'written))
```

Reversing those two clauses makes the `:exists` clause dead code — nothing
warns about it.

Before the handler runs, `with-handlers` **escapes to its own continuation**:
the body's `dynamic-wind` post thunks have already run and its
`parameterize`s are already undone by the time the handler body evaluates.
A handler that needs the raise's own dynamic context wants
`call-with-exception-handler` instead (see `reference.md`).

`with-handlers*` differs from `with-handlers` in exactly two ways: the
handler is called in tail position with respect to the form, and breaks stay
enabled while it runs instead of being disabled. Reach for it only when a
handler loops or must remain breakable; `with-handlers` is the default.

## The exn hierarchy

`exn` is a plain struct with `exn-message` and `exn-continuation-marks`, and
every built-in error is one of its subtypes. Catch by the narrowest
predicate that covers the failure you actually expect:

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
  ├ exn:fail:user        raise-user-error; printed without a context trace
  ├ exn:fail:out-of-memory
  └ exn:fail:unsupported
```

`exn:break` is **not** under `exn:fail`, which is the reason to write
`exn:fail?` rather than `exn?`: a handler on `exn?` swallows the user's
Ctrl-C along with the error it meant to catch.

`raise` accepts *any* value, not just an `exn`, so a predicate like
`exn:fail?` will not see `(raise 'timeout)`. Catch a non-`exn` raise with a
predicate that matches the value (`symbol?`, your own struct's predicate) or,
deliberately, with `void` to catch everything.

## Your own exception type

Subtype `exn:fail` so existing `exn:fail?` handlers still work, and carry the
data the caller needs as extra fields:

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

`with-handlers` is *not* cleanup — it only runs when something is raised, and
an escape continuation or a returned value skips it entirely. `dynamic-wind`
runs its post thunk on **every** exit from the body: normal return, raise, or
escape.

```racket
(define (call-with-log-file path proc)
  (define out (open-output-file path #:exists 'truncate))
  (dynamic-wind
    void
    (lambda () (proc out))
    (lambda () (close-output-port out))))
```

One real gap: `kill-thread` (and a custodian shutdown) does **not** run post
thunks in the killed thread. `break-thread` does. Anything that must be
released even when the thread is killed belongs to a custodian, not to a
`dynamic-wind`.

Prefer an existing `call-with-…` wrapper (`call-with-input-file`,
`call-with-output-file`, `call-with-semaphore`) over hand-writing the
`dynamic-wind` — they already do this correctly.

## Escaping without an error

An early return is a continuation jump, not an error; do not raise for it.
`let/ec` binds an escape procedure whose call abandons the rest of the body:

```racket
(define (first-index lst v)
  (let/ec return
    (for ([x (in-list lst)] [i (in-naturals)])
      (when (equal? x v) (return i)))
    #f))
```

`call/ec` is the procedural spelling (`call-with-escape-continuation`).
Escaping still runs enclosing `dynamic-wind` post thunks, so cleanup holds.

## Contracts and exceptions

A violation from `racket/contract` raises `exn:fail:contract:blame`, a
subtype of `exn:fail:contract` carrying the blame record:

```racket
(require racket/contract)

(with-handlers ([exn:fail:contract:blame?
                 (lambda (e) (blame-positive (exn:fail:contract:blame-object e)))])
  (contracted-call "wrong"))
```

The two mechanisms answer different questions. A contract states an
invariant at a module boundary and blames whoever broke it; a raise reports a
condition the caller is expected to handle. Do not catch
`exn:fail:contract?` to paper over a contract violation — it means the code
is wrong, not that the input was. Reading blame messages belongs to
[contracts](../contracts/SKILL.md); `raise-syntax-error`, the compile-time
counterpart of this file, belongs to [macros](../macros/SKILL.md).

## Rules that prevent rework

- **`exn:fail?`, never `exn?`.** `exn:break` is a sibling of `exn:fail`, and
  a handler on `exn?` silently eats Ctrl-C.
- **Narrow clauses first.** `with-handlers` takes the first predicate that
  matches, so a broad clause above a narrow one makes the narrow one dead.
- **Raise with the specific raiser, not `error`.** `raise-argument-error` and
  `raise-arguments-error` produce the message layout the rest of Racket
  produces; a hand-formatted `error` string does not.
- **Cleanup is `dynamic-wind` or a `call-with-…` wrapper, not a handler.** A
  handler runs only on a raise; the post thunk runs on every exit.
- **Subtype `exn:fail`, and put the data in fields.** Callers should branch on
  a predicate and read a field, not `regexp-match` the message string.
- **Don't catch what you can't handle.** A handler that returns a plausible
  substitute for a bug hides the bug; let it reach the top level unless there
  is a real recovery.
- **Early return is `let/ec`, not a raise.** Exceptions cost more and read as
  failure; an escape continuation says "done" without claiming anything broke.
