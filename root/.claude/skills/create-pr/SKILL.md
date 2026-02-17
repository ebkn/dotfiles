---
name: create-pr
description: Create a GitHub pull request with context-aware description
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git rev-parse *), Bash(git push *), Bash(gh repo view *), Bash(gh pr create *), Read, Glob, Grep, AskUserQuestion
---

## Pre-fetched context

!`git rev-parse --abbrev-ref HEAD`
!`git status --short`
!`git ls-files ':(top,icase).github/pull_request_template.md' ':(top,icase).github/pull_request_template/*.md' ':(top,icase)pull_request_template.md'`

## Instructions

Create a pull request. Follow this flow:

1. **Gather context**: Get default branch via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, then run `git log --oneline`, `git diff --stat`, and `git diff` against it.

2. **Uncommitted changes**: If `git status` above shows output, ask the user whether to commit them, ignore them, or abort. Do not proceed until answered.

3. **PR template**: Check the pre-fetched template paths above. If any template file is listed, you MUST `Read` it and use its structure as the PR body skeleton. Keep all HTML comments (`<!-- -->`) intact — only replace obvious placeholders. If no template was found, skip this step.

4. **Reference links**: Ask the user for any links to include (issues, docs, related PRs). Proactively suggest any from conversation history.

5. **Compose PR**: Based on all commits, the full diff, and conversation history:
   - Title: Conventional Commits style, under 72 chars, English
   - Body (use template if found, otherwise): Summary (what and why), Changes (grouped logically), Concerns/Notes (if any), References (if any)

6. **Confirm**: Show the full PR title and body. The user may request edits — apply and re-confirm. Do not push or create until approved.

7. **Push and create**: Push (`git push -u origin HEAD`) only if there are unpushed commits (`git log @{upstream}..HEAD`). Create with `gh pr create`. Return the PR URL.
