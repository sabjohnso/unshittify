---
description: Write Racket reader macros and work with readtables — make-readtable, terminating/non-terminating/dispatch macros, character remapping, comment-like macros, #reader, and custom #lang readers via syntax/module-reader. Use when extending Racket's reader, adding new lexical syntax, mapping characters like { to (, or building a #lang whose surface syntax differs from s-expressions.
---

# Reader Macros and Readtables

The reader turns characters into syntax objects *before* macro expansion. A
**readtable** maps characters to reader behavior; you extend it with
`make-readtable`, then make `read`/`read-syntax` use it by parameterizing
`current-readtable`. This is the layer below `define-syntax` — reach for it
only when the change is lexical (a new bracket, a sigil, a comment form),
not when a macro on ordinary s-expressions would do. For exact signatures
and the full grammar of `make-readtable`, read `reference.md` in this skill
directory.

## The reader-proc protocol

One procedure handles a character for both `read` and `read-syntax`, so it
must accept **two arities** — write it as a `case-lambda`:

```racket
(define my-proc
  (case-lambda
    ;; read mode: (char in)
    [(ch in) (do-read ch in #f #f #f #f)]
    ;; read-syntax mode: (char in src line col pos)
    [(ch in src line col pos) (do-read ch in src line col pos)]))
```

- `ch` is the character that triggered the macro (already consumed from `in`).
- The proc reads whatever follows from the port `in` and returns the datum
  (or syntax object) the character stands for.
- In `read-syntax` mode, returning a plain datum is auto-wrapped to syntax,
  but that **loses source locations** — call `read-syntax`/`datum->syntax`
  inside so positions survive.
- To consume input but produce *nothing* (a comment), return
  `(make-special-comment v)`. Returning zero values does **not** work and
  raises an arity error.

`make-readtable` requires every proc to accept arity 6 even if you only ever
call `read` — a 2-only procedure is a contract violation.

## make-readtable modes

```racket
(make-readtable base-readtable char mode action  ...more-triples...)
```

`base-readtable` is `#f` for the standard readtable, or an existing one to
extend. Triples repeat. `mode` selects the behavior:

| `mode`                   | `action`          | Effect                                                  |
|--------------------------|-------------------|---------------------------------------------------------|
| `'terminating-macro`     | proc              | `char` fires and **ends** any preceding token           |
| `'non-terminating-macro` | proc              | fires only at token start; mid-token it's a constituent |
| `'dispatch-macro`        | proc              | `char` fires only after `#` (e.g. `#$...`)              |
| a character `c`          | readtable or `#f` | `char` now parses **like** `c` (e.g. `{` like `(`)      |

Terminating vs non-terminating, demonstrated (`%` bound to a proc):

```
terminating       ab%c   ->  reads  ab    (% ends the token "ab")
non-terminating   ab%c   ->  reads  ab%c  (% is part of the symbol)
non-terminating   %c     ->  fires the macro (% is at token start)
```

Use **terminating** for sigils that should split tokens (`$`, `@`); use
**non-terminating** only for characters meant to live inside symbols.

## Worked examples

Terminating sigil — `$x` reads as `(quote x)`:

```racket
(define dollar
  (case-lambda
    [(ch in) (list 'quote (read in))]
    [(ch in src line col pos)
     (datum->syntax #f (list 'quote (read-syntax src in)))]))
(define rt (make-readtable #f #\$ 'terminating-macro dollar))
(parameterize ([current-readtable rt])
  (read (open-input-string "$foo")))      ; => '(quote foo)
```

Dispatch macro — `#$expr` (the proc is registered on `$`, fires after `#`):

```racket
(make-readtable #f #\$ 'dispatch-macro hash-dollar)
;; "#$ foo" triggers hash-dollar with ch = #\$
```

Character remap — curly braces as an extra pair of parens (remap **both**
the opener and the closer, or the reader will not balance):

```racket
(define braces->parens
  (make-readtable #f #\{ #\( #f
                     #\} #\) #f))
(parameterize ([current-readtable braces->parens])
  (read (open-input-string "{1 2 {3 4}}")))   ; => '(1 2 (3 4))
```

Comment-like macro — `!` drops the rest of the line, produces no datum:

```racket
(define line-comment
  (case-lambda
    [(ch in) (read-line in) (make-special-comment #f)]
    [(ch in src line col pos) (read-line in) (make-special-comment #f)]))
(make-readtable #f #\! 'terminating-macro line-comment)
;; (read "(1 ! gone\n 2 3)")  =>  '(1 2 3)
```

## Installing a readtable

- **Locally:** `(parameterize ([current-readtable rt]) (read in))`. The
  default value of `current-readtable` is `#f` (the standard readtable).
- **In a string/port via `#reader`:** the `#reader` and `#lang` notations
  are rejected by `read` unless `(read-accept-reader #t)` is set.
- **As a `#lang`:** put a reader at `<collection>/lang/reader.rkt` and let
  `syntax/module-reader` install the readtable with `#:wrapper1`, which
  parameterizes the reader thunk:

  ```racket
  #lang s-exp syntax/module-reader
  my-lang                 ; the module language programs expand into
  #:wrapper1 (lambda (t) (parameterize ([current-readtable my-rt]) (t)))
  (require "../rt.rkt")   ; provides my-rt
  ```

  `#lang my-lang` resolves to `my-lang/lang/reader`; the wrapper makes every
  `read`/`read-syntax` during that module use `my-rt`.

## Error reporting

Signal malformed input with `raise-read-error` (from `syntax/readerr`) so
the error carries source location instead of a bare `error`; use
`raise-read-eof-error` when input ends mid-token:

```racket
(require syntax/readerr)
(raise-read-error "unterminated $-form" src line col pos span)
```

## Rules that prevent rework

- **One `case-lambda`, two arities, always.** A proc that only takes 2 args
  fails `make-readtable`'s arity-6 contract; a proc that ignores the syntax
  arity throws away source locations.
- **Read with the syntax-aware operations inside read-syntax mode.** Use
  `read-syntax`/`peek-char`/`read-char` and rebuild with `datum->syntax` so
  positions propagate; returning raw data works but de-locates the result.
- **Remap brackets in pairs.** Mapping `{`→`(` without `}`→`)` leaves the
  closer unhandled and the read never terminates.
- **`make-special-comment` is the only way to "produce nothing."** Zero
  values raises an arity error in both `read` and inside a list.
- **Prefer a real macro to a reader macro.** Readtables operate on raw
  characters with no hygiene and no binding information — justified only for
  genuinely lexical syntax. If ordinary s-expressions can carry the idea,
  use `define-syntax`/`syntax-parse` instead.
- **Build on the standard readtable, don't replace it.** Pass `#f` (or an
  existing readtable) as the base so numbers, strings, and parens keep
  working; only override the characters you mean to change.
