# Exceptions Reference — exact signatures and grammars

Companion to SKILL.md. Source: docs.racket-lang.org/reference/ §"Exceptions"
and §"Continuations". Every form, arity and message below was checked
against Racket v9.1 [cs].

## Raising

```racket
(raise v [barrier?]) -> any            ; v is any value; barrier? defaults to #t

(error sym)                            ; message becomes "error: <sym>"
(error msg-string v ...)               ; values appended, printed with ~e
(error who-sym format-string v ...)    ; "who: <formatted>"

(raise-user-error ...)                 ; same three shapes; exn:fail:user
                                       ; printed without a context trace

(raise-argument-error who expected-string v)
(raise-argument-error who expected-string bad-pos v ...)
(raise-result-error   who expected-string v)
(raise-result-error   who expected-string bad-pos v ...)
  ; expected-string NAMES a contract ("even?"), it is not a contract value.
  ; bad-pos is the 0-based index into the v ... that failed.

(raise-arguments-error who message-string field-string v ... ...)
  ; alternating field name and value after the message.

(raise-range-error who type-string index-prefix-string
                   index in-value lower-bound upper-bound [alt-lower-bound])

(raise-mismatch-error who message-string v ...)   ; legacy
(raise-type-error who type-string v)              ; deprecated
```

`raise-argument-error` and `raise-arguments-error` take no `#:realm`
argument in 9.1 — passing one raises "procedure does not accept keyword
arguments".

## Catching

```racket
(with-handlers  ([pred-expr handler-expr] ...) body ...+)
(with-handlers* ([pred-expr handler-expr] ...) body ...+)
  ; pred-expr    : (any/c -> any/c)   applied to the raised value
  ; handler-expr : (any/c -> any)     its result is the value of the form
```

- Clauses are tried in order; the **first** matching predicate wins.
- `with-handlers` escapes to its own continuation *before* calling the
  handler, so enclosed `dynamic-wind` post thunks and `parameterize`s are
  already unwound, and breaks are disabled for the handler.
- `with-handlers*` differs only in that the handler is called in tail
  position with respect to the form and breaks are left as they were.
  Measured: `(break-enabled)` inside the handler is `#f` under
  `with-handlers`, `#t` under `with-handlers*`.

```racket
(call-with-exception-handler handler thunk) -> any
  ; handler runs in the DYNAMIC CONTEXT OF THE RAISE — no escape, so the
  ; raise-site parameterization is still in effect. Returning from the
  ; handler re-raises to the next handler out.
```

## Handler parameters

```racket
(uncaught-exception-handler)     ; (any/c -> any) ; must not return normally:
                                 ;   "handler for uncaught exceptions:
                                 ;    did not escape"
(error-display-handler)          ; (string? any/c -> any)
(error-escape-handler)           ; (-> any)
(error-value->string-handler)    ; (any/c exact-nonnegative-integer? -> string?)
(error-print-context-length)     ; exact-nonnegative-integer?, default 16
(error-print-width)              ; how wide values print in messages
(error-print-source-location)    ; boolean?
```

## The exn structs

```racket
(struct exn (message continuation-marks))
  exn-message              : string?
  exn-continuation-marks   : continuation-mark-set?

(struct exn:break exn (continuation))        ; NOT under exn:fail
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

Every name above has a matching `<name>?` predicate. Subtyping is real
struct subtyping, so `exn:fail:contract:arity?` implies `exn:fail:contract?`
implies `exn:fail?` implies `exn?`.

Not in `racket/base` — each needs its own require:

| Predicate                  | Module            | Raised by                               |
|----------------------------|-------------------|-----------------------------------------|
| `exn:fail:contract:blame?` | `racket/contract` | any contract violation                  |
| `exn:misc:match?`          | `racket/match`    | a failed `match` with no else           |
| `exn:fail:support?`        | `racket/generic`  | a method the type's `#:methods` omitted |

`exn:fail:contract:blame-object` returns the `blame?` record;
`blame-positive` / `blame-negative` name the parties.

## Cleanup and escapes

```racket
(dynamic-wind pre-thunk value-thunk post-thunk) -> any
  ; all three take zero arguments; post-thunk runs on normal return, on a
  ; raise, and on an escape out of value-thunk.

(let/ec k body ...+)                     ; k escapes when applied
(call/ec proc)                           ; = call-with-escape-continuation
(call/cc proc)                           ; = call-with-current-continuation
```

- `kill-thread` and a custodian shutdown do **not** run the post thunks of a
  `dynamic-wind` in the killed thread — measured, the post thunk simply
  never runs. `break-thread` does unwind.
- Prefer the library wrappers that already do this correctly:
  `call-with-input-file`, `call-with-output-file`, `call-with-semaphore`.

## Formatting a caught exception

```racket
(require racket/exn)
(exn->string e) -> string?     ; message plus context, as the REPL prints it
```

## Message conventions

Racket's own errors follow one layout, and `raise-argument-error` /
`raise-arguments-error` produce it for you:

```
who: short message
  field: value
  other field: value
```

- Message is a lowercase fragment with no trailing period.
- Field names are lowercase strings **without** the colon — the raiser adds
  it. A field name ending in `...` (e.g. `"other arguments..."`) prints its
  value indented on following lines.
- `who` is a symbol, normally the function's own name.
- `(error 'sym)` with a single symbol produces `error: sym`, not `sym: ` —
  use the `who`+format shape when you mean to name a function.
