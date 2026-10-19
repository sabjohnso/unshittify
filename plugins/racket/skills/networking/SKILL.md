---
description: Networks and web servers in Racket. Covers TCP and UDP sockets (racket/tcp, racket/udp), HTTP clients (net/url, net/http-client), JSON (json), and the web-server stack (serve/servlet, dispatch-rules routes, request and response, response/xexpr). Use when you write a network client or server, when you call an HTTP API, when you parse or produce JSON, when you build a web application or a REST endpoint, or when you test a server with no display.
allowed-tools: Read, Grep, Glob
---

# Networks and web servers

There are three layers, from the lowest to the highest:

For the exact signatures across `racket/tcp`, `racket/udp`, `net/url`,
`net/http-client`, and the web-server forms, read `reference.md` in this
skill directory.

- **Sockets.** `racket/tcp` and `racket/udp` give you raw connections as
  ordinary Racket ports.
- **HTTP client.** `net/url` for a quick GET or POST. `net/http-client` for
  full control of the method, the headers, and the body.
- **Web server.** `web-server` serves HTTP, with routes, request and
  response values, and a quick-start launcher.

A server is concurrent by nature (a thread per connection), and it owns
resources (ports, listeners). The threads and the custodians of
`../concurrency/SKILL.md` are the tools that keep a server correct and easy
to shut down.

## TCP

A server listens and accepts. A client connects. Both sides get a normal
input port and output port:

```racket
(require racket/tcp)
(define listener (tcp-listen 0 4 #t "127.0.0.1"))     ; port 0: the OS picks one
(define-values (host port _ph _pp) (tcp-addresses listener #t))  ; read it back

;; the accept loop: one thread per connection (see ../concurrency/SKILL.md)
(thread (lambda ()
  (let loop ()
    (define-values (in out) (tcp-accept listener))
    (thread (lambda () (handle in out) (close-output-port out) (close-input-port in)))
    (loop))))

;; the client
(define-values (cin cout) (tcp-connect "127.0.0.1" port))
(write-string "hi\n" cout) (flush-output cout)
(read-line cin)
```

Run the accept loop and its connection threads under a `make-custodian`.
Then `custodian-shutdown-all` closes every socket at once.

## UDP

UDP sends datagrams with no connection. Open a socket, bind it if
necessary, then send and receive into a buffer:

```racket
(require racket/udp)
(define s (udp-open-socket))
(udp-bind! s "127.0.0.1" 0)
(udp-send-to s "127.0.0.1" peer-port #"ping")
(define buf (make-bytes 1024))
(define-values (len from-host from-port) (udp-receive! s buf))   ; waits
```

## HTTP client

For a simple request, use `net/url`:

```racket
(require net/url racket/port)
(port->string (get-pure-port (string->url "https://example.com/data")))
(port->string (post-pure-port (string->url "https://example.com/api") #"body=1"))
```

`get-pure-port` skips the response headers. `get-impure-port` keeps them
(parse them with `purify-port`). For control of the method, the headers,
and the body, use `net/http-client`:

```racket
(require net/http-client)
(define-values (status headers body)
  (http-sendrecv "example.com" "/api" #:ssl? #t #:method #"POST"
                 #:headers (list "Content-Type: application/json")
                 #:data (jsexpr->string (hash 'name "Ada"))))
```

The `net/http-easy` package gives a simpler client (sessions, JSON, auth).
But it is a separate install (`../packages/SKILL.md`). It is not in the base
distribution.

## JSON

The `json` module handles JSON, the usual format for an API exchange. A
`jsexpr` is a hash with **symbol keys only**, a list, a string, a number, a
boolean, or `(json-null)`. A string key is not a legal jsexpr. `(jsexpr?
(hash "n" 42))` is `#f`, and `jsexpr->string` on it raises `expected argument
of type <legal JSON key value>`.

```racket
(require json)
(jsexpr->string (hash 'ok #t 'n 42))        ; => "{\"n\":42,\"ok\":true}"  (sorted keys)
(string->jsexpr "{\"n\":42}")                ; => (hasheq 'n 42), a hasheq, not a hash
(read-json a-port)  (write-json v a-port)    ; stream from a port or to a port
```

`jsexpr->string` and `write-json` emit the object keys in sorted order, not
in the order of insertion. So do not assert on the exact text of an object
with several keys. Compare the parsed `jsexpr` instead.

## Web server

`serve/servlet` (from `web-server/servlet-env`) starts a server with one
handler. Route the requests with `dispatch-rules`. Build the replies with
the response constructors of `web-server/http`:

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

- **Routes.** A `dispatch-rules` pattern mixes literal segments with typed
  captures (`(string-arg)`, `(integer-arg)`, `(symbol-arg)`). The captures
  become extra handler arguments. `#:method` restricts the verb. `else` is
  the fallback.
- **The request.** `web-server/http` gives `request-method`,
  `request-uri`, `request-bindings/raw` plus `bindings-assq`, and
  `binding:form-value` to read form data. It gives `request-headers/raw` plus
  `headers-assq` for the headers.
- **The response.** `response/xexpr` renders an X-expression to HTML (and
  **escapes it**). `response/output` writes a body through a callback, with
  a `#:mime-type`. `response/full` controls the code, the headers, and the
  body bytes exactly.
- **A real run.** `serve/servlet` blocks. To embed a server, the lower
  `serve` (`web-server/web-server`) returns a *shutdown thunk*. Run it under
  a custodian, and call the thunk to stop the server.

## Test a server with no display

Start the server under a custodian in a thread, fetch with `net/url`, then
shut it down. That is a self-contained integration test
(`../rackunit/SKILL.md`):

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

- **One thread per connection, under a custodian.** Start a handler thread
  per `tcp-accept` or connection, so a slow client cannot block the others.
  Create the threads under a custodian, so one `custodian-shutdown-all`
  closes everything (`../concurrency/SKILL.md`).
- **Escape the output. Never trust the input.** Build HTML with
  `response/xexpr` (it escapes). Do not concatenate request data into a
  string. Validate every binding before you use it. Request data is under
  the control of an attacker. That is a security baseline. Do not let one
  unchecked input compromise the server.
- **`net/url` for a simple request, `net/http-client` for control.** Use
  `get-pure-port` and `post-pure-port` for a plain fetch. Use
  `http-sendrecv` when you need a specific method, headers, TLS, or the
  status line.
- **Use the ephemeral port `0` in a test.** Let the OS assign a free port,
  and read it back with `tcp-addresses`. Then concurrent test runs do not
  collide.
- **Use `serve` (with its shutdown thunk) for an embedded server.**
  `serve/servlet` blocks, and it is for applications and tests. To run a
  server inside a larger program, use the lower-level `serve`, and keep the
  thunk to stop it.
- **Close the ports, and stop the listeners.** Wrap the connection handler,
  so the ports close on an error. Shut down the listeners and the custodians
  at exit. A leaked socket exhausts the file descriptors.
