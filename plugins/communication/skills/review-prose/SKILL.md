---
description: Review a piece of prose (a drafted chat response, a document, or a file) against Simplified Technical English (ASD-STE100) and the writing problems in the checklist below, and fix each problem found. Use before you send a substantial piece of prose (an explanation, a report, an article, a document) to the user, or when the user asks for a review, a critique, or a proofread of prose.
argument-hint: "[file path or pasted prose]"
allowed-tools: Read, Grep, Glob, Edit
---

# Review prose for house-style problems

Goal: make the prose obey Simplified Technical English (ASD-STE100), find the writing failures that this project flagged before, and fix them. Do not only list them.

## What counts as "prose" here

- A drafted chat response with an explanation, an analysis, or a narrative. Not a one-line status update, a code diff, or a short confirmation.
- A document, a README, an article, or another file that is about to be written or is already written.
- Text that the user pastes in directly for a critique.

Skip trivial or short text. A review of a one-sentence answer for "buzzwords" is a waste of effort.

## Simplified Technical English (STE) checks

Every piece of prose must obey the rules of Simplified Technical English, the controlled language of the specification ASD-STE100. The condensed rules are in the `communication:simplified-technical-english` skill. The checks below are the ones that fail most often. Apply them first, before the house-style checklist, and apply them to every sentence.

1. **Sentence length** — an instruction has at most 20 words. A descriptive sentence has at most 25 words. Split a longer sentence.
2. **Verb forms** — only the infinitive, the imperative, the simple present, the simple past, the past participle as an adjective, and the future with "will". No "-ing" verb ("the hook is blocking"). No helping-verb tense ("has blocked", "had been blocked").
3. **Active voice** — the actor is the subject. An instruction is in the imperative. A passive sentence is permitted only in description, and only when the actor is unknown or unimportant.
4. **Requirement words** — "must" for a requirement, "can" for ability or possibility. No "should", "may", or "might".
5. **One instruction per sentence** — two actions share a sentence only when they occur at the same time. The condition comes before the instruction: "If the test fails, stop."
6. **Noun clusters** — at most three nouns in a row. Rewrite a longer cluster with "of", "for", or a hyphen.
7. **Articles** — a noun carries "the", "a", "an", "this", or "these".
8. **Unapproved words** — replace each word in the left column with the word in the right column:

   | Do not write        | Write                    |
   |---------------------|--------------------------|
   | ensure, verify      | make sure                |
   | utilize, leverage   | use                      |
   | perform             | do                       |
   | obtain              | get                      |
   | initiate, commence  | start                    |
   | terminate           | stop                     |
   | modify              | change                   |
   | indicate            | show                     |
   | attempt             | try                      |
   | assist              | help                     |
   | prior to            | before                   |
   | in order to         | to                       |
   | should              | must                     |
   | may, might          | can, or "it is possible" |
   | is required         | is necessary, or "must"  |

9. **Abbreviations** — the first use spells the abbreviation out. Later uses can use the short form.
10. **Paragraphs** — one topic, at most six sentences, the key sentence first.
11. **Punctuation** — no semicolon. No dash that joins two thoughts. Parentheses hold only a reference or a short clarification. Write two sentences instead.
12. **Technical names and technical verbs** — a software name (a file, a tool, a type, a command) is a technical name. Write it as a code span. A technical process (compile, commit, parse, merge) is a technical verb. Both are permitted. Code identifiers, quoted text, and the haiku at the end of a commit message are outside STE.

## House-style checklist

1. **Buzzwords and pseudo-intellectual corporate jargon.** Phrases that sound impressive but say less than a plain sentence.
2. **"Surface" in the place of "API" or "interface".** Write the concrete word.
3. **Personification or a cute metaphor in the place of a precise claim.** For example, a tool is "polite", or two components "disagree". The reader still has to guess what occurred in the code.
4. **Bold topic sentences in the style of a headline.** The lead phrase of a bullet is built for effect ("needs a checklist, not heroics") and not as a plain statement of fact. It reads as a slide deck, not as engineering prose.
5. **Certainty or a superlative with no measurement.** "The cheapest fix available", "the worst case", with no comparison and no count behind it.
6. **Nominalization and denominalization.** An abstract noun that hides a concrete mechanism ("silent acceptance" instead of "the parser accepts malformed input and returns a value instead of an error").
7. **Undefined abbreviations.** A short form, a code, or an acronym with no spelled-out first use.
8. **Unverified claims or hallucination.** A number, a status, or a fact that was not checked this session.
9. **Informal register.** Text that reads as glib or hasty where the content calls for formal, explicit prose.
10. **Throat-clearing transitions.** A filler opener that signals a new topic and adds no content ("That said", "It's worth noting that", "At the end of the day"). Cut it. The sentence must stand on its own.
11. **Redundant restatement.** A clause that repeats what an earlier word already says. For example, "a new dependency, which the repository did not have before". "New" already says this. State the fact once.
12. **Padded verb emphasis.** An auxiliary added for emphasis that adds no meaning ("does introduce" instead of "introduces", "did in fact confirm" instead of "confirmed"). Use the plain verb.
13. **Invented words.** A coinage where an established word exists ("shutdownable", "de-locates", "freehand" as a verb, "side code"). Replace it with the established term ("easy to shut down cleanly", "strips source locations", "written without the template", "side-effecting code").
14. **A term from a domain where it means something else.** "Hygiene" for package dependencies, when it already names a macro property. The "box model" of CSS for a widget-container layout. Choose a word with no competing technical meaning in the context.
15. **Passive voice that hides the actor.** "Only after the report is shown" does not say who shows it. In an instruction, name the actor: "only after you have shown the report."
16. **A vague or wrong referent.** A noun phrase or a pronoun whose antecedent the reader must guess ("this toolset" where nothing is named a toolset, "the interesting space" for an input distribution).
17. **A sentence that parses the wrong way at first.** Garden paths and misattached modifiers. In "...avoid pseudo-intellectual framing rules out...", the reader first takes "framing rules" as a noun phrase. A "not X" at the end attaches to the nearest noun and not to the intended one. If a sentence needs a second read, restructure it.
18. **Stale counts and cross-references.** A stated count, a section name, or a pointer that does not match its target ("one of the nine checks" above a longer list, "the table above" when the table is in a different file, "Both scripts" for three). Check each one against its target. Prefer words that cannot drift ("the numbered checks above").
19. **Inconsistent terminology.** One concept with different names in one document or across two paired documents ("takes a predicate" in one place, "wants a predicate" in another, "parse an AST" and "build an AST"). Pick one term and use it throughout.
20. **Ungrammatical sentences.** A comma splice ("`#:when`/`#:unless` nest, they don't just filter"), a verb that disagrees with its compound subject, a misplaced adverb ("returns silently empty"), or a broken parallel ("computation the user waits on and needlessly wastes": the user waits, the code wastes). Fix the grammar and keep the claim.
21. **Sentence fragments that block understanding.** A fragment whose missing subject or verb leaves the claim unclear ("Same failure as before. Different cause." Which failure, and whose cause?). A short fragment is acceptable in a reference table, a heading, or an instruction where the elided words are obvious. Flag a fragment only when the reader must guess what was left out.

## Examples from past reviews

The examples below are a fixed, curated set: nothing appends to them
during a review. They supplement the checklist above — draw on one when a
piece of prose resembles it even if it doesn't fall cleanly under one of
the numbered checks.

The live, growing catalogue is `BadProseExamples.org` at the root of the
repository the session is working in. Read it before reviewing, when it is
there; it records prose failures flagged since these examples were
written. It is untracked, so it is absent on a fresh checkout and in any
project that doesn't keep one. When it is missing, review against the
checklist and the examples below alone — do not report its absence and do
not create it.

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
  formal engineering prose. This consultant takeaway-slide phrasing is
  exactly what the instruction to speak formally and avoid
  pseudo-intellectual framing rules out.
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
  erroring. The abstraction reads as more authoritative, but it leaves
  the reader to infer the real content — the actual failure mode.

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

### Example 3: from a repository-wide audit of plugin prose

Representative lines flagged in a July 2026 audit of this repository's
own skill and agent files:

> - "keep them correct and shutdownable"
> - "returning raw data works but de-locates the result"
> - "surface the command verbatim in your report"
> - "This skill only curates plugins that are already installed."
> - "**Samples taken** is the trust meter."
> - "add missing repository hook wiring back into the file"
> - "convert (or deliberately leave) a loop per the table above" — in a
>   file containing no table

**Noted problems with this prose:**

- **Invented words replace established ones.** "Shutdownable" and
  "de-locates" exist nowhere outside these files; "easy to shut down
  cleanly" and "strips source locations" say the same thing in words
  the reader already knows.
- **A fancy or corporate verb stands in for the concrete action.**
  "Surface the command" means "quote the command"; "curates plugins"
  means "enables or disables plugins." The plain verb tells the reader
  exactly what happens.
- **A metaphor replaces the precise claim.** "Is the trust meter"
  makes the reader unpack the figure of speech; "tells you how much to
  trust the percentages" states the claim directly.
- **A reference presumes facts not in evidence, or points nowhere.**
  "Back into the file" presumes the wiring was once present, which may
  be false; "the table above" points at a table that lives in a
  different file. Check every count and cross-reference against its
  target.

## Steps

1. Get the text. If the argument is a file path, read the file. If the argument is pasted or drafted text, use it directly. In the same pass, read `BadProseExamples.org` at the root of the repository if it exists. If it does not exist, continue without it.
2. Apply the STE checks above to every sentence. Count the words in each sentence. Find each "-ing" verb, each helping verb, each passive sentence, each "should" or "may", and each word in the substitution table. Quote each offending sentence and name the STE check that it fails.
3. Check the text against the house-style checklist, the examples catalogue, and the content of `BadProseExamples.org`. Quote each offending phrase and name the check that it fails.
4. Revise the text to fix every confirmed problem. Keep the original meaning, facts, and numbers. This is a pass for register and precision, not a rewrite of the content. The corrected text must pass the STE checks. Read it once more and count the words of each sentence again.
5. Apply the fix and report:
   - If the source was a drafted chat response for the user, do not print the problem lists from steps 2 and 3 and do not print the flagged draft. The corrected text becomes the response, with no review commentary around it.
   - If the source was a file, or text that the user explicitly asked you to critique, edit the file in place (or return the corrected text) with the problem lists from steps 2 and 3. Thus the user can see what was wrong and why.
6. If nothing was wrong, say so. Do not invent a rewrite to justify the review.
