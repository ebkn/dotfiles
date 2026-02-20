---
name: commit
description: Stage and commit changes with conventional commits
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Read, Glob, Grep
---

## Pre-fetched context

!`git status --short`
!`git diff --stat`

## Instructions

Commit changes quickly. Do not summarize after — move on immediately.

1. Run `git diff` and `git log --oneline -5`
2. Group unrelated changes into separate commits if needed
3. For each commit: `git add <files>` → `git diff --cached --stat` → commit
4. Message: Conventional Commits (`type(scope): description`), English, imperative, under 72 chars. Match repo style if one exists.
   - Add a body that briefly explains **why** the change was made and any relevant background. Keep it concise — just enough for a future reader to understand the motivation without re-reading the diff.
   - Omit the body only when the subject line alone is self-explanatory (e.g., fixing a typo).
5. Ask user ONLY if: changes span many unrelated concerns with unclear grouping, possible secrets, or generated files that shouldn't be committed.
