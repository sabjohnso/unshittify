---
description: Draft and apply a git commit message in this repo's format — emoji, [module] summary, Problem/Solution bullets, and a closing haiku. This is the required path for every commit in this repository — invoke it whenever the user asks to commit staged or working-tree changes, even when the request is phrased conversationally (e.g. "commit this") rather than as the literal slash command. Skip it only if the user explicitly says not to use the template or asks for a freehand message.
argument-hint: "[module hint]"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*)
---

# Write a commit message in this repo's format

Goal: produce a commit message that follows the template below, then create the commit. Only run this skill in direct response to an explicit request to commit — never chain into it off the back of finishing an unrelated task. Within that constraint, treat this skill as the default: any explicit commit request in this repository should go through it rather than being freehanded, unless the user has explicitly said to skip the template.

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

- `<emoji>` — one emoji that fits the nature of the change (bug fix, new feature, refactor, docs, chore, security, performance, etc.). Don't reuse the same emoji for unrelated commit types just for consistency; pick one that actually fits.
- `[<module>]` — the area of the codebase most affected. This does not need to be a literal module/package name — a feature area, plugin name, or subsystem is fine. If `$ARGUMENTS` supplies a hint, use it unless the diff clearly indicates a different module.
- `<the-new-state-of-the-code>` — a short phrase describing what is now true, not what action was taken (e.g. "Add settings-doctor subagent", not "Added settings-doctor subagent" or "Adding...").
- **Problem** — one or more bullets naming the concrete problem the change addresses. Skip this section only if there truly was no problem being solved (rare — most changes have one).
- **Solution** — one or more bullets naming what the change actually does to address the problem. Keep bullets parallel in structure with the Problem bullets where possible.
- `<haiku>` — a 5-7-5 syllable haiku that captures the spirit of the commit. Not a restatement of the Problem/Solution bullets in verse — aim for something evocative rather than literal.

## Steps

1. Gather context in parallel: `git status`, `git diff` (staged and unstaged), and `git log --oneline -10` for recent style precedent in this repo.
2. If nothing is staged, stage the specific files relevant to the request — never `git add -A` or `git add .` — and show what was staged.
3. Draft the message following the template above.
4. Create the commit with the message passed via a heredoc, so multi-line formatting survives:
   ```
   git commit -m "$(cat <<'EOF'
   <drafted message>
   EOF
   )"
   ```
5. Do not add any attribution trailer (no `Co-Authored-By`, no tool signature) unless the user explicitly asks for one.
6. Confirm the commit succeeded (`git status` or the commit command's own output) and report the short hash and subject line back to the user.
