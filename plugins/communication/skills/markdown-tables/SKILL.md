---
description: Reformat one or more markdown tables so that every pipe aligns in a fixed-width column. Compute the width of each column from its widest cell, and keep the declared left, center, or right alignment of each column from the header separator row. Use when you write or edit a markdown table whose columns are not visually aligned, or when the user asks you to fix, align, or clean up the format of a markdown table.
argument-hint: "[file path or pasted table]"
allowed-tools: Read, Grep, Glob, Edit
---

# Align markdown tables

Goal: rewrite a markdown table so that every pipe in every row aligns in a fixed-width column. Do not change the text of a cell or the declared alignment of the table.

## How a markdown table encodes the alignment

The row directly under the header is the separator row. The colons in the dashes of each column set the alignment of that column. No per-cell markup does.

| Separator cell | Alignment       |
|----------------|-----------------|
| `---`          | left (default)  |
| `:---`         | left (explicit) |
| `:---:`        | center          |
| `---:`         | right           |

Read this row before you touch a cell. It alone decides how to pad each column, and the rewritten separator row must have the same colons.

## How to compute the column widths

1. For each column, measure the length of every cell in that column, with the header. The widest cell sets the fixed width of the column. Use a minimum of 3 characters, also when every cell is shorter, because the separator row needs room for `---` (or `:--`, `--:`, `:-:`).
2. Treat the width of the separator row as a value that comes from the alignment of the column. Do not measure the dashes that are already there.
3. Compute the width of every column again after each edit of a cell. Added or removed text in one row changes the necessary padding for every other row in that column.

## The padding rule per alignment

- **Left** (`---` or `:---`): pad on the right with spaces up to the column width.
- **Right** (`---:`): pad on the left.
- **Center** (`:---:`): split the padding between both sides as evenly as possible. If the padding is odd, put the extra space on the right.

## Steps

1. Get the table. If you get a file path, read the file. If the table is pasted, use it directly. If a file has several tables, process each one on its own. Column widths do not carry across tables.
2. Parse the header row, the separator row, and every body row. Split each row on each unescaped `|`. Trim each cell before you measure it. A leading or trailing space in a cell is format, not content.
3. Read the colons of the separator row to fix the alignment of each column per the table above.
4. Compute the width of each column per "How to compute the column widths".
5. Emit every row again: the header, the separator, and the body. Pad each cell to the width of its column per the alignment rule. Put exactly one space on each side of the padded cell, before the pipes (`| cell   |`, not `|cell   |`).
6. If the source was a file, apply the rewrite with Edit. Otherwise return the corrected table directly, with no commentary, unless the user asks for an explanation of the changes.

## Rules that prevent rework

- **Never reflow the text of a cell.** This skill fixes the spaces between the pipes. It does not change the words, the wraps, or the content of a cell. A cell with a long sentence stays on one line. Only the padding around it changes.
- **Keep escaped pipes.** A `\|` inside a cell is content, not a column separator. Split a row on a `|` only when no backslash is before that `|`.
- **Do not assume that every row has the same cell count as the header.** If a row has fewer or more cells than the header, stop and report it. Do not guess which column is missing, and do not pad around the mismatch.
