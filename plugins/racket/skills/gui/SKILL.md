---
name: gui
description: Build desktop GUIs in Racket with racket/gui — windows and widgets (frame%, panels, button%, text-field%, canvas%), the box-model layout, control callbacks, custom drawing with canvas%/dc<%>/racket-draw, mouse/keyboard input, the eventspace event loop, keeping the UI responsive with threads and queue-callback, and dialogs. Use when writing a windowed application, drawing custom graphics, handling input events, or testing GUI code headlessly.
---

# GUI Programming with racket/gui

`racket/gui` is a class-based widget toolkit built on [[classes]]: every
window, container, and control is an object you create with `new` and drive
with `send`. You build a tree — a `frame%` holding panels holding controls —
wire callbacks, and show it. Require `racket/gui/base` (or `racket/gui`,
which adds `racket/draw` and the framework).

```racket
(require racket/gui/base racket/class)

(define frame (new frame% [label "Hello"] [width 300] [height 120]))
(define field (new text-field% [parent frame] [label "Name:"]))
(new button% [parent frame] [label "Greet"]
     [callback (lambda (btn evt)
                 (message-box "Hi" (string-append "Hello " (send field get-value))))])
(send frame show #t)        ; display it; the eventspace thread keeps the app alive
```

Running this with `racket app.rkt` shows the window and *stays running* even
after the module finishes — the GUI eventspace has a handler thread that
lives until the last window closes. That thread is the heart of everything
below.

## Widgets

- **Windows:** `frame%` (top-level window), `dialog%` (modal child).
- **Containers** lay out their children: `vertical-panel%`,
  `horizontal-panel%`, `panel%`, `group-box-panel%` (titled border),
  `tab-panel%`, `pane%`. Nest them to build structure.
- **Controls:** `message%` (label), `button%`, `check-box%`, `radio-box%`,
  `choice%` (dropdown), `list-box%`, `text-field%`, `slider%`, `gauge%`.
- **Menus:** `menu-bar%` on a frame, holding `menu%`, `menu-item%`,
  `checkable-menu-item%`.

Each is an object: read and set its state with methods —
`(send field get-value)`, `(send choice set-selection 2)`,
`(send check get-value)`.

## Layout — the box model

There is no absolute positioning by default. A control's `parent` places it,
and panels stack children vertically or horizontally. Control the result with
init args, not coordinates:

- `[alignment '(center top)]` — how children align in the panel.
- `[spacing n]` / `[border n]` — gaps between children / around the panel.
- `[stretchable-width #t]` / `[stretchable-height #f]` — whether a child grows
  with the window.
- `[min-width n]` / `[min-height n]` — minimum size.

```racket
(define col (new vertical-panel% [parent frame] [alignment '(left top)] [spacing 4]))
(new button% [parent col] [label "A"] [stretchable-width #t])
```

## Callbacks

A control's `callback` runs when the user acts on it, receiving the control
and an event object:

```racket
(new button% [parent col] [label "Go"]
     [callback (lambda (control event)        ; event : control-event%
                 (do-something))])
```

In tests you can fire a callback without a user:
`(send a-button command (new control-event% [event-type 'button]))`.

## Custom drawing

A `canvas%` gives you a drawing context (`dc<%>`); supply a `paint-callback`
that draws on each refresh. The `dc<%>` API (from `racket/draw`) is the same
whether you draw to a window or an offscreen bitmap:

```racket
(new canvas% [parent frame]
     [paint-callback
      (lambda (canvas dc)
        (send dc set-brush (new brush% [color "lightblue"]))
        (send dc set-pen (new pen% [color "navy"] [width 2]))
        (send dc draw-rectangle 10 10 80 40)
        (send dc draw-text "hi" 20 20))])
```

Draw offscreen with `bitmap-dc%` — no window needed, handy for tests and
rendering to a file:

```racket
(define dc (new bitmap-dc% [bitmap (make-bitmap 100 60)]))
(send dc draw-line 0 0 100 60)
```

Key `dc<%>` operations: `set-pen`/`set-brush`/`set-font`,
`draw-line`/`-rectangle`/`-rounded-rectangle`/`-ellipse`/`-point`/`-text`/`-bitmap`,
`get-text-extent` (measure text), `set-smoothing`. Call `(send canvas
refresh)` to trigger a repaint after state changes.

## Input events

Subclass `canvas%` and override `on-event` (a `mouse-event%`) and `on-char`
(a `key-event%`):

```racket
(define board%
  (class canvas%
    (super-new)
    (define/override (on-event e)              ; mouse
      (when (send e button-down? 'left)
        (handle-click (send e get-x) (send e get-y))
        (send this refresh)))
    (define/override (on-char e)               ; keyboard
      (case (send e get-key-code) [(#\space) (toggle)] [else (void)]))))
```

## The event loop and staying responsive

Every callback, paint, and input handler runs on the eventspace's **handler
thread**. While one runs, the UI is frozen — so **never do slow work in a
callback**. Offload it to a thread ([[concurrency]]) and marshal results back
to the UI with `queue-callback`, which runs a thunk on the handler thread:

```racket
(new button% [parent col] [label "Fetch"]
     [callback (lambda (b e)
                 (thread (lambda ()
                           (define result (slow-network-call))   ; off the UI thread
                           (queue-callback
                            (lambda () (send result-msg set-label result))))))])
```

- **`timer%`** runs a callback periodically on the handler thread — for
  animation or polling: `(new timer% [notify-callback tick] [interval 16])`.
- **`yield`** processes one round of pending events; `(sleep/yield secs)`
  sleeps while keeping the UI live. Use these only at top level, never to fake
  waiting inside a callback.
- **Eventspaces** isolate event queues; `make-eventspace` plus
  `(parameterize ([current-eventspace es]) …)` gives a window its own queue.

## Dialogs

Standard dialogs are plain functions (each runs modally, returns the choice):
`message-box`, `message-box/custom`, `get-file`, `put-file`, `get-directory`,
`get-text-from-user`, `get-choices-from-user`, `get-color-from-user`,
`get-font-from-user`.

## Testing headlessly

GUI needs a display. In CI or a headless box, run under a virtual framebuffer:
`xvfb-run -a racket app.rkt` (or `xvfb-run -a raco test …`). Test logic
without a human by constructing widgets and invoking their callbacks
(`send control command …`) or methods directly, and draw to a `bitmap-dc%` to
assert on rendering — no window shown.

## Rules that prevent rework

- **Never block the handler thread.** Slow work in a callback freezes the
  whole UI. Run it in a thread and update widgets via `queue-callback`
  ([[concurrency]]).
- **Touch widgets only from the handler thread.** From another thread, wrap UI
  updates in `queue-callback`; calling `send` on a control from a worker
  thread is a race.
- **Lay out with containers, not coordinates.** Use nested panels plus
  `alignment`/`spacing`/`stretchable-*`; absolute positioning breaks on
  resize and across platforms.
- **`super-new` in every custom widget.** A `class` extending `canvas%`/`frame%`
  must call `super-new`, like any [[classes]] subclass.
- **Separate model from view.** Keep application state in plain data
  ([[structs]]) and let callbacks read/update it, then refresh the view — so
  the logic is testable without the GUI and the view can change independently.
- **Test under `xvfb-run` and via callbacks.** Drive controls programmatically
  and render to bitmaps; reserve a real display for manual checks.
