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

3. **PR template**:
   - If a template path is listed, `Read` it before writing title/body.
   - Detect `template_language` from headings/instructions/checklists (ignore code, URLs, HTML comments).
   - Keep template headings/order and keep HTML comments (`<!-- -->`).
   - If no template exists, skip.

4. **Reference links**: Ask the user for any links to include (issues, docs, related PRs). Proactively suggest any from conversation history.

5. **Compose PR**:
   - Title: Conventional Commits, under 72 chars.
   - Decide title language before drafting and keep it fixed unless the user requests a change.
   - Title language policy: use `template_language` first whenever it can be detected.
   - If the user explicitly asks to override language for the current PR, follow that override.
   - If no `template_language` is detected, use: explicit user request > latest substantive user message > English.
   - Ignore slash commands (for example `/create-pr`), code blocks, file paths, and URLs when inferring language.
   - If language signals conflict or are ambiguous, ask the user which language to use before drafting.
   - Keep `type(scope)` tokens standard (`feat`, `fix`, etc.); localize only the description text.
   - Body: if template exists, fill its sections. If not, use Summary / Changes / Concerns / References.

6. **Confirm**: Show the full PR title and body, and include `Title language: <language>` so the user can verify it explicitly. The user may request edits — apply and re-confirm. Do not push or create until approved.

7. **Push and create**: Push (`git push -u origin HEAD`) only if there are unpushed commits (`git log @{upstream}..HEAD`). Create with `gh pr create`. Return the PR URL.
