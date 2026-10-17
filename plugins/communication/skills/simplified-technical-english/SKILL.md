---
description: Reference for writing prose in Simplified Technical English (ASD-STE100) — the condensed writing rules (approved words, technical names and technical verbs, noun clusters, verb forms, sentence and paragraph limits, procedures, descriptive text, warnings, punctuation) and a table of substitutions for software writing. Use when writing or checking any prose — a response to the user, a code comment, a commit message, a planning document, or documentation — and when the user asks what STE permits.
argument-hint: "[file path or pasted prose]"
allowed-tools: Read, Grep, Glob
---

# Write in Simplified Technical English

Goal: write prose that obeys the rules of Simplified Technical English (STE), the controlled language in the specification ASD-STE100, and check prose against those rules.

The AeroSpace and Defence Industries Association of Europe (ASD) publishes the specification and holds the copyright. This skill does not copy the specification or its dictionary. It states the rules in condensed form, in the words of this repository, and it gives the substitutions that software writing needs most often.

## Where STE applies

- Responses to the user, code comments, commit messages, planning documents, and documentation.
- Not code identifiers, not quoted text, and not the haiku at the end of a commit message. The commit template keeps the haiku as a stated exception.

## Words

- Use a word only in its approved meaning and its approved part of speech. One word has one meaning. One meaning has one word.
- Use the approved spelling. Do not use slang, idiom, or jargon.
- Use technical names for things: a part, a tool, a file, a type, a command, a language keyword. Write a software name as a code span, for example `transcript.sh` or `READ_ONLY_AGENTS`. A technical name is a noun or an adjective. It is not a verb.
- Use a technical verb for a technical process when no approved word says the same thing: compile, commit, push, merge, parse, lint, and the like. Use it in an approved verb form.
- Spell out an abbreviation at its first use. Then use the abbreviation.
- Use one name for one thing in the whole document.

## Noun clusters

- Do not put more than three nouns in a row. Rewrite a longer cluster with "of", "for", or a hyphen: "the file for the hook test" instead of "the hook test fixture file".
- Put an article (the, a, an) or a demonstrative (this, these) before a noun.

## Verbs

- Use only these verb forms: the infinitive, the imperative, the simple present, the simple past, the past participle as an adjective, and the future with "will".
- Do not use the "-ing" form as a verb. "The hook blocks the turn", not "the hook is blocking the turn". An "-ing" word is permitted only inside a technical name, for example "the wiring".
- Do not build a tense from a helping verb: not "has blocked", not "had been blocked".
- Use the active voice. In a procedure, the active voice is mandatory. In descriptive text, use the passive voice only when the agent is unknown or unimportant.
- Use "must" for a requirement. Use "can" for ability or possibility. Do not use "should", "may", or "might".

## Sentences

- Put one topic in one sentence.
- Keep a sentence in a procedure to 20 words. Keep a sentence in descriptive text to 25 words.
- Do not remove a verb or an article to make a sentence shorter.
- Put the condition before the instruction: "If the test fails, stop."
- Use a vertical list for a sequence or a set of more than two items.
- Do not use a semicolon. Write two sentences.

## Procedures

- Write an instruction in the imperative: "Run the validator."
- Write one instruction in one sentence. Two actions can share a sentence only when they occur at the same time.
- Write the steps in the order of execution.
- Give the location before the action when the location matters: "In `CLAUDE.md`, add the rule."

## Descriptive text

- Put the key sentence first in a paragraph.
- Keep a paragraph to one topic and to six sentences.
- Do not use a one-sentence paragraph more than once in ten paragraphs.

## Warnings and cautions

- A warning tells the reader about a risk of injury. A caution tells the reader about a risk of damage, for example loss of data.
- Put the warning or the caution before the instruction it applies to. Start with a short command, then give the reason.
- Do not put a procedure step inside a warning or a caution.

## Punctuation

- Use a colon to introduce a list.
- Use a hyphen to join the words of a noun cluster that the reader can parse the wrong way.
- Use parentheses only for a reference or a short clarification. Do not put a full sentence in them.
- Do not use a dash to join two thoughts. Write two sentences.
- Use a comma to separate the condition from the instruction.

## Substitutions for software writing

| Do not write        | Write                       |
|---------------------|-----------------------------|
| ensure, verify      | make sure                   |
| utilize, leverage   | use                         |
| perform             | do                          |
| obtain              | get                         |
| initiate, commence  | start                       |
| terminate           | stop                        |
| modify              | change                      |
| indicate            | show                        |
| attempt             | try                         |
| assist              | help                        |
| prior to            | before                      |
| in order to         | to                          |
| should              | must                        |
| may, might          | can, or "it is possible"    |
| is required         | is necessary, or "must"     |
| approximately       | approximately (approved)    |

## Steps to check a piece of prose

1. Read the whole text once.
2. Count the words in each sentence. Mark a sentence over the limit for its type.
3. Find each "-ing" verb, each helping verb, and each passive sentence. Rewrite it.
4. Find each word in the left column of the table above. Replace it.
5. Find each noun cluster of four or more nouns. Rewrite it.
6. Find each abbreviation. Make sure the first use spells it out.
7. Return the corrected text. Do not return the list of problems unless the user asks for it.
