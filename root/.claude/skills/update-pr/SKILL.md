---
name: update-pr
description: Update an existing GitHub pull request after adding commits by revising title/body, preserving template format, and pushing pending branch changes.
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git rev-parse *), Bash(git push *), Bash(git ls-files *), Bash(gh repo view *), Bash(gh pr view *), Bash(gh pr edit *), Read, Glob, Grep, AskUserQuestion
---

## Pre-fetched context

!`git rev-parse --abbrev-ref HEAD`
!`git status --short`
!`git ls-files ':(top,icase).github/pull_request_template.md' ':(top,icase).github/pull_request_template/*.md' ':(top,icase)pull_request_template.md'`

## Instructions

Update the existing pull request for the current branch. Follow this flow:

1. **Gather context**: Get default branch via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, then run `git log --oneline`, `git diff --stat`, and `git diff` against it.

2. **Missing PR check**: Run `gh pr view --json number,url,title,body,baseRefName,headRefName,isDraft`. If it fails, tell the user there is no open PR for this branch. Ask whether to switch to `/create-pr` or abort.

3. **Uncommitted changes**: If `git status` above shows output, ask whether to commit them, ignore them, or abort. Do not proceed until answered.

4. **PR template**:
   - If a template path is listed, `Read` it before writing title/body.
   - Detect `template_language` from headings/instructions/checklists (ignore code, URLs, HTML comments).
   - Keep template headings/order and keep HTML comments (`<!-- -->`).
   - If no template exists, skip.

5. **Collect updates**: Ask what changed since the previous PR revision and which links should be included (issues, docs, related PRs). Confirm whether the title should change.

6. **Compose updated PR content**:
   - Title: Conventional Commits, under 72 chars.
   - Decide title language before drafting and keep it fixed unless the user requests a change.
   - Title language policy: use `template_language` first whenever it can be detected.
   - If the user explicitly asks to override language for the current PR, follow that override.
   - If no `template_language` is detected, use: explicit user request > latest substantive user message > English.
   - Ignore slash commands (for example `/update-pr`), code blocks, file paths, and URLs when inferring language.
   - If language signals conflict or are ambiguous, ask the user which language to use before drafting.
   - Keep `type(scope)` tokens standard (`feat`, `fix`, etc.); localize only the description text.
   - Body: if template exists, fill its sections. If not, use Summary / Changes / Concerns / References.

7. **Confirm**: Show the full updated PR title/body. The user may request edits - apply and re-confirm. Do not push or edit until approved.

8. **Push and update**:
   - Push (`git push -u origin HEAD`) only if there are unpushed commits (`git log @{upstream}..HEAD`).
   - Update with `gh pr edit --title "<title>" --body-file <file>`.
   - Return the PR URL.
