# Readtable Reference: exact signatures and grammars

This file accompanies `SKILL.md`. The sources are docs.racket-lang.org/reference/ section "Reading"
(`Readtables`, `Reader-Extension Procedures`) and `syntax/module-reader`.
All forms below were checked against Racket v9.1 [cs].

## make-readtable

```racket
(make-readtable readtable
                (or char #f) mode action ... ...) -> readtable?

  readtable : (or/c readtable? #f)        ; #f means the standard readtable
  ;; the arguments after `readtable` are (char mode action) triples:

  char  : (or/c char? #f)                 ; the character to define or redefine
  mode  : (or/c 'terminating-macro
                'non-terminating-macro
                'dispatch-macro
                char?)                    ; an existing char to copy
  action :
    ;; when mode is 'terminating-macro / 'non-terminating-macro / 'dispatch-macro:
    (or/c procedure?)                     ; reader proc, must accept arity 2 AND 6
    ;; when mode is a char?:
    (or/c readtable? #f)                  ; the readtable that supplies the mapping
                                          ;   of char, or #f for the standard one
```

- `'dispatch-macro` registers `char` as the character *after* `#`.
  Example: `#\$` with `'dispatch-macro` handles `#$`.
- When mode is a char, `char` parses exactly like that existing char.
  Remap both members of a bracket pair (`{`→`(` and `}`→`)`).
- When `char` is `#f` and mode is a char, the treatment of all other
  self-delimiting characters changes. This is rarely necessary.

## Readtable predicates, introspection, parameter

```racket
(readtable? v) -> boolean?

(current-readtable) -> (or/c readtable? #f)        ; parameter; default #f
(current-readtable rt) -> void?                    ; rt : (or/c readtable? #f)
;; read / read-syntax use current-readtable.

(readtable-mapping rt char)
  -> (values (or/c char? 'terminating-macro 'non-terminating-macro)
             (or/c procedure? #f)
             (or/c procedure? #f))
  ;; 1st value: how char parses (a char if remapped, else the macro kind)
  ;; 2nd value: the non-dispatch reader proc, or #f
  ;; 3rd value: the dispatch (#-prefixed) reader proc, or #f
  ;; It does NOT report the standard meaning of an unmodified char.
```

## Reader-extension procedure protocol

Racket calls a reader proc in two ways. The proc must accept both arities:

```racket
(proc char in)                          ; from `read`
(proc char in src line col position)    ; from `read-syntax`
  char     : char?                      ; the char that started the call, already read
  in       : input-port?
  src      : any/c                      ; source name passed to read-syntax
  line     : (or/c exact-positive-integer? #f)   ; #f unless line counting is on
  col      : (or/c exact-nonnegative-integer? #f)
  position : (or/c exact-positive-integer? #f)
```

Result conventions:

- Return the datum (read mode) or the syntax object (read-syntax mode) that the
  characters denote. In read-syntax mode, Racket converts a non-syntax result with
  `datum->syntax`. This conversion discards source locations.
- Return `(make-special-comment v)` to show that the characters were a
  comment. The call then yields no datum. `read` and `read-syntax` ignore `v`.
- Do not return zero values. Zero values raise an arity error.
- If the proc needs a `line` or `col` that is not `#f`, enable line and column
  counting on the port with `(port-count-lines! in)`. `position` is always available.

```racket
(make-special-comment v) -> special-comment?
(special-comment? v) -> boolean?
(special-comment-value sc) -> any/c
```

## Reader parameters

```racket
(read-accept-reader)   -> boolean?   ; parameter, default #f
(read-accept-reader b) -> void?
  ;; must be #t for `read`/`read-syntax` to accept #reader and #lang/#!
(read-accept-lang)     -> boolean?   ; parameter, default #t
  ;; controls #lang/#! only (read-accept-reader must also be #t)
```

`#reader module-path datum` loads `module-path`. The module must provide `read`
and `read-syntax`. Racket uses them to read the input that follows.

## Error helpers (require syntax/readerr)

```racket
(raise-read-error msg-string src line col pos span) -> any
(raise-read-eof-error msg-string src line col pos span) -> any
  ;; span : (or/c exact-nonnegative-integer? #f)
  ;; raise an exn:fail:read (or exn:fail:read:eof) with location information.
```

## syntax/module-reader options

A `lang/reader.rkt` file written in `#lang s-exp syntax/module-reader` names
the module language on the first line. Keyword options follow:

```racket
#lang s-exp syntax/module-reader
module-language-path
#:read         read-proc            ; default: read
#:read-syntax  read-syntax-proc     ; default: read-syntax
#:wrapper1     (-> (-> any) any)    ; wraps the read thunk; parameterize here
#:wrapper2     (-> input-port (-> input-port any) any)  ; receives the port also
#:whole-body-readers? boolean?      ; reader returns the whole module body
#:info         proc                 ; DrRacket/`get-info` hook
#:language-info ...                 ; runtime get-info
require-spec ...                    ; bindings that the options above can use
```

To install a custom readtable for a `#lang`, write this:

```racket
#:wrapper1 (lambda (t) (parameterize ([current-readtable my-rt]) (t)))
```

`#lang name` finds the reader at `name/lang/reader`. The file `name/main.rkt` of the collection
(or the declared module-language-path) supplies the bindings
that programs expand into.
