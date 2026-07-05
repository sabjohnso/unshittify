# racket/draw + pict Reference — signatures

Companion to SKILL.md. Source: docs.racket-lang.org/draw/ and
docs.racket-lang.org/pict/. Checked against Racket v9.1 [cs].

## Drawing contexts (racket/draw)

```racket
(new bitmap-dc% [bitmap bmp])              ; offscreen, on a bitmap%
(send a-canvas get-dc)                     ; a GUI canvas's context (gui skill)
(new svg-dc%  [width w][height h][output path-or-port][exists 'replace]
              [interactive #f])
(new pdf-dc%  [interactive #f][width w][height h][output path-or-port][as-eps bool])
(new post-script-dc% [interactive #f][width w][height h][output path])
(new record-dc% [width w][height h])       ; record drawing, replay later
;; vector dcs (svg/pdf/ps) are documents:
(send dc start-doc reason) (send dc start-page) ... (send dc end-page) (send dc end-doc)
```

## dc<%> methods

```racket
;; state
(send dc set-pen pen-or-color width style) (send dc set-brush brush-or-color style)
(send dc set-font font%)        (send dc set-smoothing 'unsmoothed/'aligned/'smoothed)
(send dc set-text-foreground c) (send dc set-text-background c) (send dc set-background c)
(send dc set-alpha 0.0..1.0)
(send dc translate dx dy) (send dc scale sx sy) (send dc rotate radians)
(send dc get-transformation) (send dc set-transformation t)   ; save/restore
(send dc set-clipping-rect x y w h) (send dc set-clipping-region region-or-#f)
;; draw
(send dc draw-line x1 y1 x2 y2)   (send dc draw-lines (list (cons x y) ...) [dx dy])
(send dc draw-rectangle x y w h)  (send dc draw-rounded-rectangle x y w h radius)
(send dc draw-ellipse x y w h)    (send dc draw-arc x y w h start-rad end-rad)
(send dc draw-point x y)          (send dc draw-polygon (list (cons x y) ...) [dx dy fill])
(send dc draw-path path [dx dy fill-style])    (send dc draw-spline x1 y1 x2 y2 x3 y3)
(send dc draw-text str x y [combine? offset angle])
(send dc draw-bitmap bmp x y [style color mask])
(send dc get-text-extent str [font]) -> (values w h descent ascent)
(send dc get-size) -> (values w h)   (send dc clear)   (send dc flush)
```

## dc-path%

```racket
(new dc-path%)
(send p move-to x y)  (send p line-to x y)  (send p lines (list (cons x y) ...))
(send p curve-to x1 y1 x2 y2 x3 y3)         ; cubic Bezier
(send p arc x y w h start end [ccw?])
(send p rectangle x y w h)  (send p ellipse x y w h)  (send p rounded-rectangle ...)
(send p close)  (send p append other-path)  (send p reverse)
(send p translate dx dy) (send p scale sx sy) (send p rotate rad)
(send p get-bounding-box) -> (values x y w h)
```

## Resources

```racket
(make-bitmap w h [alpha?]) -> bitmap%      (read-bitmap path-or-port [kind])
(send bmp save-file path 'png/'jpeg/'xbm/'xpm [quality])
(send bmp get-width) (send bmp get-height) (send bmp get-argb-pixels ...)
(new pen%   [color c][width n][style 'solid][cap 'round][join 'round])
(new brush% [color c][style 'solid][gradient grad][stipple bmp])
(make-pen #:color c #:width n #:style s)   (make-brush #:color c #:style s)
(new color% [red r][green g][blue b][alpha a])  (make-color r g b [a])
(make-object color% r g b)                 (send the-color-database find-color "name")
(new font% [size n][family sym][style sym][weight sym][underlined? b])
(make-font #:size n #:family sym #:weight sym #:style sym)
(send the-pen-list   find-or-create-pen   color width style) -> pen%
(send the-brush-list find-or-create-brush color style) -> brush%
(send the-font-list  find-or-create-font  size family style weight) -> font%
(new linear-gradient% [x0 _][y0 _][x1 _][y1 _][stops (list (list frac color%) ...)])
(new radial-gradient% [x0 _][y0 _][r0 _][x1 _][y1 _][r1 _][stops ...])
(new region% [dc dc])  (send region set-rectangle x y w h) / set-polygon / set-arc
```

## pict constructors

```racket
(circle d)  (disk d)  (ellipse w h)  (filled-ellipse w h)
(rectangle w h)  (filled-rectangle w h)  (rounded-rectangle w h [corner])
(text str [style size angle])          ; style: a font sym list, e.g. '(bold italic)
(hline w h)  (vline w h)               ; thin rule picts (no bare `line`)
(arrow size radians)  (arrowhead size radians)
(blank [w h]) (blank size)             ; empty space (a strut)
(bitmap path-or-bitmap%)               ; wrap a bitmap as a pict
(dc draw-proc w h [ascent descent])    ; custom: draw-proc : (dc<%> dx dy -> any)
(cloud w h)  (file-icon w h color)  (standard-fish w h)   ; from pict (fun extras)
```

## pict combinators

```racket
;; horizontal: align top/center/bottom-line/bottom
(ht-append [sep] p ...) (hc-append [sep] p ...) (htl-append ..) (hb-append ..) (hbl-append ..)
;; vertical: align left/center/right
(vl-append [sep] p ...) (vc-append [sep] p ...) (vr-append [sep] p ...)
;; overlay: l/c/r × t/c/b, plus baseline variants
(lt-superimpose p ...) (ct-superimpose ..) (rt-superimpose ..)
(lc-superimpose ..) (cc-superimpose ..) (rc-superimpose ..)
(lb-superimpose ..) (cb-superimpose ..) (rb-superimpose ..)
(table ncols pict-list col-aligns row-aligns col-seps row-seps)
```

## pict transforms, styling, geometry

```racket
(scale p factor)  (scale p xf yf)  (scale-to-fit p w h)  (rotate p radians)
(colorize p color)  (linewidth n p)
(frame p [#:segment _ #:color _]) (inset p amt) (inset p l t r b)
(ghost p)               ; same bbox, invisible
(cellophane p alpha)    ; partial transparency
(clip p)                ; clip drawing to bbox     (panorama p) ; bbox includes overflow
(launder p)             ; new pict, child tags hidden
(pict-width p) (pict-height p) (pict-ascent p) (pict-descent p)
(pict->bitmap p [smoothing]) -> bitmap%
```

## pict connectors and finders

```racket
;; finder: base + embedded sub-pict -> (values x y) at that anchor point
(lt-find b p) (ct-find b p) (rt-find b p)
(lc-find b p) (cc-find b p) (rc-find b p)
(lb-find b p) (cb-find b p) (rb-find b p)
(pin-over base dx-or-find-pict [find] p)      ; place p over base, bbox unchanged
(pin-under base dx-or-find-pict [find] p)
(pin-line  [#:start-angle ...] thickness? base src src-find dst dst-find)
(pin-arrow-line  arrow-size base src src-find dst dst-find [#:line-width _ #:color _])
(pin-arrows-line arrow-size base src src-find dst dst-find ...)   ; double-headed
```

## pict sub-libraries

```racket
(require pict/color)        ; (red p) (green p) (blue p) (orange p) ... (light c) (dark c)
(require pict/shadow)       ; (shadow p radius [dx dy] #:color _ #:shadow-color _)
(require pict/conditional)  ; (show p [show?]) (hide p [hide?]) — staged reveal via ghosting
(require pict/balloon)      ; callout balloons around a pict
(require pict/flash)        ; (filled-flash w h ...) (outline-flash w h ...)
(require pict/convert)      ; prop:pict-convertible — make a type display as a pict
```
