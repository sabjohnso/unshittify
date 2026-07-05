# Concurrency Reference — exact signatures

Companion to SKILL.md. Source: docs.racket-lang.org/reference/ "Concurrency
and Parallelism" (threads, sync, channels, semaphores, futures, places,
custodians). Checked against Racket v9.1 [cs].

## Threads (racket/base)

```racket
(thread thunk) -> thread?              ; thunk : (-> any); runs concurrently
(thread/suspend-to-kill thunk)
(thread-wait t)                        ; block until t terminates
(thread-dead-evt t) -> evt?            ; ready when t has ended
(thread-running? t)  (thread-dead? t)
(kill-thread t)                        ; force-terminate (no unwinding)
(break-thread t [kind])                ; raise exn:break in t (cooperative)
(thread-suspend t) (thread-resume t [benefactor])
(current-thread) -> thread?   (thread? v)   (sleep [secs])
```

### Thread mailbox

```racket
(thread-send t v [fail-thunk])         ; enqueue v to t's mailbox (async)
(thread-receive) -> any                ; dequeue (blocks); for the current thread
(thread-try-receive) -> any/c          ; dequeue or #f if empty
(thread-receive-evt) -> evt?           ; ready when a message is available
(thread-rewind-receive lst)            ; push messages back
```

## Channels (synchronous, racket/base)

```racket
(make-channel) -> channel?
(channel-get ch) -> any                ; blocks until a put rendezvous
(channel-put ch v)                     ; blocks until a get rendezvous
(channel-put-evt ch v) -> evt?         ; event that does the put when chosen
(channel? v)
```

## Async channels (require racket/async-channel)

```racket
(make-async-channel [limit]) -> async-channel?   ; limit = buffer bound or #f
(async-channel-put ac v)               ; returns immediately (blocks only at limit)
(async-channel-get ac) -> any          ; blocks if empty
(async-channel-put-evt ac v) -> evt?
(async-channel? v)
;; NOTE: the async-channel value IS its get-event — (sync ac) yields a value.
;; there is no async-channel-get-evt.
```

## Semaphores (racket/base)

```racket
(make-semaphore [init]) -> semaphore?  ; init counter (default 0)
(semaphore-post s)  (semaphore-wait s)
(semaphore-try-wait? s) -> boolean?    ; non-blocking
(semaphore-wait/enable-break s)
(semaphore-peek-evt s) -> evt?         ; ready when post>0, without taking
(call-with-semaphore s thunk [try-fail-thunk arg ...])         ; wait/post around thunk
(call-with-semaphore/enable-break s thunk [try-fail arg ...])
(semaphore? v)
```

## Synchronizable events (racket/base)

```racket
(sync evt ...) -> any                   ; block until one is ready; its value
(sync/timeout timeout-secs-or-#f evt ...) ; #f / a thunk on timeout
(sync/enable-break evt ...)
(evt? v)  (handle-evt? v)

(handle-evt evt proc)                   ; proc on the value; KEEPS tail position
(wrap-evt evt proc)                     ; proc on the value; proc must not sync
(choice-evt evt ...)                    ; ready when any is
(guard-evt (lambda () evt))             ; make the event at sync time
(nack-guard-evt (lambda (nack-evt) evt)); nack-evt becomes ready if NOT chosen
(replace-evt evt (lambda (v) evt2))     ; chain: sync evt, then evt2
always-evt   never-evt                  ; immediately ready / never
(alarm-evt absolute-ms [monotonic?])    ; ready at a wall-clock time
(system-idle-evt) -> evt?
```

Built-in event sources: channels, `channel-put-evt`, semaphores,
`semaphore-peek-evt`, threads (`thread-dead-evt`), an async-channel itself,
ports (`port-progress-evt`, `eof-evt`), `thread-receive-evt`, subprocesses,
TCP listeners, custodian boxes.

## Futures (require racket/future)

```racket
(future thunk) -> future?              ; may run in parallel if future-safe
(touch f) -> any                       ; wait for and return the result
(futures-enabled?) -> boolean?
(would-be-future thunk)                ; a future that logs blocking, for tuning
(current-future) -> (or/c future? #f)
(processor-count) -> exact-positive-integer?
;; fsemaphore: future-safe semaphore
(make-fsemaphore init) (fsemaphore-post s) (fsemaphore-wait s)
(fsemaphore-try-wait? s) (fsemaphore-count s) (fsemaphore? v)
```

## Places (require racket/place)

```racket
(place id body ...+)                   ; id names the place-channel inside body;
                                       ;   must appear at module level
(place* id #:in ... body ...)          ; with custom ports
(dynamic-place module-path start-name) ; start a place from a module's function
(place-channel) -> (values pch pch)    ; a fresh bidirectional pair
(place-channel-put pch v)              ; send (v must be place-message-allowed?)
(place-channel-get pch) -> any
(place-channel-put/get pch v) -> any   ; put then get
(place-wait p) -> exact-integer?       ; wait; returns exit status
(place-dead-evt p) -> evt?
(place-break p [kind])  (place-kill p)
(place-message-allowed? v) -> boolean?
(place-enabled?) -> boolean?  (place? v)  (place-channel? v)
```

Allowed place messages are flat/immutable data: numbers, characters,
booleans, interned symbols, immutable strings/byte strings, immutable
prefab structs and immutable vectors/hashes of allowed values, plus
place-channels and file-stream/byte-string ports.

## Custodians (racket/base)

```racket
(make-custodian [parent]) -> custodian?
(current-custodian) -> custodian?      ; parameter; new threads/ports join it
(custodian-shutdown-all cust)          ; terminate every managed resource
(custodian-managed-list cust super)    ; what cust (a child of super) owns
(make-custodian-box cust v) -> custodian-box?   ; v kept alive while cust lives
(custodian-box-value cb)               ; v, or #f after shutdown
(custodian? v)  (custodian-box? v)
```

Threads, ports, TCP listeners, places, and child custodians created while
`current-custodian` is a given custodian are owned by it; shutting it down
reclaims them. Parameterize `current-custodian` to scope a subsystem.
