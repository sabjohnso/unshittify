---
description: Review a piece of prose — a drafted chat response, a document, or a file — for the writing problems catalogued below and the Communicate Clearly rules in CLAUDE.md, and fix what's found. Use before sending a substantial piece of written prose (an explanation, a report, an article, a doc file) to the user, or when the user asks to review, critique, or proofread prose.
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
10. **Throat-clearing transitions** — filler openers that signal a shift in topic without adding content ("That said," "It's worth noting that," "At the end of the day"). Cut them; the sentence should stand on its own.
11. **Redundant restatement** — a clause that repeats information an earlier word already implies (e.g., "a new dependency, which the repository did not previously have" — "new" already says this). State the fact once.
12. **Padded verb emphasis** — an auxiliary added for emphasis without adding meaning ("does introduce" instead of "introduces," "did in fact confirm" instead of "confirmed"). Use the plain verb.

## Examples from past reviews

This catalogue accumulates real instances found in past reviews. It
supplements the checklist above — draw on it when a piece of prose
resembles one of these patterns even if it doesn't fall cleanly under
one of the nine checks.

### Example 1: from a review by Fable 5

> - **The totality discipline needs a checklist, not heroics.** Every
>   "total boundary" finding (reader m3, expander C1/C2, core C1/C3/M5) is
>   the same failure: a newer seam was added after the boundary was built,
>   and nothing forces new seams through the boundary's catch. A single
>   convention — every exception type translated at the boundary, every
>   recursive walk either iterative or guarded by the depth budget — plus a
>   property test per boundary ("hostile input never crashes") would hold
>   the line mechanically.
> - **Silent acceptance is the recurring worst case.** The most dangerous
>   findings are not crashes but silent wrong answers: `#true` → `#t rue`,
>   `(define x 1)(define x 2)` → 1, primitive shadowing, wrong-callee
>   generics, type-confused `match`, stage-1 escape divergence, stale
>   fixpoint "ok". The project's own tenet (fail loudly) already names the
>   fix; these are the places it was not applied.
> - **Property-test generators are too polite.** Three separate reviewers
>   traced missed bugs to sanitized generators (symbols restricted to
>   `[a-z0-9]+`, no surrogate discipline, no deep macro-synthesized syntax,
>   bigint example tests only). The RapidCheck infrastructure is already in
>   place; widening the generators is the cheapest systematic improvement
>   available.
> - **Two checkers disagree about who owns a rule.** Core-level errors
>   (duplicate defines, non-exhaustive match effects, unit-across-join) are
>   deferred to the asm checker, which reports them in the wrong vocabulary
>   or not at all; meanwhile stage 1 defers to a validation pass that never
>   runs. Each rule needs one named owner.

**Noted problems with this prose:**

- **Cute personification substitutes for a precise claim.** "Property-test
  generators are too polite" and "Two checkers disagree about who owns a
  rule" give tools human traits — politeness, disagreement — instead of
  naming the actual fact: which generator under-covers which input class,
  or which component is supposed to enforce which rule and isn't. The
  metaphor is memorable, but the reader still has to guess what "polite"
  or "disagree" mean in terms of code.
- **Bolded lead sentences read as headlines, not topic sentences.** Every
  bullet opens with a bolded soundbite — "needs a checklist, not
  heroics," "is the recurring worst case," "are too polite" — built for
  punch rather than precision. That is the register of a slide deck, not
  formal engineering prose. The instruction to speak formally and avoid
  pseudo-intellectual framing rules out exactly this kind of consultant
  takeaway-slide phrasing.
- **Unexplained shorthand makes the claims unverifiable.** "reader m3,"
  "expander C1/C2," "core C1/C3/M5" are cited as evidence with no gloss on
  what the labels mean (finding IDs? line ranges? test names?). A reader
  without access to whatever document assigned those codes cannot check
  the claim. Abbreviations should be defined at first use; here they
  never are.
- **Certainty is asserted without the measurement behind it.** "The
  cheapest systematic improvement available" and "the recurring worst
  case" are stated as settled fact. Nothing quoted shows a comparison
  against other candidate improvements, or a tally showing this bug class
  recurs most often. A superlative like this needs the comparison or
  count that supports it, or it should be cut down to what was actually
  observed.
- **Abstract nouns stand in for the concrete mechanism.** "The totality
  discipline," "silent acceptance," "stage-1 escape divergence" are
  nominalizations naming a category of problem rather than the problem
  itself. "Silent acceptance," for instance, could instead say plainly
  that the parser accepts malformed input and returns a value rather than
  erroring. The abstraction reads as more authoritative, but it defers
  the real content — the actual failure mode — to the reader's inference.

### Example 2: build-dependency disclosure

> That said, this does introduce a new build-time dependency on a Python
> 3 interpreter, which the repository did not previously have. If you
> would rather this run as a first-party C++ or shell tool to avoid that
> dependency, tell me and I will rewrite it that way.

**Noted problems with this prose:**

- **A throat-clearing opener adds a sentence with no content.** "That
  said," signals a shift in topic but states nothing itself; the
  sentence that follows stands on its own without it.
- **A padded verb inflates a plain fact.** "Does introduce" is emphasis
  without meaning; "introduces" says the same thing.
- **A clause restates what an earlier word already said.** ", which the
  repository did not previously have" repeats what "new" already states
  about the dependency — the fact appears twice in one sentence.

Corrected: "This introduces a new build-time dependency on a Python 3
interpreter. Tell me if you'd rather this run as a first-party C++ or
shell tool instead, and I'll rewrite it that way."

## Steps

1. Obtain the text: if the argument is a file path, read it; if it's pasted or drafted text, use it directly.
2. Walk the checklist above, and the examples catalogue, against the text, quoting each offending phrase and naming which check it fails.
3. Revise the text to fix every confirmed problem. Preserve the original meaning, facts, and numbers — this is a register and precision pass, not a rewrite of content.
4. Apply the fix and report:
   - If the source was a drafted chat response about to be sent to the user, do not print the problem list from step 2 or the flagged draft — the corrected text simply becomes the response, with no review commentary around it.
   - If the source was a file or text the user explicitly asked to critique, edit the file in place (or return the corrected text) along with the problem list from step 2, so the user can see what was wrong and why.
5. If nothing was wrong, say so rather than inventing a rewrite to justify the review.
