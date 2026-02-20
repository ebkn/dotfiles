---
name: update-pr
description: Update an existing GitHub pull request for the current branch after new commits by revising title/body, preserving template structure, and pushing pending commits. Use when the user asks to refresh, edit, or update an already-open PR.
---

# Update PR Workflow

Update an existing pull request using this flow.

1. Gather branch and PR context:
   - `git rev-parse --abbrev-ref HEAD`
   - `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
   - `git status --short`
   - `gh pr view --json number,url,title,body,baseRefName,headRefName,isDraft`
   - `git log --oneline <base-branch>...HEAD`
   - `git diff --stat <base-branch>...HEAD`
   - `git diff <base-branch>...HEAD`
2. Handle missing PR:
   - If `gh pr view` fails, explain no open PR exists for this branch
   - Ask whether to switch to `$create-pr` or abort
3. Handle uncommitted changes:
   - If `git status --short` is not empty, ask whether to commit, ignore, or abort
   - Do not continue until the user answers
4. Load a PR template when available:
   - `git ls-files ':(top,icase).github/pull_request_template.md' ':(top,icase).github/pull_request_template/*.md' ':(top,icase)pull_request_template.md'`
   - Keep template heading order and HTML comments (`<!-- -->`) when filling sections
5. Ask for updates to include:
   - Confirm whether the title should change or stay as-is
   - Ask for links to include (issues, docs, related PRs)
   - Ask what changed since the last PR draft/review and highlight reviewer-facing impact
6. Draft updated PR title and body:
   - Title: Conventional Commits format, under 72 chars
   - Decide title language before drafting and keep it fixed unless the user requests a change
   - Title language policy: use template language first whenever it can be detected
   - If the user explicitly asks to override language for the current PR, follow that override
   - If no template language is detected, use: explicit user request > latest substantive user message > English
   - Ignore slash commands (for example `/update-pr`), code blocks, file paths, and URLs when inferring language
   - If language signals conflict or are ambiguous, ask the user which language to use before drafting
   - Keep `type(scope)` tokens standard (for example `feat`, `fix`, `chore`); localize only descriptive text
   - If no template exists, use sections: Summary / Changes / Concerns / References
7. Confirm the final title and body with the user:
   - Apply requested edits and re-confirm
   - Do not push or edit the PR before approval
8. Push and update:
   - Push with `git push -u origin HEAD` when needed
   - Update with `gh pr edit <number> --title "<title>" --body-file <file>`
   - Return the PR URL
