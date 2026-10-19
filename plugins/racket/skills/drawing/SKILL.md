---
description: Render Racket graphics with racket/draw and pict, with no window. Covers imperative draws on a dc<%> (bitmap-dc%, svg-dc%, pdf-dc%, post-script-dc%, pens, brushes, dc-path%, transforms, text metrics) and composable pictures with pict (circle, text, append, superimpose, colorize, scale, rotate, pin-arrow-line connectors, pict->bitmap). Use when you produce an image, a diagram, or an SVG, PDF, or PostScript file, when you compose or measure picts, or when you look up a dc<%> or pict procedure. For the window and the widgets around a canvas, see ../gui/SKILL.md. For a redraw loop that a timer drives, see ../canvas-animation/SKILL.md.
allowed-tools: Read, Grep, Glob
---

# Drawing: racket/draw and pict

There are two layers, and you use them together:

For the full `dc<%>` method list, the `dc-path%` and resource signatures,
and the pict constructor catalogue, read `reference.md` in this skill
directory.

- **`racket/draw`** is imperative. You draw on a **drawing context**
  (`dc<%>`). You set a pen and a brush, then you issue `draw-line`,
  `draw-rectangle`, `draw-text`, and so on. The same `dc<%>` API targets
  bitmaps, GUI canvases ([gui](../gui/SKILL.md)), and vector files (SVG,
  PDF, PostScript).
- **`pict`** is a functional picture library on top of it. A `pict` is an
  immutable value with a bounding box. Pure functions create and combine
  picts (`hc-append`, `cc-superimpose`, `colorize`). A pict renders to a
  `dc<%>` when it is shown.

Choose **pict** to compose and lay out pictures and diagrams declaratively.
Drop to **`racket/draw`** for pixel-level control or to produce an image
file. DrRacket shows a `pict` inline, and Scribble embeds picts
([scribble-docs](../scribble-docs/SKILL.md)).

## racket/draw: draw on a dc<%>

Get a context, set the draw state, and issue commands. A `bitmap-dc%` draws
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
(send bm save-file "out.png" 'png)        ; PNG, JPEG, and other formats
```

Other contexts: the `get-dc` of a GUI `canvas%` ([gui](../gui/SKILL.md)),
and the vector back ends `svg-dc%`, `pdf-dc%`, and `post-script-dc%` for a
file that is independent of the resolution. A vector back end builds a
**stateful document**. Construct it with `[interactive #f]`, then bracket
the draws with the page life cycle:

```racket
(define dc (new pdf-dc% [interactive #f] [width 200] [height 150] [output "fig.pdf"]))
(send dc start-doc "fig") (send dc start-page)
(send dc draw-line 0 0 200 150)
(send dc end-page) (send dc end-doc)       ; flushes the file
```

The key pieces of the `dc<%>` model:

- **The pen and the brush** decide the outline and the fill: `(set-pen
  pen%-or "color" w style)`, `(set-brush brush%-or "color" style)`. Use the
  cached instances from `the-pen-list`, `the-brush-list`, and
  `the-color-database`. Do not allocate one per draw.
- **A path** (`dc-path%`) describes an arbitrary shape (`move-to`,
  `line-to`, `curve-to`, `close`). Then call `(send dc draw-path p)`.
- **The state**: `translate`, `scale`, and `rotate` transform the coordinate
  system. Save and restore it with `get-transformation` and
  `set-transformation` around a block. `set-alpha` sets the opacity.
  `set-clipping-rect` and `set-clipping-region` mask. `set-smoothing` sets
  the antialias mode. A gradient is a `linear-gradient%` or a
  `radial-gradient%` set as a brush.

## pict: composable pictures

Build pictures from constructors, and combine them functionally:

```racket
(require pict)
(circle 30)  (disk 20)  (filled-rectangle 40 20)  (rounded-rectangle 40 20 5)
(text "label" '(bold) 18)  (hline 30 1)  (arrow 20 0)  (blank 10 10)
(bitmap a-bitmap%)                          ; wrap a racket/draw bitmap as a pict
```

Combine along an axis or by a stack, then style:

```racket
(hc-append 10 (circle 20) (disk 20))        ; horizontal, with the centers aligned
(vl-append 5 (text "a") (text "bb"))        ; vertical, with the left edges aligned
(cc-superimpose (rectangle 60 60) (disk 30)); an overlay, centered
(table 2 (list a b c d) cc-superimpose cc-superimpose 10 10)  ; a grid

(colorize (disk 20) "red")                  ; a new color
(scale (circle 10) 2)   (rotate (rectangle 30 10) 0.5)   (scale-to-fit p 40 40)
(frame (inset p 8))                         ; a border with padding
(linewidth 3 (circle 10))   (ghost p)   (cellophane p 0.5)  ; thicker / invisible / faint
```

Every pict has a geometry: `pict-width`, `pict-height`, `pict-ascent`, and
`pict-descent`. Use them to position things precisely.

### Connect picts into a diagram

Lay out the child picts, then draw connectors between them. *Find* their
positions in the combined picture. A find function (`cc-find`, `lt-find`,
`cb-find`, and so on) returns the location of a sub-pict in a base.
`pin-line` and `pin-arrow-line` draw between two found points:

```racket
(define a (disk 30)) (define b (disk 30))
(define base (vc-append 60 a b))
(pin-arrow-line 8 base a cb-find b ct-find) ; an arrow from the bottom of a to the top of b
```

- `pin-over` and `pin-under` put a pict at a coordinate. They do not change
  the bounding box of the base. `panorama` then grows the box to include the
  overflow.
- The sub-pict that you pass to a find function must be the *same value*
  that is embedded in the base. Keep a binding to it. Do not construct an
  equal pict again.

### Render, and go back the other way

`(pict->bitmap p)` rasterizes a pict to a `bitmap%`. `(dc draw-proc w h)`
goes the other way. It wraps imperative `dc<%>` draws as a pict of size
`w×h`. So you can put custom `racket/draw` code into a pict composition.
Sub-libraries add effects: `pict/color` (`red`, `green`, …), `pict/shadow`
(`shadow`), `pict/conditional` (`show` and `hide` for a staged reveal),
`pict/balloon`, and `pict/flash`.

## Rules that prevent rework

- **Compose with pict. Draw pixels with racket/draw.** Use the pure
  combinators of pict for layout and diagrams (declarative, testable by the
  bounding box). Use `dc<%>` for control per pixel or for file output.
  Bridge with `dc` and `pict->bitmap` when you need both.
- **Save and restore the transformation.** Wrap `translate`, `scale`, and
  `rotate` in `get-transformation` … `set-transformation`. Otherwise a
  leftover transform skews the later draws.
- **Use the pens and the brushes from the caches.** `the-pen-list` and
  `the-brush-list` return shared instances. A `new pen%` per draw call is
  wasted work in a hot paint loop ([profiling](../profiling/SKILL.md)).
- **`pin-over` overflows the bounding box. Use `panorama`.** The parent clips
  the content that is pinned past the edges, unless you widen the box with
  `panorama`.
- **Find the embedded pict, not a copy.** `cc-find` and the related
  functions locate a specific sub-pict value. Pass the binding that you
  appended. Otherwise the lookup of the location fails.
- **A vector dc needs the document life cycle.** `pdf-dc%` and
  `post-script-dc%` produce nothing before `start-doc` and `start-page` …
  `end-page` and `end-doc`. Build them with `[interactive #f]`.
