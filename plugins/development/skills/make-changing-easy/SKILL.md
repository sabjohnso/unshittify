---
description: Before you change existing code, assess whether the change site already makes the intended change easy per the Normalized Systems Theory principles of this project. If it does not, refactor first, with the behavior kept and the tests green, to create a seam for the change. Then make the change. This is the "make changing easy, then make easy changes" rule of CLAUDE.md. Use before every change to existing code (a bug fix, a new feature, or another edit), not only when the user explicitly asks for a review. Skip it only for a new file with no existing structure, or a trivial one-line fix (a typo, a constant) with no structural risk.
argument-hint: "[description of the change about to be made]"
allowed-tools: Read, Grep, Glob, Edit, Write, Bash
---

# Make the change easy, then make the easy change

Goal: before you touch existing code, confirm that the change fits through an existing seam. If it does not, create the seam first with a refactor that keeps the behavior. Then make the requested change.

This skill grants a bare `Bash` and not argument-scoped patterns, because steps 4c and 5 run the test command of the project. That command is different in every project, and it is unknown when the skill is written.

## When this applies

It applies to each edit that touches existing code: a bug fix, a new feature, or an extension of existing behavior. Skip it for a new file or module with no existing structure to assess. Skip it for a trivial one-line fix (a typo, a literal constant) with no structural risk.

## Steps

1. Identify the change site: the function, the module, or the file that the requested change will touch. Read enough of it, and of its callers, to see its current shape.
2. Assess the change site against the Normalized Systems Theory checklist (the same one that `/development:review-nst` uses): encapsulation, separation of concerns, interfaces and not implementations, composition over inheritance, local reasoning, small focused units, declarative style, isolated side effects, the open-closed principle, and refactor-friendly tests. Judge specifically whether the requested change fits through an existing seam (an existing function boundary, interface, or extension point). Otherwise the change reaches into tangled internals, makes an oversized function larger, or duplicates logic because no shared abstraction exists.
3. If the change already fits through an existing seam, it is easy as it is. Make the change directly under TDD (see `/development:review-tdd`) and stop here. Do not refactor code that does not need it.
4. If the change is not easy, make it easy first:
   a. Confirm that tests already cover the behavior of the code that you will restructure. If no test exists, add characterization tests that record its current behavior before you touch its structure. Do not skip this step for legacy code. It is the specific exception that CLAUDE.md makes for code that was not written with these principles.
   b. Restructure only enough to create the missing seam: extract an interface, split an oversized function, isolate a side effect, or replace ad hoc conditional branches with an extension point. Do what the checklist item from step 2 named as missing. This step must not change the observable behavior.
   c. Run the tests again and confirm that they are green before each further change. If they are not green, the refactor changed the behavior. Fix that before you continue.
5. With the seam in place, make the requested change through it, under strict TDD: first a test that fails, then the minimum implementation that passes it, then a refactor with the tests green.
6. Report what you assessed, whether a refactor was necessary and what it changed, and where the requested change landed. If the change site was already easy, say so plainly. Do not manufacture a refactor to justify this step.
