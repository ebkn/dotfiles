---
name: review-pr
description: Assist the user in reviewing a GitHub pull request. Present a concise overview (purpose, key changes, points worth attention) and then answer follow-up questions to help the user understand the PR. Do NOT generate review comments or judge code quality — surface facts and let the user form the review judgment. Triggered by requests like "review this PR", "help me review PR #N", "PRをレビューしたい", or the `/review-pr [PR-number|URL]` command.
allowed-tools: Bash(gh pr *), Bash(gh repo view *), Bash(git rev-parse *), Bash(git log *), Bash(git diff *), Bash(git blame *), Bash(git show *), Read, Glob, Grep, AskUserQuestion
---

Support the user in reviewing a GitHub pull request. **The goal is to help the user understand the PR**, not to take over the review judgment.

**Output language: match the language the user used in their request.** If the request is in Japanese, respond in Japanese; if English, respond in English; etc. Code snippets, file paths, and command output stay verbatim.

## Operating principles

- **The user makes the judgment.** Do not output evaluations like "this is a problem", "this should be fixed", "LGTM", or draft review comments. Limit yourself to presenting facts and context.
- **Prefer brevity.** Keep summaries short. Optimize for the user reaching the information they need quickly, not for completeness.
- **Separate facts from inference.** Distinguish what is stated in the PR body / code / commits from what you are inferring. When uncertain, say "unclear" rather than guessing.
- **Go deeper through dialogue.** Keep the initial overview compact. Expand into details only in response to the user's questions; do not front-load information.

## Procedure

### Phase 1: Identify the PR

- If a PR number or URL is given as an argument, use it.
- Otherwise, run `gh pr status --json number,title,headRefName,url` to find the PR for the current branch.
- If neither resolves a PR, ask the user for the number or URL.

### Phase 2: Fetch PR information

Collect:

- `gh pr view <N> --json number,title,body,author,baseRefName,headRefName,additions,deletions,changedFiles,labels,state,url`
- `gh pr view <N> --json files` for the file list with per-file additions/deletions.
- Diff strategy:
  - Total diff ≤ 500 lines: fetch in one call with `gh pr diff <N>`.
  - Larger: fetch file-by-file in order of change size (`gh pr diff <N> -- <path>`). When useful, `Read` the base-branch version of the file for comparison.
- Pull related commits via `gh pr view <N> --json commits` or `git log` when needed.

Note any links in the PR body (issues, docs, related PRs) for inclusion in the overview.

### Phase 3: Present the overview

Keep it **short**. Each section is bullets of essentials — do not expand into prose.

```
## PR #<N>: <title>

- Author: <author>
- Branch: <head> → <base>
- Size: +<additions> / -<deletions>, <changedFiles> files
- Labels: <labels> (if any)
- State: <state>
- Link: <url>

### Why (purpose / background)
- 2–3 lines distilled from the PR body. Extract the point even if the body is long.
- Include related issue / doc links if present.
- If the body does not state the purpose, write "not stated in PR body" — do not guess.

### What (key changes)
- 3–5 bullets at the level of **logical change units**, not per-file listings.
- Examples: "Adds <function> to <module>", "Changes return type of <API>", "Adds new config <X>".
- 1–2 lines per bullet. Split if longer.

### Points worth attention
- 2–4 objective facts that naturally draw a reviewer's attention.
- Do NOT write "good / bad" or "should be fixed". Present facts only.
- Examples:
  - "Signature of public API <X> changed (backwards-compatibility consideration)"
  - "New call to external service <Y>"
  - "Tests added / not added: <details>"
  - "Config or environment variables added/changed: <details>"
  - "Includes schema migration"
```

### Phase 4: Interactive follow-up

End the overview with a prompt to direct the next step:

```
Let me know what you'd like to dig into. Examples:
- See a specific file or function in detail
- Explore the background — why this change is needed
- Check where this PR affects the existing codebase
- Look at related tests or documentation
```

When the user follows up:

- **Code walkthrough**: `Read` the relevant code and explain accurately what it does. If the intent is unclear, say "unclear".
- **Background**: gather facts from PR body, commit messages, linked issues, `git blame`, surrounding code.
- **Impact**: use `rg` to find callers and references; check related tests / docs.
- **Comparison with existing code**: `Read` the base-branch version and explain the meaning of the diff.

What you provide is **decision material for the user**, not a conclusion.

## Prohibited actions (unless explicitly requested)

- Drafting review comments (e.g., "LGTM", "you should comment X here").
- Judging code quality ("this is well done", "this is problematic").
- Proposing fix code.
- Evaluative language like "correct / wrong", "should / should not".

Only when the user explicitly asks for a comment draft or fix proposal, assist within that request. Even then, favor presenting facts and options so the user can write the comment in their own words rather than handing them a finished verdict.
