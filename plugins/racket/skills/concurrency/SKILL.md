---
name: concurrency
description: Concurrency and parallelism in Racket — green threads, synchronous channels and thread mailboxes, async-channels, semaphores, the synchronizable-event system (sync, handle-evt, choice-evt, alarm-evt), real parallelism with futures and places, and resource lifecycle with custodians. Use when coordinating threads, choosing a communication mechanism, waiting on multiple events, parallelizing CPU work, or cleaning up groups of threads/ports.
---

# Concurrency and Parallelism in Racket

Racket separates two things people conflate:

- **Concurrency** — `thread` creates *green threads* that interleave on one
  OS thread within a place. They are cheap and preemptively scheduled, but do
  **not** run simultaneously, so they give responsiveness and structure, not
  CPU speedup.
- **Parallelism** — `future` and `place` actually use multiple cores.
  `places` have separate memory and talk by message; `futures` parallelize
  allocation-light, "future-safe" work.

Pick by need: threads to *organize* concurrent activity, futures/places to
*speed up* CPU-bound work.

## Threads

```racket
(define t (thread (lambda () (do-work))))
(thread-wait t)                  ; block until t finishes
(break-thread t)                 ; request cancellation (raises exn:break in t)
(kill-thread t)                  ; force-terminate (no cleanup) — prefer break
(sleep 0.1)                      ; yield for a while
```

Cooperative cancellation is cleaner than `kill-thread`: have the thread guard
with `exn:break?` so it can release resources:

```racket
(thread (lambda ()
          (with-handlers ([exn:break? (lambda (_) (cleanup))])
            (let loop () (sleep 0.01) (loop)))))
```

## Communicating between threads

Prefer passing messages to sharing mutable state. Three mechanisms:

- **Synchronous channels** (`make-channel`) — a *rendezvous*: `channel-put`
  blocks until another thread `channel-get`s, and vice versa. No buffer; the
  hand-off itself synchronizes the two threads.

  ```racket
  (define ch (make-channel))
  (thread (lambda () (channel-put ch 'hi)))
  (channel-get ch)               ; => 'hi
  ```

- **Thread mailboxes** (`thread-send`/`thread-receive`) — each thread has an
  asynchronous queue; the sender never blocks. Good for actor-style workers.

  ```racket
  (define w (thread (lambda () (let loop () (handle (thread-receive)) (loop)))))
  (thread-send w 'task)
  ```

- **Async channels** (`racket/async-channel`) — a buffered channel:
  `async-channel-put` returns immediately, `async-channel-get` blocks when
  empty. Use when you want decoupling with backpressure-free puts.

## Synchronization

When threads must share mutable state, guard the critical section with a
semaphore — `call-with-semaphore` acquires and *always* releases, even on
escape:

```racket
(define sem (make-semaphore 1))         ; 1 = a mutex
(call-with-semaphore sem (lambda () (set! counter (add1 counter))))
```

Even so, message-passing with immutable data is usually the better design: it
keeps state owned by one thread and removes the lock entirely.

## Synchronizable events — the unifying idea

Almost everything waitable is an **event**: channels, semaphores, threads
(their death), ports, timeouts. `sync` blocks until one event is ready and
returns its value; this is Racket's `select`:

```racket
(sync (handle-evt ch1 (lambda (v) (list 'from-1 v)))   ; post-process the result
      (handle-evt ch2 (lambda (v) (list 'from-2 v))))
(sync/timeout 0.5 some-evt)             ; => #f if nothing ready in 0.5s
```

Key combinators:

- **`handle-evt`** / **`wrap-evt`** — run a procedure on the ready value.
  `handle-evt` preserves tail position (its proc may `sync` again);
  `wrap-evt`'s proc must not sync.
- **`choice-evt`** — ready when any sub-event is (the variadic `sync` already
  does this).
- **`alarm-evt`** — becomes ready at an absolute time (ms); for timeouts.
- **`guard-evt`** / **`nack-guard-evt`** — build the event lazily at sync
  time; the NACK form learns if it *wasn't* chosen (to cancel work).
- **`always-evt`** / **`never-evt`** — immediately ready / never ready.

An async-channel and a thread are themselves events: `(sync ac)` yields a
received value; `(sync (thread-dead-evt t))` waits for `t` to end.

## Real parallelism

### Futures — parallel expressions

`future` runs a thunk in parallel if it stays "future-safe" (arithmetic,
vector/flonum ops, no I/O, limited allocation); `touch` waits for the result.
A future that hits an unsafe operation blocks until `touch`ed on the main
thread.

```racket
(require racket/future)
(define fs (for/list ([i 4]) (future (lambda () (heavy-compute i)))))
(map touch fs)                          ; results, computed across cores
(processor-count)                       ; available hardware threads
```

### Places — parallel processes with separate memory

A `place` runs a body on its own OS thread with its own heap; you communicate
only through its place-channel, sending allowable (mostly immutable/flat)
messages:

```racket
(require racket/place)
(define p (place pch
            (define n (place-channel-get pch))
            (place-channel-put pch (* n n))))
(place-channel-put p 9)
(place-channel-get p)                   ; => 81
(place-wait p)                          ; wait for the place to exit
```

**A `place` body re-instantiates its enclosing module in the new place**, so
any module top-level side effects run again there. Keep place code in a
dedicated module or a submodule, and keep top-level effects under
`(module+ main …)`, or you will see duplicated output and re-run setup.
`place-message-allowed?` checks whether a value can cross.

## Resource lifecycle: custodians

A custodian owns the threads, ports, and places created under it; shutting it
down reclaims them all at once — the clean way to bound a subsystem's
lifetime:

```racket
(define cust (make-custodian))
(parameterize ([current-custodian cust])
  (thread (lambda () (serve))))         ; this thread belongs to cust
(custodian-shutdown-all cust)           ; kills it (and everything else under cust)
```

## Rules that prevent rework

- **Message-passing over shared state.** Give each piece of state one owning
  thread and communicate by channel/mailbox; it removes most locks and races
  (the isolate-side-effects design). Reach for a semaphore only for a genuine
  shared critical section, via `call-with-semaphore`.
- **Threads are concurrency, not speedup.** Green threads interleave on one
  core. For CPU-bound work use `future` (shared heap, future-safe ops) or
  `place` (separate heap, any code); don't expect `thread` to use more cores.
- **`sync` is select — wait on events, don't poll.** Combine channels,
  timeouts (`alarm-evt`/`sync/timeout`), and thread death into one `sync`
  instead of spinning with `sleep`.
- **Prefer `break-thread` to `kill-thread`.** Cooperative cancellation lets a
  thread clean up via `exn:break?`; killing leaks half-released resources.
- **Keep place code out of module top level.** A place re-runs the module;
  isolate its body and put effects under `module+ main` so they don't execute
  twice.
- **Bound subsystems with a custodian.** Create a subsystem's threads/ports
  under a fresh custodian so one `custodian-shutdown-all` tears the whole
  thing down deterministically.
