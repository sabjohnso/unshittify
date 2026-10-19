---
description: Draft and apply a git commit message in the format of this repository (an emoji, a [module] summary, Problem and Solution bullets, and a closing haiku). This is the required path for every commit in this repository. Call it whenever the user asks you to commit staged or working-tree changes, also when the request is conversational (for example "commit this") and not the literal slash command. Skip it only if the user explicitly says not to use the template or asks for a freehand message.
argument-hint: "[module hint]"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Agent(communication:prose-reviewer)
---

# Write a commit message in the format of this repository

Goal: produce a commit message that follows the template below, then create the commit. Run this skill only as a direct response to an explicit request to commit. Never call it only because an unrelated task just finished. Inside that limit, treat this skill as the default. Every explicit commit request in this repository must go through it, and not through a message without the template, unless the user has explicitly said to skip the template.

## Template

```
<emoji> [<module>] <the-new-state-of-the-code>

Problem:
- <problem-item>
...

Solution:
- <solution-item>
...

<haiku>
```

- `<emoji>`. One emoji that fits the kind of the change (a bug fix, a new feature, a refactor, docs, a chore, security, performance, and so on). Do not use the same emoji for unrelated commit types only for consistency. Pick one that fits.
- `[<module>]`. The area of the codebase that the change affects most. It does not need to be a literal module or package name. A feature area, a plugin name, or a subsystem is acceptable. If `$ARGUMENTS` gives a hint, use it, unless the diff clearly shows a different module.
- `<the-new-state-of-the-code>`. A short phrase that describes what is now true, not the action that was taken (for example "Add settings-doctor subagent", not "Added settings-doctor subagent" or "Adding...").
- **Problem**. One or more bullets that name the concrete problem that the change solves. Skip this section only if there was no problem at all. That is rare. Most changes have one.
- **Solution**. One or more bullets that name what the change does to solve the problem. Keep the bullets parallel in structure to the Problem bullets where possible.
- `<haiku>`. A haiku of 5, 7, and 5 syllables that catches the spirit of the commit. It is not a restatement of the Problem and Solution bullets in verse. Aim for something evocative and not literal.

## Steps

1. Gather the context in parallel: `git status`, `git diff` (staged and unstaged), and `git log --oneline -10` for the recent style in this repository.
2. If nothing is staged, stage the specific files that the request covers. Never run `git add -A` or `git add .`. Show what you staged.
3. Draft the message with the template above.
4. Write the subject and the bullets in Simplified Technical English (ASD-STE100). The haiku is the one exception. Delegate the draft to the `communication:prose-reviewer` agent and apply the confirmed fixes before the commit. The structure of the template (the emoji, the `[module]` subject, the Problem and Solution bullets, the haiku) is required. It is not a style violation. The review covers the prose inside it: the phrase of the subject, the bullets, and the words of the haiku.
5. Create the commit with the message in a heredoc, so the multi-line format survives:
   ```
   git commit -m "$(cat <<'EOF'
   <drafted message>
   EOF
   )"
   ```
6. Do not add an attribution trailer (no `Co-Authored-By`, no tool signature), unless the user explicitly asks for one.
7. Confirm that the commit succeeded (`git status`, or the output of the commit command). Report the short hash and the subject line to the user.
