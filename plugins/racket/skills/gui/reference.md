# racket/gui Reference — classes and signatures

Companion to SKILL.md. Source: docs.racket-lang.org/gui/ and racket/draw.
Checked against Racket v9.1 [cs] (constructed under Xvfb).

## Class hierarchy (interfaces)

```
area<%>              ; anything with a size: min-width, stretchable-*, ...
 ├ subarea<%>        ; has a parent + margins
 │  └ subwindow<%>
 │     └ window<%>   ; show/focus/enable, get-parent, get-client-size
 │        └ control<%> ; the leaf widgets (button%, text-field%, ...)
 └ area-container<%> ; holds children: add-child, change-children, get-children
    └ area-container-window<%>
       ├ top-level-window<%>  (frame% dialog%)
       └ pane% / panel%
```

## Windows and containers

```racket
(new frame% [label str] [parent #f] [width n] [height n] [x n] [y n]
            [style '(...)] [enabled #t])
   ; styles: 'no-resize-border 'no-caption 'fullscreen-button 'float ...
   ; methods: show, is-shown?, center, maximize, set-label, create-status-line,
   ;          show-without-yield
(new dialog% [label str] [parent #f] [width n] [height n] [style ...])
   ; (send dlg show #t) blocks until the dialog is dismissed (modal)

(new panel%            [parent p] [style '(border)] ...)
(new vertical-panel%   [parent p] [alignment '(h v)] [spacing n] [border n]
                       [stretchable-width bool] [stretchable-height bool])
(new horizontal-panel% [parent p] ...)
(new group-box-panel%  [parent p] [label str] ...)
(new tab-panel% [parent p] [choices (list str ...)] [callback proc])
(new pane% / vertical-pane% / horizontal-pane% [parent p] ...)
   ; alignment h = 'left 'center 'right ; v = 'top 'center 'bottom
```

## Controls

```racket
(new message%  [parent p] [label str-or-bitmap])
(new button%   [parent p] [label str] [callback (-> button% control-event% any)])
(new check-box% [parent p] [label str] [callback ...] [value bool])
   ; get-value / set-value
(new radio-box% [parent p] [label str] [choices (list str ...)] [callback ...])
   ; get-selection / set-selection
(new choice%   [parent p] [label str] [choices (list str ...)] [callback ...])
   ; get-selection, get-string-selection, set-selection, append, clear
(new list-box% [parent p] [label str] [choices (list str ...)] [style '(single)]
               [callback ...])
   ; get-selections, get-string, set, append, clear, get-data
(new text-field% [parent p] [label str] [init-value ""] [callback ...]
                 [style '(single)])    ; 'multiple for multi-line
   ; get-value / set-value
(new slider%   [parent p] [label str] [min-value n] [max-value n] [init-value n])
   ; get-value / set-value
(new gauge%    [parent p] [label str] [range n])     ; set-value, set-range

;; menus
(new menu-bar% [parent frame])
(new menu% [parent menu-bar-or-menu] [label "&File"])
(new menu-item% [parent menu] [label str] [callback (-> item control-event% any)]
                [shortcut char] [shortcut-prefixes '(...)])
(new checkable-menu-item% [parent menu] [label str] [callback ...])
(new separator-menu-item% [parent menu])
```

Common `control<%>`/`window<%>` methods: `enable`, `is-enabled?`, `show`,
`focus`, `get-label`/`set-label`, `get-parent`, `min-width`/`min-height`,
`stretchable-width`/`-height`.

## Canvas and drawing

```racket
(new canvas% [parent p] [paint-callback (-> canvas% (is-a?/c dc<%>) any)]
             [style '(...)])
   ; methods: get-dc, refresh, on-paint, on-event, on-char, on-size, suspend-flush
(new editor-canvas% [parent p] [editor an-editor])   ; for text%/pasteboard%

;; dc<%> (a drawing context; from canvas get-dc or a bitmap-dc%)
(send dc set-pen pen-or-color width style)   (send dc set-brush brush-or-color style)
(send dc set-font font%)   (send dc set-smoothing 'aligned/'unsmoothed/'smoothed)
(send dc set-text-foreground color)   (send dc set-background color)
(send dc draw-line x1 y1 x2 y2)        (send dc draw-lines points)
(send dc draw-rectangle x y w h)       (send dc draw-rounded-rectangle x y w h r)
(send dc draw-ellipse x y w h)         (send dc draw-arc x y w h start end)
(send dc draw-point x y)               (send dc draw-polygon points)
(send dc draw-text str x y)            (send dc draw-bitmap bmp x y)
(send dc get-text-extent str) -> (values w h descent ascent)
(send dc get-size) -> (values w h)     (send dc clear)
```

## racket/draw

```racket
(make-bitmap w h [alpha?]) -> (is-a?/c bitmap%)
(read-bitmap path-or-port) -> bitmap%
(new bitmap-dc% [bitmap bmp])              ; an offscreen dc<%>
(new pen%   [color c] [width n] [style 'solid] [cap 'round] [join 'round])
(new brush% [color c] [style 'solid])
(make-pen   #:color c #:width n #:style s)   (make-brush #:color c #:style s)
(make-color r g b [alpha])  (new color% [red r] [green g] [blue b])
(make-object color% r g b)  (send the-color-database find-color "name")
(make-font  #:size n #:family 'roman/'swiss/'modern #:weight 'bold #:style 'italic)
(new font% [size n] [family sym] [weight sym] [style sym])
```

## Events

```racket
(new control-event% [event-type 'button/'check-box/'choice/'list-box/'text-field/...])
mouse-event%  : get-x, get-y, button-down? [which], button-up?, dragging?,
                moving?, get-left-down, get-shift-down, get-event-type
key-event%    : get-key-code (char or sym like 'left 'f1 'release), get-key-release-code,
                get-shift-down, get-control-down, get-meta-down
scroll-event% : get-position, get-direction
```

## Eventspaces, timers, top-level control

```racket
(current-eventspace) -> eventspace?        ; parameter
(make-eventspace) -> eventspace?
(queue-callback thunk [high-priority?])    ; run thunk on the handler thread
(yield [evt-or-'wait]) -> any              ; process pending events once
(sleep/yield secs)                         ; sleep while dispatching events
(eventspace-shutdown? es)  (eventspace-handler-thread es)
(event-dispatch-handler)                   ; parameter, advanced
(new timer% [notify-callback (-> any)] [interval msecs-or-#f] [just-once? bool])
   ; methods: start, stop
(application-quit-handler)  (application-about-handler)  (application-file-handler)
```

## Dialog functions

```racket
(message-box title message [parent] [style '(ok)]) -> sym
(message-box/custom title message btn1 btn2 btn3 [parent] ...) -> (or/c 1 2 3 #f)
(get-file [message parent dir filename ext style filters]) -> path-or-#f
(put-file [message parent dir filename ext style filters]) -> path-or-#f
(get-directory [message parent dir style]) -> path-or-#f
(get-text-from-user title message [parent init] ...) -> str-or-#f
(get-choices-from-user title message choices [parent] ...) -> (listof index)-or-#f
(get-color-from-user [message parent init style]) -> color%-or-#f
(get-font-from-user  [message parent init style]) -> font%-or-#f
```
