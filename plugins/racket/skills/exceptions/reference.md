# Exceptions Reference: exact signatures and grammars

This file accompanies `SKILL.md`. Source: docs.racket-lang.org/reference/ §"Exceptions"
and §"Continuations". Every form, arity, and message below was checked
against Racket v9.1 [cs].

## Raising

```racket
(raise v [barrier?]) -> any            ; v is any value. barrier? defaults to #t

(error sym)                            ; message becomes "error: <sym>"
(error msg-string v ...)               ; the function appends the values and prints them with ~e
(error who-sym format-string v ...)    ; "who: <formatted>"

(raise-user-error ...)                 ; same three shapes. It raises exn:fail:user
                                       ; and prints no context trace

(raise-argument-error who expected-string v)
(raise-argument-error who expected-string bad-pos v ...)
(raise-result-error   who expected-string v)
(raise-result-error   who expected-string bad-pos v ...)
  ; expected-string names a contract ("even?"). It is not a contract value.
  ; bad-pos is the 0-based index of the failed value in v ...

(raise-arguments-error who message-string field-string v ... ...)
  ; after the message, field names and values alternate.

(raise-range-error who type-string index-prefix-string
                   index in-value lower-bound upper-bound [alt-lower-bound])

(raise-mismatch-error who message-string v ...)   ; legacy
(raise-type-error who type-string v)              ; deprecated
```

`raise-argument-error` and `raise-arguments-error` take no `#:realm`
argument in 9.1. If you pass one, they raise "procedure does not accept keyword
arguments".

## Catching

```racket
(with-handlers  ([pred-expr handler-expr] ...) body ...+)
(with-handlers* ([pred-expr handler-expr] ...) body ...+)
  ; pred-expr    : (any/c -> any/c)   the form applies it to the raised value
  ; handler-expr : (any/c -> any)     its result is the value of the form
```

- The form tries the clauses in order. The **first** predicate that matches wins.
- `with-handlers` escapes to its own continuation *before* it calls the
  handler. The enclosed `dynamic-wind` post thunks and `parameterize`s are
  then unwound. Breaks are disabled for the handler.
- `with-handlers*` differs in two ways. It calls the handler in tail
  position with respect to the form, and it leaves breaks as they were.
  Measured: `(break-enabled)` inside the handler is `#f` under
  `with-handlers` and `#t` under `with-handlers*`.

```racket
(call-with-exception-handler handler thunk) -> any
  ; handler runs in the dynamic context of the raise. There is no escape,
  ; so the raise-site parameterization is still in effect. If the handler
  ; returns, it re-raises to the next outer handler.
```

## Handler parameters

```racket
(uncaught-exception-handler)     ; (any/c -> any). It must not return normally:
                                 ;   "handler for uncaught exceptions:
                                 ;    did not escape"
(error-display-handler)          ; (string? any/c -> any)
(error-escape-handler)           ; (-> any)
(error-value->string-handler)    ; (any/c exact-nonnegative-integer? -> string?)
(error-print-context-length)     ; exact-nonnegative-integer?, default 16
(error-print-width)              ; the print width of values in messages
(error-print-source-location)    ; boolean?
```

## The exn structs

```racket
(struct exn (message continuation-marks))
  exn-message              : string?
  exn-continuation-marks   : continuation-mark-set?

(struct exn:break exn (continuation))        ; not a subtype of exn:fail
  (struct exn:break:hang-up   exn:break ())
  (struct exn:break:terminate exn:break ())

(struct exn:fail exn ())
  (struct exn:fail:contract exn:fail ())
    exn:fail:contract:arity
    exn:fail:contract:divide-by-zero
    exn:fail:contract:non-fixnum-result
    exn:fail:contract:continuation
    exn:fail:contract:variable            ; + exn:fail:contract:variable-id
  (struct exn:fail:syntax exn:fail (exprs))  ; exn:fail:syntax-exprs
    exn:fail:syntax:unbound
    exn:fail:syntax:missing-module        ; + ...-path
  (struct exn:fail:read exn:fail (srclocs))  ; exn:fail:read-srclocs
    exn:fail:read:eof
    exn:fail:read:non-char
  (struct exn:fail:filesystem exn:fail ())
    exn:fail:filesystem:exists
    exn:fail:filesystem:version
    exn:fail:filesystem:errno             ; + exn:fail:filesystem:errno-errno
    exn:fail:filesystem:missing-module
  (struct exn:fail:network exn:fail ())
    exn:fail:network:errno                ; + exn:fail:network:errno-errno
  exn:fail:out-of-memory
  exn:fail:unsupported
  exn:fail:user                           ; raise-user-error
```

Every name above has a matching `<name>?` predicate. The subtyping is real
struct subtyping, so `exn:fail:contract:arity?` implies `exn:fail:contract?`,
which implies `exn:fail?`, which implies `exn?`.

The following are not in `racket/base`. Each needs its own require:

| Predicate                  | Module            | Raised by                               |
|----------------------------|-------------------|-----------------------------------------|
| `exn:fail:contract:blame?` | `racket/contract` | any contract violation                  |
| `exn:misc:match?`          | `racket/match`    | a failed `match` with no else           |
| `exn:fail:support?`        | `racket/generic`  | a method the type's `#:methods` omitted |

`exn:fail:contract:blame-object` returns the `blame?` record.
`blame-positive` and `blame-negative` name the parties.

## Cleanup and escapes

```racket
(dynamic-wind pre-thunk value-thunk post-thunk) -> any
  ; all three take zero arguments. post-thunk runs on a normal return, on
  ; a raise, and on an escape out of value-thunk.

(let/ec k body ...+)                     ; k escapes when you apply it
(call/ec proc)                           ; = call-with-escape-continuation
(call/cc proc)                           ; = call-with-current-continuation
```

- `kill-thread` and a custodian shutdown do **not** run the post thunks of a
  `dynamic-wind` in the killed thread. Measured: the post thunk never
  runs. `break-thread` does unwind.
- Use the library wrappers that do this correctly:
  `call-with-input-file`, `call-with-output-file`, `call-with-semaphore`.

## How to format a caught exception

```racket
(require racket/exn)
(exn->string e) -> string?     ; message and context, as the read-eval-print loop (REPL) prints them
```

## Message conventions

Racket's own errors follow one layout. `raise-argument-error` and
`raise-arguments-error` produce this layout for you:

```
who: short message
  field: value
  other field: value
```

- The message is a lowercase fragment with no final period.
- Field names are lowercase strings **without** the colon. The raiser adds
  the colon. A field name that ends in `...` (for example `"other arguments..."`)
  prints its value indented on the next lines.
- `who` is a symbol. It is normally the name of the function.
- `(error 'sym)` with a single symbol produces `error: sym`, not `sym: `.
  To name a function, use the `who` and format shape.
