---
name: networking
description: Networking and web servers in Racket — TCP/UDP sockets (racket/tcp, racket/udp), HTTP clients (net/url, net/http-client), JSON (json), and the web-server stack (serve/servlet, dispatch-rules routing, request/response, response/xexpr). Use when writing a network client or server, calling an HTTP API, parsing/producing JSON, building a web app or REST endpoint, or testing servers headlessly.
---

# Networking and Web Servers

Three layers, lowest to highest:

- **Sockets** — `racket/tcp` and `racket/udp` give you raw connections as
  ordinary Racket ports.
- **HTTP client** — `net/url` for quick GET/POST, `net/http-client` for full
  control of method/headers/body.
- **Web server** — `web-server` serves HTTP, with routing, request/response
  values, and a quick-start launcher.

Servers are inherently concurrent (a thread per connection) and resource-
owning (ports, listeners) — `[[concurrency]]`'s threads and custodians are
the tools that keep them correct and shutdownable.

## TCP

A server listens and accepts; a client connects. Both sides get a normal
input port and output port:

```racket
(require racket/tcp)
(define listener (tcp-listen 0 4 #t "127.0.0.1"))     ; port 0 = OS picks one
(define-values (host port _ph _pp) (tcp-addresses listener #t))  ; read it back

;; accept loop: one thread per connection (see [[concurrency]])
(thread (lambda ()
  (let loop ()
    (define-values (in out) (tcp-accept listener))
    (thread (lambda () (handle in out) (close-output-port out) (close-input-port in)))
    (loop))))

;; client
(define-values (cin cout) (tcp-connect "127.0.0.1" port))
(write-string "hi\n" cout) (flush-output cout)
(read-line cin)
```

Run the accept loop and its connection threads under a `make-custodian` so
`custodian-shutdown-all` closes every socket at once.

## UDP

Connectionless datagrams — open a socket, optionally bind, send and receive
into a buffer:

```racket
(require racket/udp)
(define s (udp-open-socket))
(udp-bind! s "127.0.0.1" 0)
(udp-send-to s "127.0.0.1" peer-port #"ping")
(define buf (make-bytes 1024))
(define-values (len from-host from-port) (udp-receive! s buf))   ; blocks
```

## HTTP client

For simple requests, `net/url`:

```racket
(require net/url racket/port)
(port->string (get-pure-port (string->url "https://example.com/data")))
(port->string (post-pure-port (string->url "https://example.com/api") #"body=1"))
```

`get-pure-port` skips response headers; `get-impure-port` keeps them (parse
with `purify-port`). For method/header/body control, `net/http-client`:

```racket
(require net/http-client)
(define-values (status headers body)
  (http-sendrecv "example.com" "/api" #:ssl? #t #:method #"POST"
                 #:headers (list "Content-Type: application/json")
                 #:data (jsexpr->string (hash 'name "Ada"))))
```

The `net/http-easy` package offers a friendlier client (sessions, JSON,
auth), but it is a separate install (`[[packages]]`), not in the base
distribution.

## JSON

`json` is the API exchange format: `jsexpr`s are hashes (string-or-symbol
keys), lists, strings, numbers, booleans, and `(json-null)`:

```racket
(require json)
(jsexpr->string (hash 'ok #t 'n 42))        ; => "{\"ok\":true,\"n\":42}"
(string->jsexpr "{\"n\":42}")                ; => (hash 'n 42)
(read-json a-port)  (write-json v a-port)    ; stream from/to ports
```

## Web server

`serve/servlet` (from `web-server/servlet-env`) starts a server with one
handler. Route requests with `dispatch-rules`, and build replies with the
`web-server/http` response constructors:

```racket
(require web-server/servlet-env web-server/http web-server/dispatch json)

(define-values (dispatch _url)
  (dispatch-rules
   [("hello" (string-arg)) (lambda (req name)
                             (response/xexpr `(html (body (p "hi " ,name)))))]
   [("api") #:method "get" (lambda (req)
                             (response/output #:mime-type #"application/json"
                               (lambda (out) (write-json (hash 'n 42) out))))]
   [else (lambda (req) (response/full 404 #"Not Found" (current-seconds)
                                      #"text/plain" '() (list #"missing")))]))

(serve/servlet dispatch
               #:port 8080
               #:servlet-regexp #rx""        ; send every path to `dispatch`
               #:launch-browser? #f)
```

- **Routing:** `dispatch-rules` patterns mix literal segments with typed
  captures — `(string-arg)`, `(integer-arg)`, `(symbol-arg)` — bound as extra
  handler arguments; `#:method` restricts the verb; `else` is the fallback.
- **Request:** `web-server/http` exposes `request-method`,
  `request-uri`, `request-bindings/raw` + `bindings-assq`, and
  `binding:form-value` to read form data; `request-headers/raw` +
  `headers-assq` for headers.
- **Response:** `response/xexpr` renders an X-expression to HTML (and
  **escapes it**); `response/output` writes a body via a callback with a
  `#:mime-type`; `response/full` controls code/headers/body bytes exactly.
- **Running for real:** `serve/servlet` blocks. To embed a server, the lower
  `serve` (`web-server/web-server`) returns a *shutdown thunk*; run it under a
  custodian and call the thunk to stop.

## Testing servers headlessly

Start the server under a custodian in a thread, fetch with `net/url`, then
shut it down — a self-contained integration test ([[rackunit]]):

```racket
(define cust (make-custodian))
(parameterize ([current-custodian cust])
  (thread (lambda () (serve/servlet dispatch #:port 8231 #:servlet-regexp #rx""
                                    #:launch-browser? #f #:command-line? #t))))
(sleep 1)                                     ; let it bind
(check-equal? (port->string (get-pure-port (string->url "http://127.0.0.1:8231/hello/Ada")))
              "<html>…hi Ada…</html>")
(custodian-shutdown-all cust)                 ; stop the server
```

## Rules that prevent rework

- **One thread per connection, bounded by a custodian.** Spawn a handler
  thread per `tcp-accept`/connection so a slow client can't block others, and
  create them under a custodian so one `custodian-shutdown-all` closes
  everything ([[concurrency]]).
- **Escape output; never trust input.** Build HTML with `response/xexpr`
  (it escapes) rather than string-concatenating request data, and validate
  every binding before use — request data is attacker-controlled (a security
  baseline; don't let one unchecked input compromise the server).
- **`net/url` for simple, `net/http-client` for control.** Use `get-pure-port`
  /`post-pure-port` for plain fetches; reach for `http-sendrecv` when you need
  a specific method, headers, TLS, or to read the status line.
- **Use ephemeral port `0` in tests.** Let the OS assign a free port and read
  it back with `tcp-addresses`, so concurrent test runs don't collide.
- **`serve` (with its shutdown thunk) for embedded servers.**
  `serve/servlet` blocks and is for apps and tests; to run a server inside a
  larger program, use the lower-level `serve` and keep the thunk to stop it.
- **Close ports and stop listeners.** Wrap connection handling so ports close
  on error, and shut down listeners/custodians on exit; leaked sockets
  exhaust file descriptors.
