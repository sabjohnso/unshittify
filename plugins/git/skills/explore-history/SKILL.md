---
description: Explore this repository's git history — find when or why a line/file changed, who changed it, search commit messages or code changes across history, or inspect a past commit. Use when the user asks about git history, blame, log, "when did X change," "who wrote this," or "find the commit that...".
argument-hint: "[question, path, or search term]"
disable-model-invocation: true
allowed-tools: Bash(git log:*), Bash(git show:*), Bash(git blame:*), Bash(git diff:*), Bash(git reflog:*), Bash(git branch:*), Bash(git tag:*), Bash(git shortlog:*), Bash(git rev-list:*)
---

# Explore git history

Goal: answer a question about the repository's past by picking the narrowest git query that answers it, not by dumping the whole log. This skill is read-only — it never commits, checks out, resets, or rewrites history.

## Map the question to a query

- **"When did this line/file change, and who changed it?"** → `git blame -L <start>,<end> -- <path>` for specific lines, or `git log --follow -p -- <path>` to walk every revision of a file (`--follow` keeps tracking it across renames).
- **"Find the commit that added/removed a specific string or code pattern"** → `git log -S'<exact string>' --oneline -- <path>` (pickaxe: matches commits that changed the *count* of that string) or `git log -G'<regex>' --oneline -- <path>` (matches commits whose diff matches the regex anywhere).
- **"Search commit messages"** → `git log --grep='<pattern>' -i --oneline` (add `--all` to search every branch, not just the current one).
- **"What did commits by X look like, or in a date range?"** → `git log --author='<name>' --since='<date>' --until='<date>' --oneline`.
- **"Show me exactly what a commit did"** → `git show <hash>` (add `-- <path>` to scope to one file).
- **"Has this ever existed on another branch, or was it lost?"** → `git log --all --oneline -- <path>`; for recently lost local work, `git reflog` first, then `git show <hash>` on whatever it turns up.
- **"Who has worked on this area the most?"** → `git shortlog -sn -- <path>`.
- **Visual overview of branching/merges** → `git log --oneline --graph --decorate --all`.

## Steps

1. If the request is ambiguous (a vague area of code, no path, no time frame), ask one clarifying question rather than guessing — a wrong scope wastes a full history walk.
2. Run the narrowest query from the map above. Prefer `--oneline` first to see candidate commits, then drill into a specific one with `git show` or `-p` only once you know which commit matters.
3. Report findings as: commit hash (short), author, date, one-line subject, and the specific lines/hunks relevant to the question — not the full diff, unless the user asked to see everything.
4. If several commits could be "the" answer, list them ordered most-recent-first and let the user pick, rather than committing to one guess.
