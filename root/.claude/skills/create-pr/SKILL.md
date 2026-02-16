---
name: create-pr
description: Create a GitHub pull request with context-aware description
allowed-tools: Bash(git *), Bash(gh *), Bash(cat *), Bash(find *), Read, Glob, Grep, AskUserQuestion
---

## Pre-fetched context

### Current branch
!`git rev-parse --abbrev-ref HEAD`

### Unstaged/untracked changes
!`git status --short`

## Instructions

You are creating a pull request. Follow these steps precisely.

### Step 0: Gather branch context

1. Get the default branch: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
2. Run these against the default branch (in parallel):
   - `git log --oneline <default-branch>..HEAD`
   - `git diff --stat <default-branch>..HEAD`
   - `git diff <default-branch>..HEAD`

### Step 1: Check for uncommitted changes

If the "Unstaged/untracked changes" section above shows any output, STOP and ask the user first:
- Show them the list of uncommitted changes
- Ask whether to:
  - **Commit them** before proceeding (stage and commit, then continue)
  - **Ignore them** and create the PR with only the already-committed changes
  - **Abort** the PR creation entirely

Do NOT proceed to the next step until the user has answered.

### Step 2: Find and read the PR template

Search for a PR template in the project:
- `.github/pull_request_template.md`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/PULL_REQUEST_TEMPLATE/*.md`
- `pull_request_template.md`

If a template exists, you MUST use its structure for the PR body. Fill in each section based on the context above. If no template exists, use the default structure in Step 4.

**Important**: Do NOT remove HTML comments (`<!-- ... -->`) from the template. Keep all comments as-is. Only replace placeholder text that is clearly meant to be filled in.

### Step 3: Ask the user about reference links

Before creating the PR, ask the user:
- Are there any reference links to include? (issue URLs, design docs, Slack threads, related PRs, etc.)
- If the conversation history contains relevant context (e.g., issue numbers, URLs, decisions), suggest them proactively.

### Step 4: Compose the PR

Analyze ALL commits on this branch (not just the latest), the full diff, and the conversation history to write:

**Title**: Concise, under 72 characters. Follow Conventional Commits if the project uses it (check commit history for patterns).

**Body** (use PR template if found, otherwise this structure):
- **Summary**: 1-3 bullet points explaining what changed and WHY
- **Changes**: Key changes grouped logically (not a file-by-file list)
- **Concerns / Notes**: Any risks, known limitations, migration steps, or areas reviewers should focus on. Omit this section if there are none.
- **References**: Links provided by the user, related issues, etc. Omit if none.

### Step 5: Review and confirm

Show the user the full PR content (title and body) and ask for confirmation before proceeding. The user may request edits — apply them and re-confirm.

Do NOT push or create the PR until the user explicitly approves.

### Step 6: Push and create

1. Check if there are unpushed commits: `git log @{upstream}..HEAD` (if no upstream exists, always push)
2. Only push (`git push -u origin HEAD`) if there are unpushed commits
3. Create the PR with `gh pr create`
4. Return the PR URL to the user
