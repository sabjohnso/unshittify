# Concurrency Reference: exact signatures

This file accompanies SKILL.md. Source: docs.racket-lang.org/reference/ "Concurrency
and Parallelism" (threads, sync, channels, semaphores, futures, places,
custodians). The signatures match Racket v9.1 [cs].

## Threads (racket/base)

```racket
(thread thunk) -> thread?              ; thunk : (-> any); runs at the same time
(thread/suspend-to-kill thunk)
(thread-wait t)                        ; wait until t stops
(thread-dead-evt t) -> evt?            ; ready when t ends
(thread-running? t)  (thread-dead? t)
(kill-thread t)                        ; stop t by force (no unwinding)
(break-thread t [kind])                ; raise exn:break in t (t must cooperate)
(thread-suspend t) (thread-resume t [benefactor])
(current-thread) -> thread?   (thread? v)   (sleep [secs])
```

### Thread mailbox

```racket
(thread-send t v [fail-thunk])         ; add v to the mailbox of t (asynchronous)
(thread-receive) -> any                ; remove a message (blocks); for the current thread
(thread-try-receive) -> any/c          ; remove a message, or #f if empty
(thread-receive-evt) -> evt?           ; ready when a message is available
(thread-rewind-receive lst)            ; put messages back
```

## Channels (synchronous, racket/base)

```racket
(make-channel) -> channel?
(channel-get ch) -> any                ; blocks until a put meets it
(channel-put ch v)                     ; blocks until a get meets it
(channel-put-evt ch v) -> evt?         ; event that does the put when sync chooses it
(channel? v)
```

## Async channels (require racket/async-channel)

```racket
(make-async-channel [limit]) -> async-channel?   ; limit = size of the buffer or #f
(async-channel-put ac v)               ; returns at once (blocks only at the limit)
(async-channel-get ac) -> any          ; blocks if empty
(async-channel-put-evt ac v) -> evt?
(async-channel? v)
;; NOTE: the async-channel value IS its get-event. (sync ac) returns a value.
;; There is no async-channel-get-evt.
```

## Semaphores (racket/base)

```racket
(make-semaphore [init]) -> semaphore?  ; init = start value of the counter (default 0)
(semaphore-post s)  (semaphore-wait s)
(semaphore-try-wait? s) -> boolean?    ; does not block
(semaphore-wait/enable-break s)
(semaphore-peek-evt s) -> evt?         ; ready when post>0, does not take the count
(call-with-semaphore s thunk [try-fail-thunk arg ...])         ; wait before thunk, post after thunk
(call-with-semaphore/enable-break s thunk [try-fail arg ...])
(semaphore? v)
```

## Synchronizable events (racket/base)

```racket
(sync evt ...) -> any                   ; block until one is ready; returns its value
(sync/timeout timeout-secs-or-#f evt ...) ; on timeout: #f, or the result of a thunk
(sync/enable-break evt ...)
(evt? v)  (handle-evt? v)

(handle-evt evt proc)                   ; proc gets the value; proc KEEPS tail position
(wrap-evt evt proc)                     ; proc gets the value; proc must not sync
(choice-evt evt ...)                    ; ready when any evt is ready
(guard-evt (lambda () evt))             ; make the event at sync time
(nack-guard-evt (lambda (nack-evt) evt)); nack-evt becomes ready if sync does NOT choose evt
(replace-evt evt (lambda (v) evt2))     ; chain: sync evt, then evt2
always-evt   never-evt                  ; ready at once / never ready
(alarm-evt absolute-ms [monotonic?])    ; ready at a clock time
(system-idle-evt) -> evt?
```

The built-in event sources are: channels, `channel-put-evt`, semaphores,
`semaphore-peek-evt`, threads (`thread-dead-evt`), an async-channel itself,
ports (`port-progress-evt`, `eof-evt`), `thread-receive-evt`, subprocesses,
TCP (Transmission Control Protocol) listeners, and custodian boxes.

## Futures (require racket/future)

```racket
(future thunk) -> future?              ; can run in parallel if future-safe
(touch f) -> any                       ; wait for the result and return it
(futures-enabled?) -> boolean?
(would-be-future thunk)                ; a future that logs each block, to help tuning
(current-future) -> (or/c future? #f)
(processor-count) -> exact-positive-integer?
;; fsemaphore: future-safe semaphore
(make-fsemaphore init) (fsemaphore-post s) (fsemaphore-wait s)
(fsemaphore-try-wait? s) (fsemaphore-count s) (fsemaphore? v)
```

## Places (require racket/place)

```racket
(place id body ...+)                   ; id names the place-channel in body;
                                       ;   must appear at module level
(place* maybe-port ... id body ...+)   ; with custom ports; the KEYWORDS MUST COME
                                       ;   FIRST, before id:
                                       ;   (place* #:in in #:out out #:err err
                                       ;           pch body ...+)
                                       ; maybe-port = #:in in | #:out out | #:err err
(dynamic-place module-path start-name) ; start a place from a function of a module
(place-channel) -> (values pch pch)    ; a new pair that carries messages in both directions
(place-channel-put pch v)              ; send v (v must be place-message-allowed?)
(place-channel-get pch) -> any
(place-channel-put/get pch v) -> any   ; put, then get
(place-wait p) -> exact-integer?       ; wait, then return the exit status
(place-dead-evt p) -> evt?
(place-break p [kind])  (place-kill p)
(place-message-allowed? v) -> boolean?
(place-enabled?) -> boolean?  (place? v)  (place-channel? v)
```

A place message must be flat or immutable data. The allowed data are: numbers, characters,
booleans, interned symbols, immutable strings/byte strings, immutable
prefab structs and immutable vectors/hashes of allowed values, place-channels,
and file-stream/byte-string ports.

## Custodians (racket/base)

```racket
(make-custodian [parent]) -> custodian?
(current-custodian) -> custodian?      ; parameter; new threads/ports join it
(custodian-shutdown-all cust)          ; stop every managed resource
(custodian-managed-list cust super)    ; the resources that cust (a child of super) owns
(make-custodian-box cust v) -> custodian-box?   ; v stays alive while cust lives
(custodian-box-value cb)               ; v, or #f after shutdown
(custodian? v)  (custodian-box? v)
```

A custodian owns each thread, port, TCP listener, place, and child custodian
that is created while `current-custodian` is that custodian. When you shut the
custodian down, it reclaims them. Use `parameterize` on `current-custodian` to limit the scope of a subsystem.
