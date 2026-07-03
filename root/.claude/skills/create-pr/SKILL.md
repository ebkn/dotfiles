---
name: create-pr
description: Create a GitHub pull request with context-aware description
effort: low
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git rev-parse *), Bash(git push *), Bash(git ls-files *), Bash(gh repo view *), Bash(gh pr create *), Bash(echo *), Read, Glob, Grep, AskUserQuestion
---

## Pre-fetched context

!`git rev-parse --abbrev-ref HEAD`
!`git status --short`
!`git ls-files ':(top,icase).github/pull_request_template.md' ':(top,icase).github/pull_request_template/*.md' ':(top,icase)pull_request_template.md'`

## Instructions

Create a pull request. Follow this flow:

1. **Gather context**: Get the default branch locally via `git rev-parse --abbrev-ref origin/HEAD` (strip the `origin/` prefix); only if that fails (origin/HEAD unset) fall back to `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`. Then run `git log --oneline`, `git diff --stat`, and `git diff` against it.

2. **Uncommitted changes**: If `git status` above shows output, ask the user whether to commit them, ignore them, or abort. Do not proceed until answered.

3. **PR template**:
   - If a template path is listed, `Read` it before writing title/body.
   - Detect `template_language` from headings/instructions/checklists (ignore code, URLs, HTML comments).
   - Keep template headings/order and keep HTML comments (`<!-- -->`).
   - If no template exists, skip.

4. **Compose PR**:
   - Title: Conventional Commits.
   - Decide title language before drafting and keep it fixed unless the user requests a change.
   - Title language policy: use `template_language` first whenever it can be detected.
   - If the user explicitly asks to override language for the current PR, follow that override.
   - If no `template_language` is detected, use: explicit user request > latest substantive user message > English.
   - Ignore slash commands (for example `/create-pr`), code blocks, file paths, and URLs when inferring language.
   - If language signals conflict or are ambiguous, ask the user which language to use before drafting.
   - Keep `type(scope)` tokens standard (`feat`, `fix`, etc.); localize only the description text.
   - Body: if template exists, fill its sections. If not, use Summary / Changes / Concerns / References.
   - Proactively include any reference links (issues, docs, related PRs) found in conversation history.
   - Do **not** append the Claude session URL (`https://claude.ai/code/…`) to the PR body.

5. **Push and create**: Do not ask the user to confirm the title/body — create directly. Push before creating:
   - Check for an upstream with `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}`.
   - If it fails (no upstream — the common new-branch case), push unconditionally with `git push -u origin HEAD`.
   - If an upstream exists, push only when `git log @{upstream}..HEAD` shows unpushed commits.

   Then create with `gh pr create --title "<title>" --body "<body>"`. Return the PR URL.
