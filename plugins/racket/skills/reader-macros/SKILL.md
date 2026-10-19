---
description: "Write Racket reader macros, and work with readtables. Covers make-readtable, terminating, non-terminating, and dispatch macros, a character remap, comment-like macros, #reader, and a custom #lang reader through syntax/module-reader. Use when you extend the reader of Racket, when you add new lexical syntax, when you map a character such as { to (, or when you build a #lang whose surface syntax differs from s-expressions."
allowed-tools: Read, Grep, Glob
---

# Reader macros and readtables

The reader turns characters into syntax objects *before* the macro
expansion. A **readtable** maps characters to reader behavior. You extend it
with `make-readtable`, and then you make `read` and `read-syntax` use it
with a `parameterize` of `current-readtable`. This is the layer below
`define-syntax`. Use it only when the change is lexical (a new bracket, a
sigil, a comment form), not when a macro on ordinary s-expressions is
enough. For the exact signatures and the full grammar of `make-readtable`,
read `reference.md` in this skill directory.

## The reader-proc protocol

One procedure handles a character for both `read` and `read-syntax`. So it
must accept **two arities**. Write it as a `case-lambda`:

```racket
(define my-proc
  (case-lambda
    ;; read mode: (char in)
    [(ch in) (do-read ch in #f #f #f #f)]
    ;; read-syntax mode: (char in src line col pos)
    [(ch in src line col pos) (do-read ch in src line col pos)]))
```

- `ch` is the character that triggered the macro. It is already consumed
  from `in`.
- The procedure reads what follows from the port `in`, and it returns the
  datum (or the syntax object) that the character stands for.
- In `read-syntax` mode, Racket wraps a returned plain datum as syntax, but
  that **loses the source locations**. Call `read-syntax` or `datum->syntax`
  inside the procedure, so the positions survive.
- To consume input and produce *nothing* (a comment), return
  `(make-special-comment v)`. A return of zero values does **not** work. It
  raises an arity error.

`make-readtable` requires every procedure to accept arity 6, also when you
only call `read`. A procedure with arity 2 only is a contract violation.

## The make-readtable modes

```racket
(make-readtable base-readtable char mode action  ...more-triples...)
```

`base-readtable` is `#f` for the standard readtable, or an existing
readtable to extend. The triples repeat. `mode` selects the behavior:

| `mode`                   | `action`          | Effect                                                     |
|--------------------------|-------------------|------------------------------------------------------------|
| `'terminating-macro`     | a procedure       | `char` fires, and it **ends** the token before it          |
| `'non-terminating-macro` | a procedure       | fires only at the start of a token. Inside a token, it is a constituent |
| `'dispatch-macro`        | a procedure       | `char` fires only after `#` (for example `#$...`)          |
| a character `c`          | a readtable or `#f` | `char` now parses **like** `c` (for example `{` like `(`) |

A demonstration of terminating against non-terminating (`%` bound to a
procedure):

```
terminating       ab%c   ->  reads  ab    (% ends the token "ab")
non-terminating   ab%c   ->  reads  ab%c  (% is part of the symbol)
non-terminating   %c     ->  fires the macro (% is at the start of the token)
```

Use **terminating** for a sigil that must split tokens (`$`, `@`). Use
**non-terminating** only for a character that must live inside symbols.

## Worked examples

A terminating sigil: `$x` reads as `(quote x)`:

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

A dispatch macro: `#$expr` (the procedure is registered on `$`, and it fires
after `#`):

```racket
(make-readtable #f #\$ 'dispatch-macro hash-dollar)
;; "#$ foo" triggers hash-dollar with ch = #\$
```

A character remap: curly braces as an extra pair of parentheses. Remap
**both** the opener and the closer. Otherwise the reader does not balance:

```racket
(define braces->parens
  (make-readtable #f #\{ #\( #f
                     #\} #\) #f))
(parameterize ([current-readtable braces->parens])
  (read (open-input-string "{1 2 {3 4}}")))   ; => '(1 2 (3 4))
```

A comment-like macro: `!` drops the rest of the line and produces no datum:

```racket
(define line-comment
  (case-lambda
    [(ch in) (read-line in) (make-special-comment #f)]
    [(ch in src line col pos) (read-line in) (make-special-comment #f)]))
(make-readtable #f #\! 'terminating-macro line-comment)
;; (read "(1 ! gone\n 2 3)")  =>  '(1 2 3)
```

## Install a readtable

- **Locally:** `(parameterize ([current-readtable rt]) (read in))`. The
  default value of `current-readtable` is `#f` (the standard readtable).
- **In a string or a port through `#reader`:** `read` rejects the `#reader`
  and `#lang` notations, unless `(read-accept-reader #t)` is set.
- **As a `#lang`:** put a reader at `<collection>/lang/reader.rkt`, and let
  `syntax/module-reader` install the readtable with `#:wrapper1`, which
  wraps the reader thunk in a `parameterize`:

  ```racket
  #lang s-exp syntax/module-reader
  my-lang                 ; the module language that the programs expand into
  #:wrapper1 (lambda (t) (parameterize ([current-readtable my-rt]) (t)))
  (require "../rt.rkt")   ; gives my-rt
  ```

  `#lang my-lang` resolves to `my-lang/lang/reader`. The wrapper makes every
  `read` and `read-syntax` during that module use `my-rt`.

## Error reports

Signal malformed input with `raise-read-error` (from `syntax/readerr`).
Then the error carries the source location, which a bare `error` does not.
Use `raise-read-eof-error` when the input ends inside a token:

```racket
(require syntax/readerr)
(raise-read-error "unterminated $-form" src line col pos span)
```

## Rules that prevent rework

- **One `case-lambda`, two arities, always.** A procedure that takes only 2
  arguments fails the arity-6 contract of `make-readtable`. A procedure
  that ignores the syntax arity discards the source locations.
- **Read with the syntax-aware operations inside the read-syntax mode.** Use
  `read-syntax`, `peek-char`, and `read-char`, and build the result with
  `datum->syntax`, so the positions propagate. A return of raw data works,
  but it strips the source locations from the result.
- **Remap brackets in pairs.** A map of `{` to `(` without a map of `}` to
  `)` leaves the closer with no handler, and the read never ends.
- **`make-special-comment` is the only way to "produce nothing".** Zero
  values raise an arity error, both in `read` and inside a list.
- **Prefer a real macro to a reader macro.** A readtable operates on raw
  characters, with no hygiene and no binding information. It is justified
  only for syntax that is lexical. If ordinary s-expressions can carry the
  idea, use `define-syntax` or `syntax-parse` instead.
- **Build on the standard readtable. Do not replace it.** Pass `#f` (or an
  existing readtable) as the base. Then numbers, strings, and parentheses
  continue to work. Override only the characters that you mean to change.
