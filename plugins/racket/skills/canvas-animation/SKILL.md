---
description: Drive a repeated redraw loop on a racket/gui canvas%. Covers the timer% tick that advances a model and then requests a repaint, motion that is independent of the frame rate through a dt clock, a render with no flicker (double buffers, refresh and refresh-now, suspend-flush and resume-flush, offscreen bitmaps), input that feeds the model, and the split of the pure update from the render, so a test needs no window. Use when you build a game loop or an animation, when you make motion smooth or independent of the frame rate, or when you diagnose canvas flicker. For a single paint, see ../drawing/SKILL.md. For the window, the widgets, and the dialogs around the canvas, see ../gui/SKILL.md.
allowed-tools: Read, Grep, Glob
---

# Canvas animation with racket/gui

An animation on a `canvas%` is a loop. A **timer** advances the model state
and then asks the canvas to repaint. The **paint-callback** renders the
current state. The data flows one way: *update the model, then draw it*.
Never the reverse. This skill builds on [gui](../gui/SKILL.md) (the canvas,
the eventspace, and the input) and on [drawing](../drawing/SKILL.md) (the
`dc<%>` that you paint with).

For the `canvas%` and `timer%` members that an animation uses, the timing
primitives, and the offscreen double-buffer pattern, read `reference.md` in
this skill directory.

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
               [interval 16]                ; about 60 frames per second
               [notify-callback (lambda ()  ; update, then request a repaint
                                  (set-box! state (+ (unbox state) 2.0))
                                  (send canvas refresh))]))
(send frame show #t)                        ; a shown frame keeps the application alive
```

The `timer%` fires on the handler thread of the eventspace. So the update and
the paint run in sequence, and the model needs no lock.

## Frame timing: make the motion independent of the frame rate

A fixed step per tick (`+ 2.0`) moves faster or slower as the real frame rate
drifts. For a smooth, constant speed, scale the motion by the **elapsed
time** since the last frame (`dt`), with a monotonic clock:

```racket
(define last (box (current-inexact-monotonic-milliseconds)))
(define pos (box 0.0))
(define speed 120.0)                         ; units per SECOND

(define (tick)
  (define now (current-inexact-monotonic-milliseconds))
  (define dt (/ (- now (unbox last)) 1000.0)); seconds since the last frame
  (set-box! last now)
  (set-box! pos (+ (unbox pos) (* speed dt)))
  (send canvas refresh))
```

The `timer%` interval is a *request*, not a guarantee. `dt` corrects the
jitter and the dropped frames.

## A render with no flicker

`canvas%` is **double-buffered** by default. The draw calls inside the
`paint-callback` go to an offscreen buffer, and the canvas shows the result
in one step. So a partly drawn frame never appears on the screen. The rules
that keep it smooth:

- **Draw only in the `paint-callback`.** A draw from a timer through `get-dc`
  bypasses the buffer and flickers. Update the state in the timer. Draw in
  the callback. Call `refresh` to connect them.
- **`refresh` and `refresh-now`.** `refresh` queues a repaint, and the system
  merges it with other repaints. Use it in the loop. `refresh-now` paints
  *synchronously* before it returns. Keep it for a single forced redraw, not
  for the animation tick.
- **Redraw the whole frame from the state.** Start the callback with
  `(send dc clear)` (or use `[style '(no-autoclear)]` and clear yourself).
  Then draw everything from the model. An animation recomputes the picture.
  It does not erase the old sprite.
- **Batch a burst of draws with `suspend-flush` and `resume-flush`.** When
  you must issue many draws outside the normal callback, wrap them, so only
  one flush occurs.

For an expensive scene, render once to an **offscreen bitmap** and copy
("blit") it to the canvas. Redraw the bitmap only when the scene changes:

```racket
(define buf (make-bitmap 400 300))
(define bdc (new bitmap-dc% [bitmap buf]))
;; ... draw the scene into bdc when it changes ...
(new canvas% [parent frame] [style '(no-autoclear)]
     [paint-callback (lambda (cv dc) (send dc draw-bitmap buf 0 0))])
```

## Animation from input

Read the input into the model. Never draw from an input handler. Subclass
`canvas%` and override `on-char` or `on-event` (see [gui](../gui/SKILL.md))
to set the state that the next paint shows:

```racket
(define game-canvas%
  (class canvas%
    (super-new)
    (define/override (on-char e)
      (case (send e get-key-code)
        [(left)  (set-box! vx -1)]
        [(right) (set-box! vx 1)]
        [else (void)]))))    ; the timer integrates vx into the position each frame
```

## Keep the loop responsive

The update and the paint run on the handler thread, so a slow frame freezes
the input. Keep the work per frame small. Push heavy computation (path
search, asset loads) to a worker thread, and feed the results back with
`queue-callback` (see [concurrency](../concurrency/SKILL.md)). A `timer%`
interval that is shorter than the work of a frame only queues callbacks
faster than they drain. Measure with [profiling](../profiling/SKILL.md).

## Test an animation

Split the **pure update** from the **render**, so a test of the logic needs
no window:

```racket
(define (step st dt) (struct-copy world st [x (+ (world-x st) (* (world-vx st) dt))]))
;; test the model with rackunit. No GUI is necessary:
(check-equal? (world-x (step (world 0 100) 0.5)) 50.0)
```

Render the model to an offscreen `bitmap-dc%` ([drawing](../drawing/SKILL.md))
to take a snapshot of a frame in a test. A shown `frame%` keeps the
eventspace, and the process, alive. Close the frame or call `(exit)` to stop
a standalone run.

## Rules that prevent rework

- **One-way flow: the timer updates the model, and the paint renders it.** Do
  not change the state in the paint-callback, and do not draw from the
  timer. Keep the update and the render separate. Then the animation stays
  predictable and testable.
- **Scale the motion by `dt`, not by the frame count.** Use
  `current-inexact-monotonic-milliseconds`. Then the speed is constant at
  every frame rate, and dropped frames do not change the trajectory.
- **`refresh` in the loop, and draw in the paint-callback.** That path is
  double-buffered and has no flicker. A draw through `get-dc` and a
  `refresh-now` per tick are not. Keep them for special cases.
- **Clear and redraw from the state each frame.** Recompute the whole
  picture. Do not patch the previous one. Cache to an offscreen bitmap only
  when a scene is expensive and changes rarely.
- **Stop the timer, and keep the frames cheap.** Call `(send timer stop)` at
  teardown. Move heavy work off the handler thread
  ([concurrency](../concurrency/SKILL.md)), so the input and the render stay
  smooth.
