---
description: Review a piece of prose — a drafted chat response, a document, or a file — for the writing problems catalogued in BadProseExamples.org and the Communicate Clearly rules in CLAUDE.md, and fix what's found. Use before sending a substantial piece of written prose (an explanation, a report, an article, a doc file) to the user, or when the user asks to review, critique, or proofread prose.
argument-hint: "[file path or pasted prose]"
allowed-tools: Read, Grep, Glob, Edit
---

# Review prose for house-style problems

Goal: catch the writing failures this project has flagged before, and fix them — not just list them.

## What counts as "prose" here

- A drafted chat response carrying explanation, analysis, or narrative — not a one-line status update, a code diff, or a terse confirmation.
- A document, README, article, or other file about to be written or already written.
- Text the user pastes in directly for critique.

Skip trivial or already-terse text; reviewing a one-sentence answer for "buzzwords" is wasted motion.

## Checklist

1. **Buzzwords / pseudo-intellectual corporate jargon** — phrases that sound impressive but say less than a plain sentence would.
2. **"Surface" misused for "API"/"interface"** — say the concrete word.
3. **Personification or cute metaphor standing in for a precise claim** — e.g. a tool described as "polite" or two components that "disagree," where the reader still has to guess what actually happened in the code.
4. **Headline-style bolded topic sentences** — a bullet's lead phrase built for punch ("needs a checklist, not heroics") rather than a plain statement of fact; reads like a slide deck, not engineering prose.
5. **Certainty or superlatives asserted without a measurement** — "the cheapest fix available," "the worst case," stated with no comparison or count behind it.
6. **Nominalization / denominalization** — abstract nouns papering over a concrete mechanism ("silent acceptance" instead of "the parser accepts malformed input and returns a value instead of erroring").
7. **Undefined abbreviations** — any shorthand, code, or acronym used without being spelled out at first use.
8. **Unverified claims or hallucination** — a number, status, or fact stated without having been checked this session.
9. **Informal register** — anything that reads as glib or dashed-off where the content calls for formal, explicit prose.

## Steps

1. Obtain the text: if the argument is a file path, read it; if it's pasted or drafted text, use it directly.
2. If `BadProseExamples.org` exists at the repository root, read its "Noted Problems" entries too — that catalogue accumulates new examples over time and may include failures not yet folded into the checklist above.
3. Walk the checklist against the text, quoting each offending phrase and naming which check it fails.
4. Revise the text to fix every confirmed problem. Preserve the original meaning, facts, and numbers — this is a register and precision pass, not a rewrite of content.
5. Apply the fix: if the source was a file, edit it in place and report which lines changed; if the source was a response about to be sent to the user, the corrected text becomes that response — do not send the flagged draft.
6. If nothing was wrong, say so rather than inventing a rewrite to justify the review.
