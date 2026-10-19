---
description: Explore the git history of this repository. Find when or why a line or a file changed, find who changed it, search the commit messages or the code changes across the history, or inspect a past commit. Use when the user asks about the git history, blame, the log, "when did X change", "who wrote this", or "find the commit that...".
argument-hint: "[question, path, or search term]"
allowed-tools: Bash(git log:*), Bash(git show:*), Bash(git blame:*), Bash(git diff:*), Bash(git reflog:*), Bash(git branch:*), Bash(git tag:*), Bash(git shortlog:*), Bash(git rev-list:*)
---

# Explore the git history

Goal: answer a question about the past of the repository with the narrowest git query that answers it. Do not dump the whole log. This skill is read-only. It never commits, checks out, resets, or rewrites the history.

## Map the question to a query

- **"When did this line or file change, and who changed it?"** Use `git blame -L <start>,<end> -- <path>` for specific lines. Use `git log --follow -p -- <path>` to walk every revision of a file. `--follow` tracks the file across renames.
- **"Find the commit that added or removed a specific string or code pattern."** Use `git log -S'<exact string>' --oneline -- <path>` (the pickaxe, which matches the commits that changed the *count* of that string), or `git log -G'<regex>' --oneline -- <path>` (which matches the commits whose diff matches the regex at any position).
- **"Search the commit messages."** Use `git log --grep='<pattern>' -i --oneline`. Add `--all` to search every branch, not only the current one.
- **"What did the commits by X look like, or the commits in a date range?"** Use `git log --author='<name>' --since='<date>' --until='<date>' --oneline`.
- **"Show me exactly what a commit did."** Use `git show <hash>`. Add `-- <path>` to limit the output to one file.
- **"Did this ever exist on a different branch, or was it lost?"** Use `git log --all --oneline -- <path>`. For local work that was lost a short time ago, run `git reflog` first, then `git show <hash>` on each hash that it shows.
- **"Who has worked on this area the most?"** Use `git shortlog -sn -- <path>`.
- **A visual overview of the branches and merges.** Use `git log --oneline --graph --decorate --all`.

## Steps

1. If the request is ambiguous (a vague area of code, no path, no time frame), ask one question to clarify it. Do not guess. A wrong scope wastes a full walk of the history.
2. Run the narrowest query from the map above. Prefer `--oneline` first to see the candidate commits. Then read a specific commit with `git show` or `-p`, only when you know which commit matters.
3. Report the findings as the short commit hash, the author, the date, the one-line subject, and the specific lines or hunks that answer the question. Do not report the full diff, unless the user asked to see everything.
4. If several commits can be "the" answer, list them with the most recent first, and let the user pick. Do not commit to one guess.
