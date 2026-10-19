---
description: Build a desktop application window with racket/gui. Covers frame% and dialog%, panels and the box-model layout, controls (button%, text-field%, choice%, list-box%, slider%), menu bars, control callbacks, mouse and keyboard events, the handler thread of the eventspace, queue-callback, and the standard file, color, and text dialogs. Use when you assemble or lay out the widgets of a window, when you wire a control callback, when you handle input events, when you keep the UI responsive during slow work, or when you test a windowed application with no display. For what to paint on a canvas, see ../drawing/SKILL.md. For a redraw loop that a timer drives, see ../canvas-animation/SKILL.md.
allowed-tools: Bash(racket:*), Bash(raco:*), Bash(xvfb-run:*), Read, Grep, Glob
---

# GUI programs with racket/gui

`racket/gui` is a class-based widget toolkit built on
[classes](../classes/SKILL.md). Every window, container, and control is an
object. You create it with `new` and drive it with `send`. You build a tree
(a `frame%` that holds panels that hold controls), you wire the callbacks,
and you show the tree. Require `racket/gui/base` (or `racket/gui`, which adds
`racket/draw` and the framework).

For the class hierarchy and the signatures of every window, container, and
control class, read `reference.md` in this skill directory.

```racket
(require racket/gui/base racket/class)

(define frame (new frame% [label "Hello"] [width 300] [height 120]))
(define field (new text-field% [parent frame] [label "Name:"]))
(new button% [parent frame] [label "Greet"]
     [callback (lambda (btn evt)
                 (message-box "Hi" (string-append "Hello " (send field get-value))))])
(send frame show #t)        ; show it. The eventspace thread keeps the application alive.
```

A run with `racket app.rkt` shows the window, and the process *continues to
run* after the module finishes. The GUI eventspace has a handler thread that
lives until the last window closes. That thread is the center of all that
follows.

## Widgets

- **Windows:** `frame%` (a top-level window), `dialog%` (a modal child).
- **Containers** lay out their children: `vertical-panel%`,
  `horizontal-panel%`, `panel%`, `group-box-panel%` (a border with a title),
  `tab-panel%`, `pane%`. Nest them to build the structure.
- **Controls:** `message%` (a label), `button%`, `check-box%`, `radio-box%`,
  `choice%` (a dropdown), `list-box%`, `text-field%`, `slider%`, `gauge%`.
- **Menus:** `menu-bar%` on a frame. It holds `menu%`, `menu-item%`, and
  `checkable-menu-item%`.

Each one is an object. Read and set its state with methods: `(send field
get-value)`, `(send choice set-selection 2)`, `(send check get-value)`.

## Layout: containers, not coordinates

There is no absolute position by default. The `parent` of a control places
it, and a panel stacks its children vertically or horizontally. Control the
result with init arguments, not with coordinates:

- `[alignment '(center top)]`: how the children align in the panel.
- `[spacing n]` and `[border n]`: the gap between the children, and the gap
  around the panel.
- `[stretchable-width #t]` and `[stretchable-height #f]`: whether a child
  grows with the window.
- `[min-width n]` and `[min-height n]`: the minimum size.

```racket
(define col (new vertical-panel% [parent frame] [alignment '(left top)] [spacing 4]))
(new button% [parent col] [label "A"] [stretchable-width #t])
```

## Callbacks

The `callback` of a control runs when the user acts on the control. It gets
the control and an event object:

```racket
(new button% [parent col] [label "Go"]
     [callback (lambda (control event)        ; event : control-event%
                 (do-something))])
```

In a test, you can fire a callback with no user:
`(send a-button command (new control-event% [event-type 'button]))`.

## Custom draws

A `canvas%` gives you a drawing context (`dc<%>`). Give it a
`paint-callback` that draws on each refresh. The `dc<%>` API (from
`racket/draw`) is the same for a window and for an offscreen bitmap.
[drawing](../drawing/SKILL.md) catalogs it. This skill covers only how a
canvas gets one and when it repaints:

```racket
(new canvas% [parent frame]
     [paint-callback
      (lambda (canvas dc)
        (send dc set-brush (new brush% [color "lightblue"]))
        (send dc set-pen (new pen% [color "navy"] [width 2]))
        (send dc draw-rectangle 10 10 80 40)
        (send dc draw-text "hi" 20 20))])
```

Draw offscreen with `bitmap-dc%`. It needs no window, and it is useful for a
test and for a render to a file:

```racket
(define dc (new bitmap-dc% [bitmap (make-bitmap 100 60)]))
(send dc draw-line 0 0 100 60)
```

The key `dc<%>` operations: `set-pen`, `set-brush`, `set-font`,
`draw-line`, `-rectangle`, `-rounded-rectangle`, `-ellipse`, `-point`,
`-text`, `-bitmap`, `get-text-extent` (measure text), `set-smoothing`. Call
`(send canvas refresh)` to trigger a repaint after a state change.

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

## The event loop and the responsiveness

Every callback, paint, and input handler runs on the **handler thread** of
the eventspace. While one runs, the UI is frozen. So **never do slow work in
a callback**. Move it to a thread ([concurrency](../concurrency/SKILL.md)),
and send the results back to the UI with `queue-callback`. It runs a thunk on
the handler thread:

```racket
(new button% [parent col] [label "Fetch"]
     [callback (lambda (b e)
                 (thread (lambda ()
                           (define result (slow-network-call))   ; off the UI thread
                           (queue-callback
                            (lambda () (send result-msg set-label result))))))])
```

- **`timer%`** runs a callback periodically on the handler thread, for an
  animation or a poll: `(new timer% [notify-callback tick] [interval 16])`.
- **`yield`** processes one round of pending events. `(sleep/yield secs)`
  sleeps and keeps the UI live. Use these only at the top level. Never use
  them to fake a wait inside a callback.
- **Eventspaces** isolate the event queues. `make-eventspace` plus
  `(parameterize ([current-eventspace es]) …)` gives a window its own queue.

## Dialogs

The standard dialogs are plain functions. Each one runs modally and returns
the choice: `message-box`, `message-box/custom`, `get-file`, `put-file`,
`get-directory`, `get-text-from-user`, `get-choices-from-user`,
`get-color-from-user`, `get-font-from-user`.

## Tests with no display

A GUI needs a display. In CI or on a machine with no display, run under a
virtual framebuffer: `xvfb-run -a racket app.rkt` (or `xvfb-run -a raco test
…`). Test the logic with no human: construct the widgets and call their
callbacks (`send control command …`) or their methods directly. Draw to a
`bitmap-dc%` to assert on the render. No window is shown.

## Rules that prevent rework

- **Never block the handler thread.** Slow work in a callback freezes the
  whole UI. Run it in a thread, and update the widgets through
  `queue-callback` ([concurrency](../concurrency/SKILL.md)).
- **Touch the widgets only from the handler thread.** From an other thread,
  wrap each UI update in `queue-callback`. A `send` to a control from a
  worker thread is a race.
- **Lay out with containers, not with coordinates.** Use nested panels plus
  `alignment`, `spacing`, and `stretchable-*`. An absolute position breaks
  on a resize and across platforms.
- **`super-new` in every custom widget.** A `class` that extends `canvas%`
  or `frame%` must call `super-new`, as every [classes](../classes/SKILL.md)
  subclass does.
- **Separate the model from the view.** Keep the application state in plain
  data ([structs](../structs/SKILL.md)). Let the callbacks read and update
  it, and then refresh the view. Then the logic is testable with no GUI, and
  the view can change on its own.
- **Test under `xvfb-run` and through the callbacks.** Drive the controls
  from a program, and render to bitmaps. Keep a real display for manual
  checks.
