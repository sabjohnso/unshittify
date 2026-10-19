# Canvas Animation Reference: signatures

Companion to SKILL.md. Source: docs.racket-lang.org/gui/ (canvas%, timer%).
Interface introspection (`interface->method-names`) checked the member names
against Racket v9.1 [cs] with no display attached. This shows that a method
exists. It does not show that an init-argument name is correct. Only a
created window can show that. For the full widget and dc<%> APIs, see
../gui/SKILL.md and ../drawing/SKILL.md.

## canvas% — animation-relevant members

```racket
(new canvas% [parent p]
     [paint-callback (-> canvas% (is-a?/c dc<%>) any)]   ; the canvas calls this to repaint
     [style (listof sym)])        ; '(no-autoclear) = the canvas does not clear itself
                                  ; '(transparent) ; '(gl) for OpenGL (sgl)
;; repaint control
(send cv refresh)                 ; queue a repaint (asynchronous, coalesced). Use it in a loop
(send cv refresh-now [paint-proc #:flush? bool])  ; paint now, synchronously
(send cv on-paint)                ; the default calls paint-callback (override as an alternative)
(send cv get-dc) -> (is-a?/c dc<%>)               ; the drawing context of the canvas
;; flush control (batch the drawing to reduce flicker)
(send cv suspend-flush)           ; stop on-screen updates
(send cv resume-flush)            ; re-enable. Pair it with suspend-flush
(send cv flush)                   ; force pending drawing to the screen
;; geometry / focus (from canvas<%>, window<%>)
(send cv get-size) -> (values w h)        (send cv get-client-size) -> (values w h)
(send cv min-client-width w)  (send cv min-client-height h)   ; also min-width/min-height
(send cv accept-tab-focus on?)
(send cv on-char key-event%)              (send cv on-event mouse-event%)
```

The `canvas%` class uses double buffering. The system composes the drawing of
`paint-callback` offscreen and shows it without flicker. `'(no-autoclear)`
stops the automatic clear before each paint. Then you must call
`(send dc clear)` or blit a full-frame bitmap.

## timer%: the animation clock

```racket
(new timer% [notify-callback (-> any)]    ; runs on the eventspace handler thread
            [interval msec-or-#f]         ; fire every interval ms. #f = inactive
            [just-once? bool])            ; #t = fire a single time
(send t start interval [just-once?])      ; (re)start with an interval
(send t stop)                             ; stop firing
(send t interval) -> (or/c exact-positive-integer? #f)
```

A `timer%` belongs to `(current-eventspace)`. The handler thread runs its
callback in sequence with paints and input.

## Timing and scheduling primitives

```racket
(current-inexact-monotonic-milliseconds) -> flonum   ; use for dt. It never goes backward
(current-inexact-milliseconds) -> flonum             ; wall clock (it can jump)
(queue-callback thunk [high?])            ; run thunk on the handler thread (from a worker)
(yield) (sleep/yield secs)                ; dispatch events at top level (not in callbacks)
```

Compute `dt` from successive readings of
`current-inexact-monotonic-milliseconds`. Integrate motion as
`(+ pos (* speed dt))`. Give `speed` in units per second.

## Offscreen double-buffer pattern (racket/draw)

```racket
(define buf (make-bitmap w h))            ; an ARGB bitmap
(define bdc (new bitmap-dc% [bitmap buf]))
;; render the scene into bdc when it changes:
(send bdc clear) (send bdc draw-... ) ...
;; blit in the canvas paint-callback:
(lambda (cv dc) (send dc draw-bitmap buf 0 0))
```

Redraw `buf` only when the scene changes, for example a static background or
a costly composite. Blit it every frame. For the full `dc<%>` and
`bitmap-dc%` API, see the drawing skill.

## Loop drivers: when to use which

- **`timer%`**: the default. It calls `notify-callback` periodically on the
  handler thread, and the system coalesces it with paints and input. Use it
  for nearly all UI animation.
- **A worker `thread` + `queue-callback`**: use it when frames depend on slow
  off-thread work. Compute on the thread. Then call `queue-callback` to update
  the model and `refresh` on the handler thread (see the concurrency skill).
- **`refresh-now` in a bounded loop**: use it only for synchronous,
  non-interactive rendering (for example, to export frames). Never use it as
  the live animation tick.
