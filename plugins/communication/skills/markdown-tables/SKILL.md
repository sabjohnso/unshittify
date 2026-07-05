---
description: Reformat one or more markdown tables so every pipe lines up into a fixed-width column, computing each column's width from its widest cell and preserving each column's declared left/center/right alignment from the header separator row. Use when writing or editing a markdown table whose columns are not visually aligned, or when the user asks to fix, align, or clean up a markdown table's formatting.
argument-hint: "[file path or pasted table]"
allowed-tools: Read, Grep, Glob, Edit
---

# Align markdown tables

Goal: rewrite a markdown table so every pipe in every row lines up in a fixed-width column, without changing any cell's text or the table's declared alignment.

## How a markdown table encodes alignment

The row directly under the header is the separator row; the colons in each column's dashes set that column's alignment, not any per-cell markup:

| Separator cell | Alignment       |
|----------------|-----------------|
| `---`          | left (default)  |
| `:---`         | left (explicit) |
| `:---:`        | center          |
| `---:`         | right           |

Read this row before touching any cell — it is the single source of truth for how to pad each column, and the rewritten separator row must reproduce the same colons.

## Computing column widths

1. For each column, measure the length of every cell in that column, including the header — the widest cell sets the column's fixed width. Use a floor of 3 characters even if every cell is shorter, since the separator row needs room for `---` (or `:--`, `--:`, `:-:`).
2. Treat the separator row's own width as generated from the column's alignment, not measured from whatever dashes are already there.
3. Recompute every column's width after any edit to a cell — adding or shortening text in one row changes the padding required for every other row in that column.

## Padding rule per alignment

- **Left** (`---` or `:---`): pad on the right with spaces up to the column width.
- **Right** (`---:`): pad on the left.
- **Center** (`:---:`): split the padding as evenly as possible between both sides, with the extra space (if the padding is odd) on the right.

## Steps

1. Obtain the table: if given a file path, read it; if pasted, use it directly. If a file has multiple tables, process each independently — column widths do not carry across tables.
2. Parse the header row, the separator row, and every body row by splitting on unescaped `|`. Trim each cell before measuring; a cell's leading or trailing space in the source is formatting, not content.
3. Read the separator row's colons to fix each column's alignment per the table above.
4. Compute each column's width per "Computing column widths."
5. Re-emit every row — header, separator, body — with each cell padded to its column's width per the alignment rule, and exactly one space on each side of the padded cell before the surrounding pipes (`| cell   |`, not `|cell   |`).
6. If the source was a file, apply the rewrite with Edit; otherwise return the corrected table directly, with no commentary, unless asked to explain what changed.

## Rules that prevent rework

- **Never reflow cell text.** This skill fixes the spacing between pipes, not word choice, wrapping, or cell content — a cell containing a long sentence stays on one line; only the surrounding padding changes.
- **Preserve escaped pipes.** A `\|` inside a cell is content, not a column separator — split a row on `|` only when that `|` is not preceded by a backslash.
- **Don't assume every row has the same cell count as the header.** A malformed table — a row with fewer or more cells than the header — should be flagged rather than silently padded to fit; report it instead of guessing which column is missing.
