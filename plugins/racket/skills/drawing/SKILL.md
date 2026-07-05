---
name: drawing
description: Draw graphics in Racket with racket/draw and pict — imperative drawing on a dc<%> (bitmaps, SVG/PDF/PS files, pens/brushes/paths/transforms) and functional, composable pictures with pict (circle/text/append/superimpose, colorize/scale/rotate, pin-line connectors, pict->bitmap). Use when rendering images, building diagrams, composing pictures, producing vector output, or drawing custom graphics outside or inside a GUI.
---

# Drawing: racket/draw and pict

Two layers, used together:

- **`racket/draw`** is imperative drawing onto a **drawing context**
  (`dc<%>`): you set a pen and brush, then issue `draw-line`,
  `draw-rectangle`, `draw-text`, … The same `dc<%>` API targets bitmaps,
  GUI canvases ([[gui]]), and vector files (SVG/PDF/PostScript).
- **`pict`** is a functional picture library built on top: a `pict` is an
  immutable value with a bounding box, created and combined by pure functions
  (`hc-append`, `cc-superimpose`, `colorize`). It renders to a `dc<%>` when
  displayed.

Choose **pict** to compose and lay out pictures and diagrams declaratively;
drop to **`racket/draw`** for pixel-level control or to produce image files.
DrRacket shows a `pict` inline, and Scribble embeds them ([[scribble-docs]]).

## racket/draw — drawing on a dc<%>

Get a context, set drawing state, issue commands. A `bitmap-dc%` draws
offscreen with no window:

```racket
(require racket/draw racket/class)
(define bm (make-bitmap 100 80))
(define dc (new bitmap-dc% [bitmap bm]))
(send dc set-smoothing 'smoothed)
(send dc set-brush (new brush% [color "lightblue"]))
(send dc set-pen (new pen% [color "navy"] [width 2]))
(send dc draw-ellipse 10 10 80 60)
(send dc draw-text "hi" 20 20)
(send bm save-file "out.png" 'png)        ; PNG/JPEG/etc.
```

Other contexts: a GUI `canvas%`'s `get-dc` ([[gui]]); and vector backends
`svg-dc%`, `pdf-dc%`, `post-script-dc%` for resolution-independent files.
The vector backends are **stateful documents** — construct with
`[interactive #f]`, then bracket drawing with the page lifecycle:

```racket
(define dc (new pdf-dc% [interactive #f] [width 200] [height 150] [output "fig.pdf"]))
(send dc start-doc "fig") (send dc start-page)
(send dc draw-line 0 0 200 150)
(send dc end-page) (send dc end-doc)       ; flushes the file
```

Key pieces of the `dc<%>` model:

- **Pen and brush** decide outline and fill: `(set-pen pen%-or "color" w style)`,
  `(set-brush brush%-or "color" style)`. Reuse cached instances via
  `the-pen-list`/`the-brush-list`/`the-color-database` instead of allocating
  per draw.
- **Paths** (`dc-path%`) describe arbitrary shapes — `move-to`, `line-to`,
  `curve-to`, `close` — then `(send dc draw-path p)`.
- **State**: `translate`/`scale`/`rotate` transform the coordinate system;
  save and restore it with `get-transformation`/`set-transformation` around a
  block. `set-alpha` for opacity, `set-clipping-rect`/`set-clipping-region`
  to mask, `set-smoothing` for antialiasing. Gradients via
  `linear-gradient%`/`radial-gradient%` set as a brush.

## pict — composable pictures

Build pictures from constructors and combine them functionally:

```racket
(require pict)
(circle 30)  (disk 20)  (filled-rectangle 40 20)  (rounded-rectangle 40 20 5)
(text "label" '(bold) 18)  (hline 30 1)  (arrow 20 0)  (blank 10 10)
(bitmap a-bitmap%)                          ; wrap a racket/draw bitmap as a pict
```

Combine along axes or by stacking, then style:

```racket
(hc-append 10 (circle 20) (disk 20))        ; horizontal, centers aligned
(vl-append 5 (text "a") (text "bb"))        ; vertical, left edges aligned
(cc-superimpose (rectangle 60 60) (disk 30)); overlay, centered
(table 2 (list a b c d) cc-superimpose cc-superimpose 10 10)  ; a grid

(colorize (disk 20) "red")                  ; recolor
(scale (circle 10) 2)   (rotate (rectangle 30 10) 0.5)   (scale-to-fit p 40 40)
(frame (inset p 8))                         ; border with padding
(linewidth 3 (circle 10))   (ghost p)   (cellophane p 0.5)  ; thicker / invisible / faint
```

Every pict has geometry: `pict-width`, `pict-height`, `pict-ascent`,
`pict-descent` — use them to position things precisely.

### Connecting picts into diagrams

Lay out child picts, then draw connectors between them by *finding* their
positions in the combined picture. A find function (`cc-find`, `lt-find`,
`cb-find`, …) returns a sub-pict's location in a base; `pin-line` /
`pin-arrow-line` draw between two found points:

```racket
(define a (disk 30)) (define b (disk 30))
(define base (vc-append 60 a b))
(pin-arrow-line 8 base a cb-find b ct-find) ; arrow from bottom of a to top of b
```

- `pin-over` / `pin-under` place a pict at a coordinate without changing the
  base's bounding box; `panorama` then grows the box to include overflow.
- The sub-pict you pass to a find function must be the *same value* embedded
  in the base — keep a binding to it (don't reconstruct an equal pict).

### Rendering and bridging back

`(pict->bitmap p)` rasterizes a pict to a `bitmap%`; `(dc draw-proc w h)`
goes the other way — wraps imperative `dc<%>` drawing as a pict of size
`w×h`, so you can drop custom `racket/draw` code into a pict composition.
Sub-libraries add effects: `pict/color` (`red`, `green`, …), `pict/shadow`
(`shadow`), `pict/conditional` (`show`/`hide` for staged reveals),
`pict/balloon`, `pict/flash`.

## Rules that prevent rework

- **Compose with pict; draw pixels with racket/draw.** Reach for pict's pure
  combinators for layout and diagrams (declarative, testable by bounding
  box); use `dc<%>` for per-pixel control or file output. Bridge with `dc`
  and `pict->bitmap` when you need both.
- **Save and restore the transformation.** Wrap `translate`/`scale`/`rotate`
  in `get-transformation` … `set-transformation` so later drawing isn't
  skewed by leftover transforms.
- **Reuse pens and brushes from the caches.** `the-pen-list`/`the-brush-list`
  return shared instances; allocating a `new pen%` per draw call is wasted
  work in a hot paint loop ([[profiling]]).
- **`pin-over` overflows the bounding box — use `panorama`.** Content pinned
  past the edges is clipped by the parent unless you `panorama` to widen the
  box.
- **Find the embedded pict, not a copy.** `cc-find` and friends locate a
  specific sub-pict value; pass the binding you appended, or the location
  lookup fails.
- **Vector dcs need the document lifecycle.** `pdf-dc%`/`post-script-dc%`
  produce nothing until `start-doc`/`start-page` … `end-page`/`end-doc`; build
  them with `[interactive #f]`.
