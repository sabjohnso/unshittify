---
description: Before modifying existing code, assess whether the change site already makes the intended change easy per this project's Normalized Systems Theory principles; if it doesn't, refactor first — behavior-preserving and test-covered — to create a seam for the change, then make the change. Embodies CLAUDE.md's "make changing easy, then make easy changes." Use before every code change to existing code — a bug fix, a feature addition, or any edit — not only when explicitly asked to review; skip only for brand-new files with no existing structure, or a purely factual one-line fix (a typo, a constant) with no structural risk.
argument-hint: "[description of the change about to be made]"
allowed-tools: Read, Grep, Glob, Edit, Write, Bash
---

# Make changing easy, then make the easy change

Goal: before touching existing code, confirm the change fits through an existing seam. If it doesn't, create the seam first through a behavior-preserving refactor, then make the requested change.

## When this applies

Applies to any edit that touches existing code: a bug fix, a feature addition, an extension of existing behavior. Skip it for a brand-new file or module with no existing structure to assess, and for a purely factual one-line fix (a typo, a literal constant) that carries no structural risk.

## Steps

1. Identify the change site: the function, module, or file the requested change will touch. Read enough of it, and its callers, to see its current shape.
2. Assess the change site against the Normalized Systems Theory checklist (the same one used by `/development:review-nst`): encapsulation, separation of concerns, programming to interfaces, composition over inheritance, local reasoning, small focused units, declarative style, isolated side effects, the open-closed principle, refactor-friendly tests. Judge specifically whether the requested change fits through an existing seam — an existing function boundary, interface, or extension point — or whether it would require reaching into tangled internals, growing an already-oversized function, or duplicating logic for lack of a shared abstraction.
3. If the change already fits through an existing seam, it is easy as-is: proceed directly to making the change under TDD (see `/development:review-tdd`) and stop here — do not refactor code that doesn't need it.
4. If it is not easy, make it easy first:
   a. Confirm behavior-preserving tests already cover the code to be restructured. If none exist, add characterization tests capturing its current behavior before touching its structure — do not skip this step for legacy code; it is the specific carve-out CLAUDE.md makes for code not originally written with these principles in mind.
   b. Perform the minimal restructuring that creates the missing seam: extract an interface, split an oversized function, isolate a side effect, replace ad hoc conditional branching with an extension point — whatever the checklist item in step 2 named as missing. This step must not change observable behavior.
   c. Re-run the tests and confirm they are still green before making any further change. If they are not, the refactor was not behavior-preserving; fix that before proceeding.
5. With the seam now in place, make the originally requested change through it, following strict TDD: a failing test first, the minimum implementation to pass it, then refactor with tests green.
6. Report what was assessed, whether a refactor was needed and what it changed, and where the requested change ultimately landed. If the change site was already easy, say so plainly rather than manufacturing a refactor to justify this step.
