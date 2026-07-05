---
description: Animate a racket/gui canvas% — the timer-driven update/render loop, frame-rate-independent motion with dt timing, flicker-free drawing (double buffering, refresh vs refresh-now, suspend-flush/resume-flush, offscreen bitmaps), input-driven animation, and testing animation by splitting model from view. Use when building a game loop, animating graphics, achieving smooth motion, or fixing canvas flicker.
---

# Canvas Animation with racket/gui

Animation on a `canvas%` is a loop: a **timer** advances the model state,
then asks the canvas to repaint, and the **paint-callback** renders the
current state. Data flows one way — *update the model, then draw it* — never
the reverse. This builds on `[[gui]]` (the canvas, eventspace, and input)
and `[[drawing]]` (the `dc<%>` you paint with).

```racket
(require racket/gui/base racket/class)

(define state (box 0.0))                    ; the model: an x-position

(define frame (new frame% [label "anim"] [width 300] [height 100]))
(define canvas
  (new canvas% [parent frame]
       [paint-callback (lambda (cv dc)      ; render the CURRENT state
                         (send dc clear)
                         (send dc draw-rectangle (unbox state) 40 20 20))]))

(define t (new timer%
               [interval 16]                ; ~60 fps
               [notify-callback (lambda ()  ; update, then request a repaint
                                  (set-box! state (+ (unbox state) 2.0))
                                  (send canvas refresh))]))
(send frame show #t)                        ; a shown frame keeps the app alive
```

The `timer%` fires on the eventspace handler thread, so update and paint are
serialized — no locking needed for the model.

## Frame timing — make motion frame-rate independent

A fixed step per tick (`+ 2.0`) moves faster or slower as the real frame rate
drifts. For smooth, consistent speed, scale motion by the **elapsed time**
since the last frame (`dt`), using a monotonic clock:

```racket
(define last (box (current-inexact-monotonic-milliseconds)))
(define pos (box 0.0))
(define speed 120.0)                         ; units per SECOND

(define (tick)
  (define now (current-inexact-monotonic-milliseconds))
  (define dt (/ (- now (unbox last)) 1000.0)); seconds since last frame
  (set-box! last now)
  (set-box! pos (+ (unbox pos) (* speed dt)))
  (send canvas refresh))
```

The `timer%` interval is a *request*, not a guarantee; `dt` corrects for the
jitter and for dropped frames.

## Flicker-free rendering

`canvas%` is **double-buffered** by default: drawing inside the
`paint-callback` is composited offscreen and shown atomically, so you get no
tearing. The rules that keep it smooth:

- **Draw only in the `paint-callback`.** Reading `get-dc` and drawing from a
  timer bypasses the buffering and flickers. Update state in the timer; draw
  in the callback; call `refresh` to connect them.
- **`refresh` vs `refresh-now`.** `refresh` queues a repaint that the system
  coalesces with others — use it in the loop. `refresh-now` paints
  *synchronously* before returning; reserve it for a one-off forced redraw,
  not the animation tick.
- **Redraw the whole frame from state.** Begin the callback with
  `(send dc clear)` (or use `[style '(no-autoclear)]` and clear yourself),
  then draw everything from the model. Animation is "recompute the picture,"
  not "erase the old sprite."
- **Batch bursts with `suspend-flush`/`resume-flush`.** When you must issue
  many draws outside the normal callback, wrap them so only one flush
  happens.

For an expensive scene, render once to an **offscreen bitmap** and blit it,
redrawing the bitmap only when the scene changes:

```racket
(define buf (make-bitmap 400 300))
(define bdc (new bitmap-dc% [bitmap buf]))
;; ... draw the scene into bdc when it changes ...
(new canvas% [parent frame] [style '(no-autoclear)]
     [paint-callback (lambda (cv dc) (send dc draw-bitmap buf 0 0))])
```

## Input-driven animation

Read input into the model, never draw from an input handler. Subclass
`canvas%` and override `on-char`/`on-event` (see `[[gui]]`) to set state that
the next paint reflects:

```racket
(define game-canvas%
  (class canvas%
    (super-new)
    (define/override (on-char e)
      (case (send e get-key-code)
        [(left)  (set-box! vx -1)]
        [(right) (set-box! vx 1)]
        [else (void)]))))    ; the timer integrates vx into position each frame
```

## Keeping the loop responsive

Update and paint run on the handler thread, so a slow frame freezes input.
Keep per-frame work small; push heavy computation (path-finding, asset
loading) to a worker thread and feed results back with `queue-callback`
(see `[[concurrency]]`). A `timer%` interval shorter than a frame's work just
queues callbacks faster than they drain — measure with `[[profiling]]`.

## Testing animation

Split the **pure update** from **rendering** so the logic is testable without
a window:

```racket
(define (step st dt) (struct-copy world st [x (+ (world-x st) (* (world-vx st) dt))]))
;; test the model with rackunit — no GUI needed:
(check-equal? (world-x (step (world 0 100) 0.5)) 50.0)
```

Render the model to an offscreen `bitmap-dc%` (`[[drawing]]`) to snapshot a
frame in a test. Remember a shown `frame%` keeps the eventspace — and the
process — alive; close the frame or `(exit)` to stop a standalone run.

## Rules that prevent rework

- **One-way flow: timer updates the model, paint renders it.** Don't mutate
  state in the paint-callback or draw from the timer; keep update and render
  separate and the animation stays predictable and testable.
- **Scale motion by `dt`, not by frame count.** Use
  `current-inexact-monotonic-milliseconds` so speed is constant regardless of
  the actual frame rate, and dropped frames don't change the trajectory.
- **`refresh` in the loop; draw in the paint-callback.** That path is
  double-buffered and flicker-free; `get-dc` drawing and `refresh-now` per
  tick are not — reserve them for special cases.
- **Clear and redraw from state each frame.** Recompute the whole picture
  rather than patching the previous one; cache to an offscreen bitmap only
  when a scene is expensive and changes rarely.
- **Stop the timer and keep frames cheap.** `(send timer stop)` on teardown,
  and move heavy work off the handler thread (`[[concurrency]]`) so input and
  rendering stay smooth.
