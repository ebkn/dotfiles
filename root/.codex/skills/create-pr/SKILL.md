---
name: create-pr
description: Create GitHub pull requests with context-aware title and body, PR template support, and approval gating. Use when the user asks to open, draft, or prepare a PR from the current branch.
---

# Create PR Workflow

Create a pull request using this flow.

1. Gather branch and diff context:
   - `git rev-parse --abbrev-ref HEAD`
   - `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
   - `git status --short`
   - `git log --oneline`
   - `git diff --stat <default-branch>...HEAD`
   - `git diff <default-branch>...HEAD`
2. Handle uncommitted changes:
   - If `git status --short` is not empty, ask whether to commit, ignore, or abort
   - Do not continue until the user answers
3. Load a PR template when available:
   - `git ls-files ':(top,icase).github/pull_request_template.md' ':(top,icase).github/pull_request_template/*.md' ':(top,icase)pull_request_template.md'`
   - Keep template heading order and HTML comments (`<!-- -->`) when filling sections
4. Ask for reference links to include (issues, docs, related PRs) and suggest obvious ones from current context.
5. Draft the PR:
   - Title: Conventional Commits format, under 72 chars
   - Decide title language before drafting and keep it fixed unless the user requests a change
   - Title language policy: use template language first whenever it can be detected
   - If the user explicitly asks to override language for the current PR, follow that override
   - If no template language is detected, use: explicit user request > latest substantive user message > English
   - Ignore slash commands (for example `/create-pr`), code blocks, file paths, and URLs when inferring language
   - If language signals conflict or are ambiguous, ask the user which language to use before drafting
   - Keep `type(scope)` tokens standard (for example `feat`, `fix`, `chore`); localize only descriptive text
   - If no template exists, use sections: Summary / Changes / Concerns / References
6. Confirm the final PR title and body with the user:
   - Apply requested edits and re-confirm
   - Do not push or create the PR before approval
7. Push and create:
   - Push with `git push -u origin HEAD` when needed
   - Create with `gh pr create`
   - Return the PR URL
