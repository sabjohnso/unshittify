---
description: Concurrency and parallelism in Racket. Covers green threads, synchronous channels and thread mailboxes, async channels, semaphores, the synchronizable-event system (sync, handle-evt, choice-evt, alarm-evt), real parallelism with futures and places, and the resource life cycle with custodians. Use when you coordinate threads, when you choose a communication mechanism, when you wait on several events, when you parallelize CPU work, or when you clean up a group of threads or ports.
allowed-tools: Read, Grep, Glob
---

# Concurrency and parallelism in Racket

Racket separates two things that people confuse:

For the exact signatures of the threads, the channels, the semaphores, and
the synchronizable-event system, read `reference.md` in this skill directory.

- **Concurrency.** `thread` creates *green threads* that interleave on one OS
  thread inside a place. They are cheap, and the scheduler preempts them.
  But they do **not** run at the same time. So they give responsiveness and
  structure, not CPU speed.
- **Parallelism.** `future` and `place` use several cores. A `place` has its
  own memory and talks by message. A `future` parallelizes work that
  allocates little and avoids unsafe operations ("future-safe", defined
  below).

Pick by need. Use threads to *organize* concurrent activity. Use futures or
places to *speed up* CPU-bound work.

## Threads

```racket
(define t (thread (lambda () (do-work))))
(thread-wait t)                  ; wait until t finishes
(break-thread t)                 ; request a cancellation (raises exn:break in t)
(kill-thread t)                  ; force a stop (no cleanup). Prefer break.
(sleep 0.1)                      ; yield for a while
```

Cooperative cancellation is cleaner than `kill-thread`. Let the thread guard
with `exn:break?`, so it can release its resources:

```racket
(thread (lambda ()
          (with-handlers ([exn:break? (lambda (_) (cleanup))])
            (let loop () (sleep 0.01) (loop)))))
```

## Communication between threads

Prefer messages to shared mutable state. There are three mechanisms:

- **Synchronous channels** (`make-channel`) are a *rendezvous*. `channel-put`
  waits until an other thread calls `channel-get`, and the reverse. There is
  no buffer. The hand-off itself synchronizes the two threads.

  ```racket
  (define ch (make-channel))
  (thread (lambda () (channel-put ch 'hi)))
  (channel-get ch)               ; => 'hi
  ```

- **Thread mailboxes** (`thread-send` and `thread-receive`). Each thread has
  an asynchronous queue. The sender never waits. This is good for workers in
  the actor style.

  ```racket
  (define w (thread (lambda () (let loop () (handle (thread-receive)) (loop)))))
  (thread-send w 'task)
  ```

- **Async channels** (`racket/async-channel`) are buffered channels.
  `async-channel-put` returns at once. `async-channel-get` waits when the
  channel is empty. Use them when the sender must never wait for the
  receiver. The buffer is unbounded by default.

## Synchronization

When threads must share mutable state, guard the critical section with a
semaphore. `call-with-semaphore` acquires it and *always* releases it, also
on an escape:

```racket
(define sem (make-semaphore 1))         ; 1 = a mutex
(call-with-semaphore sem (lambda () (set! counter (add1 counter))))
```

Even so, messages with immutable data are usually the better design. One
thread owns the state, and the lock disappears.

## Synchronizable events: the idea that unifies all

Almost everything that you can wait on is an **event**: a channel, a
semaphore, a thread (its end), a port, a timeout. `sync` waits until one
event is ready, and it returns the value of that event. This is the `select`
of Racket:

```racket
(sync (handle-evt ch1 (lambda (v) (list 'from-1 v)))   ; post-process the result
      (handle-evt ch2 (lambda (v) (list 'from-2 v))))
(sync/timeout 0.5 some-evt)             ; => #f if nothing is ready in 0.5 s
```

The key combinators:

- **`handle-evt`** and **`wrap-evt`** run a procedure on the ready value.
  `handle-evt` keeps the tail position (its procedure can `sync` again). The
  procedure of `wrap-evt` must not sync.
- **`choice-evt`** is ready when one of its sub-events is ready. The variadic
  `sync` already does this.
- **`alarm-evt`** becomes ready at an absolute time (in ms). Use it for a
  timeout.
- **`guard-evt`** and **`nack-guard-evt`** build the event at sync time. The
  NACK (negative acknowledgment) form learns whether it *was not* chosen, so
  it can cancel work.
- **`always-evt`** is ready at once. **`never-evt`** is never ready.

An async channel and a thread are events too. `(sync ac)` gives a received
value. `(sync (thread-dead-evt t))` waits for the end of `t`.

## Real parallelism

### Futures: parallel expressions

`future` runs a thunk in parallel if the thunk stays "future-safe"
(arithmetic, vector and flonum operations, no I/O, limited allocation).
`touch` waits for the result. A future that reaches an unsafe operation waits
until the main thread calls `touch` on it.

```racket
(require racket/future)
(define fs (for/list ([i 4]) (future (lambda () (heavy-compute i)))))
(map touch fs)                          ; the results, computed across the cores
(processor-count)                       ; the available hardware threads
```

### Places: parallel processes with separate memory

A `place` runs a body on its own OS thread with its own heap. You
communicate only through its place channel, with messages that are permitted
(mostly immutable or flat values):

```racket
(require racket/place)
(define p (place pch
            (define n (place-channel-get pch))
            (place-channel-put pch (* n n))))
(place-channel-put p 9)
(place-channel-get p)                   ; => 81
(place-wait p)                          ; wait for the exit of the place
```

**A `place` body instantiates its module again in the new place.** So each
side effect at the top level of the module runs again there. Keep the place
code in a dedicated module or submodule, and keep the top-level effects under
`(module+ main …)`. Otherwise you see duplicated output and a second run of
the setup. `place-message-allowed?` checks whether a value can cross.

## The resource life cycle: custodians

A custodian owns the threads, the ports, and the places created under it. A
shutdown of the custodian reclaims them all at once. That is the clean way
to bound the lifetime of a subsystem:

```racket
(define cust (make-custodian))
(parameterize ([current-custodian cust])
  (thread (lambda () (serve))))         ; this thread belongs to cust
(custodian-shutdown-all cust)           ; kills it, and everything else under cust
```

## Rules that prevent rework

- **Messages over shared state.** Give each piece of state one owner thread,
  and communicate by channel or mailbox. That removes most locks and races,
  because the side effects stay in one thread. Use a semaphore only for a
  real shared critical section, through `call-with-semaphore`.
- **Threads are concurrency, not speed.** Green threads interleave on one
  core. For CPU-bound work, use `future` (a shared heap, future-safe
  operations) or `place` (a separate heap, any code). Do not expect `thread`
  to use more cores.
- **`sync` is select. Wait on events. Do not poll.** Combine channels,
  timeouts (`alarm-evt`, `sync/timeout`), and the end of a thread in one
  `sync`. Do not spin with `sleep`.
- **Prefer `break-thread` to `kill-thread`.** Cooperative cancellation lets a
  thread clean up through `exn:break?`. A kill leaks half-released
  resources.
- **Keep the place code out of the top level of the module.** A place runs
  the module again. Isolate its body, and put the effects under `module+
  main`, so they do not run twice.
- **Bound a subsystem with a custodian.** Create the threads and the ports of
  a subsystem under a fresh custodian. Then one `custodian-shutdown-all`
  tears the whole subsystem down, with a predictable result.
