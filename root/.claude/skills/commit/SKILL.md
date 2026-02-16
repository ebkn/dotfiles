---
name: commit
description: Stage and commit changes with conventional commits
allowed-tools: Bash(git *), Read, Glob, Grep
---

## Pre-fetched context

!`git status --short`
!`git diff --stat`

## Instructions

Commit changes quickly. Do not summarize after — move on immediately.

1. Run `git diff` and `git log --oneline -5`
2. Group unrelated changes into separate commits if needed
3. For each commit: `git add <files>` → `git diff --cached --stat` → commit
4. Message: Conventional Commits (`type(scope): description`), English, imperative, under 72 chars. Match repo style if one exists. Add body only when non-obvious.
5. Ask user ONLY if: changes span many unrelated concerns with unclear grouping, possible secrets, or generated files that shouldn't be committed.
