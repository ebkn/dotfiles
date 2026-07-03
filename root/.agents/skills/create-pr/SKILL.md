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

1. **Gather context**: Get the default branch locally via `git rev-parse --abbrev-ref origin/HEAD` (strip the `origin/` prefix); only if that fails (origin/HEAD unset) fall back to `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`. Then read the commits **with full messages** via `git log <base>..HEAD` (bodies included — the commit skill records the *why* there) plus `git diff --stat <base>..HEAD` for the file-level shape. Pull the full `git diff <base>..HEAD` only when the messages and stat don't sufficiently explain the changes (thin or missing commit bodies) — for large PRs this avoids reading the whole diff needlessly.

2. **Uncommitted changes**: Don't block. Create the PR from the commits that already exist and note in your reply that any uncommitted changes were left out. Only stop if there are no commits ahead of the base branch — there is then nothing to open a PR from.

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
   - If language signals conflict or are ambiguous, don't block — fall back to the priority order above (default to English when nothing is decisive).
   - Keep `type(scope)` tokens standard (`feat`, `fix`, etc.); localize only the description text.
   - Body: if template exists, fill its sections. If not, use Summary / Changes / Concerns / References.
   - Proactively include any reference links (issues, docs, related PRs) found in conversation history.
   - Do **not** append the Claude session URL (`https://claude.ai/code/…`) to the PR body.

5. **Push and create**: Do not ask the user to confirm the title/body — create directly. Push before creating:
   - Check for an upstream with `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}`.
   - If it fails (no upstream — the common new-branch case), push unconditionally with `git push -u origin HEAD`.
   - If an upstream exists, push only when `git log @{upstream}..HEAD` shows unpushed commits.

   Then create the PR, passing the body via a **quoted** heredoc into `--body-file -` (stdin) so backticks, `$`, and quotes in the body stay literal — no escaping, no temp file, and no `$()` subshell:

   ```sh
   gh pr create --title "<title>" --body-file - <<'PR_BODY_EOF'
   <body>
   PR_BODY_EOF
   ```

   Keep the title free of backticks — GitHub renders PR titles as plain text, so backticks would appear literally *and* would trigger shell command substitution inside the double quotes; escape any `$` or `"` if the title contains them. Return the PR URL.
