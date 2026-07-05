# Readtable Reference — exact signatures and grammars

Companion to SKILL.md. Source: docs.racket-lang.org/reference/ §"Reading"
(`Readtables`, `Reader-Extension Procedures`) and `syntax/module-reader`.
All forms below were checked against Racket v9.1 [cs].

## make-readtable

```racket
(make-readtable readtable
                (or char #f) mode action ... ...) -> readtable?

  readtable : (or/c readtable? #f)        ; #f = the standard readtable
  ;; arguments after `readtable` come in (char mode action) triples:

  char  : (or/c char? #f)                 ; the character to (re)define
  mode  : (or/c 'terminating-macro
                'non-terminating-macro
                'dispatch-macro
                char?)                    ; an existing char to mimic
  action :
    ;; when mode is 'terminating-macro / 'non-terminating-macro / 'dispatch-macro:
    (or/c procedure?)                     ; reader proc, must accept arity 2 AND 6
    ;; when mode is a char?:
    (or/c readtable? #f)                  ; readtable to inherit char's mapping
                                          ;   from, or #f for the standard one
```

- `'dispatch-macro` registers `char` as the character *after* `#`
  (so `#\$` + `'dispatch-macro` handles `#$`).
- mode = char remaps `char` to parse exactly like that existing char.
  Remap both members of a bracket pair (`{`→`(` and `}`→`)`).
- `char` = `#f` with a char mode adjusts the treatment of all otherwise
  self-delimiting characters — rarely needed.

## Readtable predicates, introspection, parameter

```racket
(readtable? v) -> boolean?

(current-readtable) -> (or/c readtable? #f)        ; parameter; default #f
(current-readtable rt) -> void?                    ; rt : (or/c readtable? #f)
;; read / read-syntax consult current-readtable.

(readtable-mapping rt char)
  -> (values (or/c char? 'terminating-macro 'non-terminating-macro)
             (or/c procedure? #f)
             (or/c procedure? #f))
  ;; 1st value: how char parses (a char if remapped, else the macro kind)
  ;; 2nd value: the non-dispatch reader proc, or #f
  ;; 3rd value: the dispatch (#-prefixed) reader proc, or #f
  ;; Does NOT report the standard meaning of an unmodified char.
```

## Reader-extension procedure protocol

A reader proc is called two ways and must accept both arities:

```racket
(proc char in)                          ; from `read`
(proc char in src line col position)    ; from `read-syntax`
  char     : char?                      ; the triggering char, already read
  in       : input-port?
  src      : any/c                      ; source name passed to read-syntax
  line     : (or/c exact-positive-integer? #f)   ; #f unless line counting on
  col      : (or/c exact-nonnegative-integer? #f)
  position : (or/c exact-positive-integer? #f)
```

Result conventions:

- Return the datum (read mode) or syntax object (read-syntax mode) the
  characters denote. A non-syntax result in read-syntax mode is coerced via
  `datum->syntax`, discarding source locations.
- Return `(make-special-comment v)` to indicate the characters were a
  comment and yield no datum. `v` is ignored by `read`/`read-syntax`.
- Returning zero values is **not** allowed and raises an arity error.
- Enable line/column tracking on the port with `(port-count-lines! in)` if
  the proc needs non-`#f` `line`/`col`; `position` is available regardless.

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
  ;; gates #lang/#! specifically (also requires read-accept-reader)
```

`#reader module-path datum` loads `module-path`, which must provide `read`
and `read-syntax`, and uses them to read the following input.

## Error helpers (require syntax/readerr)

```racket
(raise-read-error msg-string src line col pos span) -> any
(raise-read-eof-error msg-string src line col pos span) -> any
  ;; span : (or/c exact-nonnegative-integer? #f)
  ;; raise an exn:fail:read (or exn:fail:read:eof) with location info.
```

## syntax/module-reader options

A `lang/reader.rkt` written in `#lang s-exp syntax/module-reader` declares
the module language on the first line, then accepts keyword options:

```racket
#lang s-exp syntax/module-reader
module-language-path
#:read         read-proc            ; default: read
#:read-syntax  read-syntax-proc     ; default: read-syntax
#:wrapper1     (-> (-> any) any)    ; wraps the read thunk; parameterize here
#:wrapper2     (-> input-port (-> input-port any) any)  ; sees the port too
#:whole-body-readers? boolean?      ; reader returns the whole module body
#:info         proc                 ; DrRacket/`get-info` hook
#:language-info ...                 ; runtime get-info
require-spec ...                    ; bindings available to the options above
```

The standard way to install a custom readtable for a `#lang`:

```racket
#:wrapper1 (lambda (t) (parameterize ([current-readtable my-rt]) (t)))
```

`#lang name` resolves the reader at `name/lang/reader`; the collection's
`name/main.rkt` (or the declared module-language-path) supplies the bindings
that programs expand into.
