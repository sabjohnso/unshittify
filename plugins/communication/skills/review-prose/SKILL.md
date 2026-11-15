---
description: Review a piece of prose against Simplified Technical English (ASD-STE100) and the checklist below, and fix each problem. The prose can be a drafted chat response, a document, or a file. Use before you send a substantial piece of prose to the user. Examples are an explanation, a report, an article, and a document. Also use when the user asks for a review, a critique, or a proofread of prose.
argument-hint: "[file path or pasted prose]"
allowed-tools: Read, Grep, Glob, Edit
---

# Review prose for house-style problems

Goal: make the prose obey Simplified Technical English (ASD-STE100). Find the prose failures that this project flagged before, and fix them. Do not only list them.

## What counts as "prose" here

These texts count as prose:

- A drafted chat response that holds an explanation, an analysis, or a narrative.
- A document, a README, an article, or another file, before or after someone writes it.
- Text that the user pastes in directly for a critique.

A one-line status update, a code diff, and a short confirmation do not count. Skip trivial or short text. A review of a one-sentence answer for "buzzwords" is a waste of effort.

## Simplified Technical English (STE) checks

Every piece of prose must obey the rules of Simplified Technical English, the controlled language of the specification ASD-STE100. The condensed rules are in the `communication:simplified-technical-english` skill. The checks below are the ones that fail most often. Apply them first, before the house-style checklist. Apply them to every sentence.

1. **Sentence length.** An instruction has at most 20 words. A descriptive sentence has at most 25 words. Split a longer sentence.
2. **Verb forms.** Use only the approved verb forms. They are the infinitive, the imperative, the simple present, the simple past, the past participle as an adjective, and the future with "will". Do not use an "-ing" verb ("the hook is blocking"). Do not use a tense with a helping verb ("has blocked", "had been blocked").
3. **Active voice.** The actor is the subject. An instruction is in the imperative. STE permits a passive sentence only in description, and only when the actor is unknown or unimportant.
4. **Requirement words.** Use "must" for a requirement. Use "can" for ability or possibility. Do not use "should", "may", or "might".
5. **One instruction per sentence.** Two actions share a sentence only when they occur at the same time. The condition comes before the instruction: "If the test fails, stop."
6. **Noun clusters.** Put at most three nouns in a row. Rewrite a longer cluster with "of", "for", or a hyphen.
7. **Articles.** A noun carries "the", "a", "an", "this", or "these".
8. **Unapproved words.** Replace each word in the left column with the word in the right column:

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

9. **Abbreviations.** The first use spells the abbreviation out. Later uses can use the short form.
10. **Paragraphs.** A paragraph has one topic and at most six sentences. The key sentence comes first.
11. **Punctuation.** Do not use a semicolon. Do not use a dash that joins two thoughts. Write two sentences. Parentheses hold only a reference or a short clarification.
12. **Technical names and technical verbs.** A software name (a file, a tool, a type, a command) is a technical name. Write it as a code span. A technical process (compile, commit, parse, merge) is a technical verb. STE permits both. Code identifiers, quoted text, and the haiku at the end of a commit message are outside STE.
13. **"-ing" adjectives.** The rule on "-ing" verbs also applies to an adjective ("the offending sentence", "the remaining files"). Write the past participle or a plain adjective ("the faulty sentence", "the other files").
14. **Passive with a known actor.** STE permits a passive sentence in description only when the actor is unknown or unimportant. If the text names the actor, or if the reader can name it, write the active form. Write "STE permits a passive sentence", not "a passive sentence is permitted".
15. **List items.** Each item of a vertical list is a complete sentence with a verb. As an alternative, the lead-in sentence and the item together make one complete sentence. A fragment with no verb ("No semicolon.") is not a list item.

## House-style checklist

1. **Buzzwords and pseudo-intellectual corporate jargon.** These phrases sound impressive, but they say less than a plain sentence.
2. **"Surface" in the place of "API" or "interface".** Write the concrete word.
3. **Personification or a cute metaphor in the place of a precise claim.** For example, a tool is "polite", or two components "disagree". The reader must then guess what occurred in the code.
4. **Bold topic sentences in the style of a headline.** The writer builds the lead phrase of a bullet for effect ("needs a checklist, not heroics") and not as a plain statement of fact. The result reads as a slide deck, not as engineering prose.
5. **Certainty or a superlative with no measurement.** Examples are "the cheapest fix available" and "the worst case", with no comparison and no count to support them.
6. **Nominalization and denominalization.** An abstract noun hides a concrete mechanism. For example, "silent acceptance" hides "the parser accepts malformed input and returns a value instead of an error".
7. **Undefined abbreviations.** A short form, a code, or an acronym has no spelled-out first use.
8. **Unverified claims or hallucination.** The text states a number, a status, or a fact that the writer did not check.
9. **Informal register.** The text reads as glib or hasty where the content calls for formal, explicit prose.
10. **Throat-clearing transitions.** A filler opener signals a new topic and adds no content ("That said", "It's worth noting that", "At the end of the day"). Cut it. The sentence must stand on its own.
11. **Redundant restatement.** A clause repeats what an earlier word already says. An example is "a new dependency, which the repository did not have before". "New" already says this. State the fact once.
12. **Padded verb emphasis.** An auxiliary for emphasis adds no meaning ("does introduce" instead of "introduces", "did in fact confirm" instead of "confirmed"). Use the plain verb.
13. **Invented words.** The writer coins a word where an established word exists ("shutdownable", "de-locates", "freehand" as a verb, "side code"). Replace it with the established term ("easy to shut down cleanly", "strips source locations", "written without the template", "side-effecting code").
14. **A term from a domain where it means something else.** One example is "hygiene" for package dependencies, when it already names a macro property. Another example is the "box model" of CSS for a widget-container layout. Choose a word with no other technical meaning in the context.
15. **Passive voice that hides the actor.** "Only after the report is shown" does not say who shows it. In an instruction, name the actor: "only after you show the report."
16. **A vague or wrong referent.** The reader must guess the antecedent of a noun phrase or a pronoun. Examples are "this toolset" where nothing has that name, and "the interesting space" for an input distribution.
17. **A sentence that parses the wrong way at first.** These sentences are garden paths, or they hold a modifier in the wrong position. In "...avoid pseudo-intellectual framing rules out...", the reader first takes "framing rules" as a noun phrase. A "not X" at the end attaches to the nearest noun and not to the intended one. If a sentence needs a second read, restructure it.
18. **Stale counts and cross-references.** A stated count, a section name, or a pointer does not match its target. Examples are "one of the nine checks" above a longer list, "the table above" when the table is in a different file, and "Both scripts" for three. Check each one against its target. Prefer words that cannot drift ("the numbered checks above").
19. **Inconsistent terminology.** One concept has different names in one document or across two paired documents. Examples are "takes a predicate" and "wants a predicate", or "parse an AST" and "build an AST". Pick one term and use it throughout.
20. **Ungrammatical sentences.** Examples are a comma splice ("`#:when`/`#:unless` nest, they don't just filter"), a verb that disagrees with its compound subject, and a misplaced adverb ("returns silently empty"). Another example is a broken parallel. In "computation the user waits on and needlessly wastes", the user waits and the code wastes. Fix the grammar and keep the claim.
21. **Sentence fragments that block understanding.** The absent subject or verb of a fragment leaves the claim unclear. In "Same failure as before. Different cause.", the reader cannot tell which failure and whose cause. A short fragment is acceptable in a reference table, a heading, or an instruction where the omitted words are obvious. Flag a fragment only when the reader must guess the omitted words.
22. **A number with a unit that has the wrong scale.** This check applies to a number whose unit takes a metric prefix (s, m, g, B, Hz, and so on). Such a number has one, two, or three digits before the decimal point. The first digit is not zero. Choose the prefix that makes this true. Keep every digit of the source number. Thus "64000 ms" becomes "64.000 s", "0.5 kg" becomes "500 g", and "1500 Hz" becomes "1.500 kHz". A value of zero is "0 s". Three cases are outside this check. They are a plain count ("3 files"), a number with no unit, and a unit with no metric prefix (an hour, a degree, a percent).

## Examples from past reviews

The examples below are a fixed, curated set. No review adds to them. They supplement the checklist above. Use an example when a piece of prose resembles it. The prose does not have to fit one of the numbered checks.

The live catalogue is `BadProseExamples.org` at the root of the repository of the session. If the file is there, read it before the review. It records the prose failures that a user flagged after these examples.

Git does not track that file. Thus it is absent on a fresh checkout and in a project that does not keep one. If it is absent, review against the checklist and the examples below alone. Do not report its absence, and do not create it.

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

- **A cute personification replaces a precise claim.** "Property-test generators are too polite" and "Two checkers disagree about who owns a rule" give tools human traits. The text does not name the fact. Which generator covers too little of which input class? Which component must enforce which rule and does not? The reader can remember the metaphor, but must guess what "polite" or "disagree" means in the code.
- **Bold lead sentences read as headlines, not as topic sentences.** Each bullet opens with a bold phrase that the writer built for effect: "needs a checklist, not heroics," "is the recurring worst case," "are too polite". That is the register of a slide deck, not of formal engineering prose. The instruction to speak formally and to avoid pseudo-intellectual jargon excludes this style.
- **Unexplained short forms make the claims impossible to check.** The text cites "reader m3," "expander C1/C2," and "core C1/C3/M5" as evidence, and it does not say what the labels mean. They can be the identifiers of findings, line ranges, or test names. A reader with no access to the document that assigned those codes cannot check the claim. The writer must define an abbreviation at its first use, and this text never does.
- **The text asserts certainty with no measurement.** It states "the cheapest systematic improvement available" and "the recurring worst case" as settled fact. The quoted text shows no comparison with other possible improvements. It shows no count that says this class of bug occurs most often. A superlative needs the comparison or the count that supports it. Without one, reduce the claim to what the writer observed.
- **Abstract nouns replace the concrete mechanism.** "The totality discipline," "silent acceptance," and "stage-1 escape divergence" are nominalizations. Each one names a category of problem and not the problem itself. For example, "silent acceptance" can say plainly that the parser accepts malformed input and returns a value, not an error. The abstraction reads as more authoritative, but the reader must infer the real failure mode.

### Example 2: build-dependency disclosure

> That said, this does introduce a new build-time dependency on a Python
> 3 interpreter, which the repository did not previously have. If you
> would rather this run as a first-party C++ or shell tool to avoid that
> dependency, tell me and I will rewrite it that way.

**Noted problems with this prose:**

- **A throat-clearing opener adds no content.** "That said," signals a change of topic but states nothing. The sentence that follows stands on its own without it.
- **A padded verb inflates a plain fact.** "Does introduce" is emphasis with no meaning. "Introduces" says the same thing.
- **A clause repeats what an earlier word already said.** ", which the repository did not previously have" repeats what "new" already states about the dependency. The fact occurs twice in one sentence.

Corrected: "This introduces a new build-time dependency on a Python 3 interpreter. If you prefer a first-party C++ tool or a shell tool, tell me. I will then write it again in that form."

### Example 3: from a repository-wide audit of plugin prose

The lines below are typical of those that an audit in July 2026 flagged in the skill files and the agent files of this repository:

> - "keep them correct and shutdownable"
> - "returning raw data works but de-locates the result"
> - "surface the command verbatim in your report"
> - "This skill only curates plugins that are already installed."
> - "**Samples taken** is the trust meter."
> - "add missing repository hook wiring back into the file"
> - "convert (or deliberately leave) a loop per the table above" (in a
>   file that holds no table)

**Noted problems with this prose:**

- **Invented words replace established ones.** "Shutdownable" and "de-locates" occur only in these files. "Easy to shut down cleanly" and "strips source locations" say the same thing in words that the reader already knows.
- **A fancy or corporate verb replaces the concrete action.** "Surface the command" means "quote the command". "Curates plugins" means "enables or disables plugins". The plain verb tells the reader exactly what occurs.
- **A metaphor replaces the precise claim.** "Is the trust meter" makes the reader decode the figure of speech. "Tells you how much to trust the percentages" states the claim directly.
- **A reference assumes a fact with no evidence, or points nowhere.** "Back into the file" assumes that the wiring was there before, and that is possibly false. "The table above" points at a table that is in a different file. Check every count and every cross-reference against its target.

## Steps

1. Get the text. If the argument is a file path, read the file. If the argument is text, use it directly. In the same pass, read `BadProseExamples.org` at the root of the repository if it exists. If it does not exist, continue without it.
2. Apply the STE checks above to every sentence. Count the words in each sentence. Find each "-ing" verb, each "-ing" adjective, each helping verb, and each passive sentence. Find each "should" or "may", each word in the substitution table, and each list item with no verb. Quote each faulty sentence. Name the STE check that it fails.
3. Check the text against the house-style checklist, the examples catalogue, and the content of `BadProseExamples.org`. Find each number with a unit. Count its digits before the decimal point. Quote each faulty phrase. Name the check that it fails.
4. Revise the text to fix every confirmed problem. Keep the original meaning, facts, and numbers. This is a pass for register and precision, not a rewrite of the content. The corrected text must pass the STE checks. Read it once more. Count the words of each sentence again.
5. Apply the fix and report:
   - For a drafted chat response for the user, do not print the problem lists from steps 2 and 3. Do not print the flagged draft. The corrected text becomes the response, with no review commentary around it.
   - If the source was a file, edit the file in place. Give the problem lists from steps 2 and 3 with it. Thus the user can see each problem and its cause.
   - If the user asked for a critique of pasted text, return the corrected text with the same problem lists.
6. If nothing was wrong, say so. Do not invent a rewrite to justify the review.
