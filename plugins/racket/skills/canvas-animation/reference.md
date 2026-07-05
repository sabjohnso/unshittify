# Canvas Animation Reference — signatures

Companion to SKILL.md. Source: docs.racket-lang.org/gui/ (canvas%, timer%).
Checked against Racket v9.1 [cs] (constructed/run under Xvfb). See the gui and
drawing skills for the full widget and dc<%> APIs.

## canvas% — animation-relevant members

```racket
(new canvas% [parent p]
     [paint-callback (-> canvas% (is-a?/c dc<%>) any)]   ; called to repaint
     [style (listof sym)])        ; '(no-autoclear) = canvas won't auto-clear;
                                  ; '(transparent) ; '(gl) for OpenGL (sgl)
;; repaint control
(send cv refresh)                 ; queue a repaint (async, coalesced) — use in a loop
(send cv refresh-now [paint-proc #:flush? bool])  ; paint synchronously, now
(send cv on-paint)                ; default paints via paint-callback (override alt)
(send cv get-dc) -> (is-a?/c dc<%>)               ; the canvas's drawing context
;; flush control (batch drawing, reduce flicker)
(send cv suspend-flush)           ; stop on-screen updates
(send cv resume-flush)            ; re-enable; pair with suspend-flush
(send cv flush)                   ; force pending drawing to the screen
;; geometry / focus (from canvas<%>, window<%>)
(send cv get-size) -> (values w h)        (send cv get-client-size) -> (values w h)
(send cv min-client-width w)  (send cv min-client-height h)   ; also min-width/min-height
(send cv accept-tab-focus on?)
(send cv on-char key-event%)              (send cv on-event mouse-event%)
```

`canvas%` is double-buffered, so `paint-callback` drawing is composited
offscreen and shown without flicker. `'(no-autoclear)` suppresses the
automatic clear before each paint — then you must `(send dc clear)` (or blit a
full-frame bitmap) yourself.

## timer% — the animation clock

```racket
(new timer% [notify-callback (-> any)]    ; runs on the eventspace handler thread
            [interval msec-or-#f]         ; fire every interval ms; #f = inactive
            [just-once? bool])            ; #t = fire a single time
(send t start interval [just-once?])      ; (re)start with an interval
(send t stop)                             ; stop firing
(send t interval) -> (or/c exact-positive-integer? #f)
```

A `timer%` belongs to `(current-eventspace)`; its callback is serialized with
paints and input on the handler thread.

## Timing and scheduling primitives

```racket
(current-inexact-monotonic-milliseconds) -> flonum   ; for dt; never goes backward
(current-inexact-milliseconds) -> flonum             ; wall clock (may jump)
(queue-callback thunk [high?])            ; run thunk on the handler thread (from a worker)
(yield) (sleep/yield secs)                ; dispatch events at top level (not in callbacks)
```

Compute `dt` from successive `current-inexact-monotonic-milliseconds`
readings; integrate motion as `(+ pos (* speed dt))` with `speed` in
units per second.

## Offscreen double-buffer pattern (racket/draw)

```racket
(define buf (make-bitmap w h))            ; an ARGB bitmap
(define bdc (new bitmap-dc% [bitmap buf]))
;; render the scene into bdc when it changes:
(send bdc clear) (send bdc draw-... ) ...
;; blit in the canvas paint-callback:
(lambda (cv dc) (send dc draw-bitmap buf 0 0))
```

Redraw `buf` only when the scene actually changes (a static background, a
costly composite); blit it every frame. See the drawing skill for the full
`dc<%>`/`bitmap-dc%` API.

## Loop drivers — when to use which

- **`timer%`** — the default: periodic `notify-callback` on the handler
  thread, automatically coalesced with paints/input. Use for ~all UI
  animation.
- **A worker `thread` + `queue-callback`** — when frames depend on slow
  off-thread work; compute on the thread, then `queue-callback` to update the
  model and `refresh` on the handler thread (see the concurrency skill).
- **`refresh-now` in a bounded loop** — only for synchronous, non-interactive
  rendering (e.g. exporting frames), never as the live animation tick.
