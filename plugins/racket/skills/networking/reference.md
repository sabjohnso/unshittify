# Networking / Web Reference — signatures

This file accompanies SKILL.md. Sources: docs.racket-lang.org/reference/ (networking)
and docs.racket-lang.org/web-server/. The signatures agree with Racket v9.1 [cs].

## racket/tcp

```racket
(tcp-listen port-no [max-allow-wait reuse? hostname-or-#f]) -> tcp-listener?
   ; port-no 0 => the OS chooses an ephemeral port
(tcp-accept listener) -> (values input-port? output-port?)   ; waits
(tcp-accept/enable-break listener) -> (values in out)
(tcp-accept-evt listener) -> evt?                ; ready -> (list in out)
(tcp-connect hostname port-no [local-host local-port]) -> (values in out)
(tcp-connect/enable-break ...) 
(tcp-addresses tcp-port-or-listener [port-numbers?])
   -> (values local-host remote-host) or 4 values, if port-numbers? is true
(tcp-close listener)   (tcp-listener? v)   (tcp-port? v)
(tcp-abandon-port tcp-port)                      ; closes one direction
```

## racket/udp

```racket
(udp-open-socket [family-hostname family-port]) -> udp?
(udp-bind! sock hostname-or-#f port-no [reuse?])
(udp-connect! sock hostname-or-#f port-no-or-#f)
(udp-send-to sock hostname port-no bytes [start end])   ; socket not connected
(udp-send    sock bytes [start end])                    ; socket connected
(udp-receive! sock bytes [start end]) -> (values len host port)   ; waits
(udp-receive!* sock bytes ...)                  ; does not wait, len is #f if no datagram
(udp-send-to-evt sock host port bytes) -> evt?  (udp-receive!-evt sock bytes) -> evt?
(udp-addresses sock [port-numbers?])   (udp-close sock)   (udp? v)
(udp-multicast-join-group! sock addr iface)  ; also leave / loopback / ttl / interface
```

## net/url

```racket
(struct url (scheme user host port path-absolute? path query fragment))
   ; path : (listof path/param) ; query : (listof (cons symbol (or/c string #f)))
(string->url str) -> url?      (url->string u) -> string?
(combine-url/relative base str) -> url?
(path->url path) -> url?       (url->path u) -> path?
;; ports (each takes a url; "pure" drops the headers, "impure" keeps them):
(get-pure-port    u [headers #:redirections n]) -> input-port?
(get-impure-port  u [headers]) -> input-port?       ; response with status and headers
(post-pure-port   u data [headers]) -> input-port?
(post-impure-port u data [headers]) -> input-port?
(put-pure-port u data [headers])  (delete-pure-port u [headers])
(head-pure-port u [headers])      (head-impure-port u [headers])
(call/input-url u connect handle [headers]) -> any   ; opens, calls handle, closes
(purify-port in) -> string     ; reads and removes the header block of an impure port
```

## net/http-client

```racket
(http-sendrecv host uri
               [#:ssl? bool-or-protocol] [#:port n] [#:method bytes-or-str]
               [#:headers (listof string/bytes)] [#:data bytes-or-#f]
               [#:content-decode '(gzip deflate)])
   -> (values status-bytes  (listof bytes)-headers  input-port-body)
;; connection-oriented (these reuse a connection):
(http-conn-open  host [#:ssl? _ #:port _]) -> http-conn?
(http-conn-open! conn host ...) 
(http-conn-send! conn uri [#:method _ #:headers _ #:data _])
(http-conn-recv! conn [#:method _ #:close? _]) -> (values status headers body)
(http-conn-close! conn)   (http-conn? v)   (http-conn-live? v)
```

## net/uri-codec, net/base64

```racket
(uri-encode str) (uri-decode str)        (uri-path-segment-encode str) ...
(form-urlencoded->alist str) -> (listof (cons symbol string))
(alist->form-urlencoded alist) -> string
(current-alist-separator-mode)           ; values: '& or '; or 'amp ...
(base64-encode bytes [linesep]) -> bytes   (base64-decode bytes) -> bytes
```

## json

```racket
(jsexpr? v)        ; (or/c (hash/c symbol? jsexpr?) (listof jsexpr?)
                   ;       string exact-integer inexact-real boolean json-null)
                   ; object keys must be symbols: (jsexpr? (hash "n" 42)) is #f
(read-json [in])   (write-json v [out])
(string->jsexpr str) -> jsexpr     (jsexpr->string v) -> string
   ; both writers write object keys in sorted order, not in insertion order
(json-null) -> 'null               ; a parameter, the value for JSON null
```

## web-server/servlet-env

```racket
(serve/servlet handler            ; (-> request? response?) ; or a dispatcher
  [#:port n] [#:listen-ip ip-or-#f] [#:servlet-path str]
  [#:servlet-regexp rx]           ; the paths that go to `handler` (#rx"" = all)
  [#:launch-browser? bool] [#:command-line? bool]   ; #:command-line? #t: no extra setup
  [#:stateless? bool] [#:server-root-path dir]
  [#:extra-files-paths (listof dir)]                ; serves static files
  [#:log-file path] [#:ssl? bool] [#:ssl-cert path] [#:ssl-key path]) -> void
```

## web-server/http

```racket
;; request
(struct request (method uri headers/raw bindings/raw post-data/raw
                 host-ip host-port client-ip))
(request-method req) -> bytes        (request-uri req) -> url?
(request-bindings/raw req) -> (listof binding?)
(request-headers/raw req) -> (listof header?)
(bindings-assq key-bytes binds) -> (or/c binding? #f)
(headers-assq  key-bytes hdrs)  -> (or/c header? #f)
(binding:form? b) (binding:form-value b) -> bytes
(binding:file? b) (binding:file-filename b) (binding:file-content b)
;; header
(make-header field-bytes value-bytes) -> header?   (header-field h) (header-value h)
;; response
(struct response (code message seconds mime headers output))
(response/output output-proc [#:code n #:message bytes #:seconds s
                              #:mime-type bytes #:headers (listof header?)]) -> response?
   ; output-proc : (output-port -> any)
(response/full code message seconds mime-type headers (listof bytes)) -> response?
(response/xexpr xexpr [#:code _ #:headers _ #:mime-type _ #:preamble _]) -> response?
   ; renders an X-expression and escapes the HTML
(redirect-to url-string [status #:headers _]) -> response?   ; status is permanently, see-other, or temporarily
```

## web-server/dispatch

```racket
(dispatch-rules [dispatch-pattern maybe-method handler] ... [else handler])
   -> (values dispatch url-generator)
   dispatch-pattern = (seg ...) ; seg = "literal" | (string-arg) | (integer-arg)
                                ;             | (number-arg) | (real-arg) | (symbol-arg)
   maybe-method     = #:method (or "get" "post" regexp ...)
(dispatch-rules+applies [pattern handler] ... [else handler])
   -> (values dispatch url-generator applies?)   ; applies? : (request? -> boolean?)
(dispatch-rules! ...)                        ; like dispatch-rules, with a mutable rule set
(dispatch-case [pattern handler] ... [else handler])     ; the dispatch function only, no url generator
(dispatch-url  [pattern handler] ...)                    ; the url generator only
(serve/dispatch dispatch) -> void
   ; calls serve/servlet with #:servlet-regexp #rx"" so that every request reaches dispatch
(define-container id ...)  (container? v)
;; NOTE: define-dispatch-rules does not exist. The export list of
;; web-server/dispatch is the identifiers named in this section and no others.
```

## web-server/web-server (embed a server)

```racket
(serve #:dispatch dispatcher [#:port n #:listen-ip _ #:max-waiting _
       #:connection-timeout _ #:tcp@ _]) -> (-> void)     ; returns a thunk that shuts down the server
(serve/ports #:dispatch d #:ports (list n ...)) -> (-> void)
;; dispatchers can combine: web-server/dispatchers/* (filter, sequencer, files, servlet)
```

Other useful modules: `web-server/templates` (`include-template` for HTML
templates), `web-server/formlets` (forms that you can combine),
`web-server/servlet` (`send/suspend` and `send/suspend/dispatch` for control flow
with continuations), `net/cookies/server` and `net/cookies/common` (cookies).
