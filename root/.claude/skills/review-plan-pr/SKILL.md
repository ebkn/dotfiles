---
name: review-plan-pr
description: Assist the user in reviewing a GitHub pull request. Present a concise overview (purpose, key changes, points worth attention) and then answer follow-up questions to help the user understand the PR. Do NOT generate review comments or judge code quality — surface facts and let the user form the review judgment. Triggered by requests like "review this PR", "help me review PR #N", "PRをレビューしたい", or the `/review-plan-pr [PR-number|URL]` command.
allowed-tools: Bash(gh pr *), Bash(gh repo view *), Bash(git rev-parse *), Bash(git log *), Bash(git diff *), Bash(git blame *), Bash(git show *), Read, Glob, Grep, AskUserQuestion
---

Support the user in reviewing a GitHub pull request. **The goal is to help the user understand the PR**, not to take over the review judgment.

**Output language: match the language the user used in their request.** If the request is in Japanese, respond in Japanese; if English, respond in English; etc. Code snippets, file paths, and command output stay verbatim.

## Operating principles

- **The user makes the judgment — but the scope of "judgment" depends on PR type.**
  - **Code-centric PRs**: do not evaluate code quality, correctness, or style. No "this is a bug", "this should be refactored", "LGTM", or review-comment drafts. Present facts and context only.
  - **Doc/plan-centric PRs (ADR, RFC, design doc, proposal)**: code-quality evaluation is still off-limits, but **structural and decision-quality evaluation is part of the job**. Surface gaps that prevent a reader from making the decision the doc asks for:
    - Missing or vague problem statement / goals / non-goals
    - Decision not actually stated, or alternatives not compared with explicit reasons for rejection
    - Trade-offs, risks, or open questions not addressed
    - No rollback / migration plan when the change is non-trivial
    - Premises that are unstated or contradict each other / other docs / the current code
    - Claims in the doc that are not consistent with the code changes in the same PR
  - In all cases, **do not draft review comments** on the user's behalf, and do not impose subjective stylistic preferences. Frame structural gaps as observations ("the doc does not state X"), not prescriptions ("you must add X").
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
- Classify the PR before deciding the diff strategy:
  - **Doc/plan-centric**: design docs, ADRs, RFCs, proposals, spec changes. Signals: most changed files are `*.md` / `docs/` / `rfc/` / `adr/` / `proposals/`; PR title/labels include "design", "ADR", "RFC", "proposal", "plan", "spec"; little or no executable code change.
  - **Code-centric**: implementation PRs. Signals: most changed files are source code; PR makes behavioral changes.
  - **Mixed**: both doc and code change materially. Use the doc-centric order for doc files and the code-centric order for code files.
- Diff strategy:
  - Total diff ≤ 500 lines: fetch in one call with `gh pr diff <N>`.
  - Larger: fetch file-by-file **in risk order**, not change-size order. Do not let lockfiles, generated code, or boilerplate files crowd out high-signal files.
  - **Code-centric risk order (high → low):**
    1. Public API surface (exported functions/types, route handlers, RPC schemas, GraphQL schemas)
    2. Authentication / authorization / permission checks
    3. Data model and schema migrations (DB schema, ORM models, migration files)
    4. External I/O (calls to third-party APIs, network, filesystem, message queues)
    5. Configuration and environment variables (config files, env var reads, feature flags)
    6. Core business logic
    7. Tests (use to confirm intent and coverage of the above)
    8. Documentation (treat as fact-checking material against the code)
    9. Generated artifacts, lockfiles, snapshot/fixture dumps — skim only to confirm they look auto-generated; do not deep-read
  - **Doc/plan-centric risk order (high → low):**
    1. The document itself — read as primary content, not as commentary on code. Focus on:
       - Problem statement and goals / non-goals
       - Proposed approach and the decision being made
       - Alternatives considered and why they were rejected
       - Trade-offs, risks, open questions, migration / rollback plan
    2. Diagrams, schemas, API shapes embedded in the doc (these often carry the actual contract)
    3. Code or config changes in the same PR — treat as **consistency checks against the doc**. Are the claims in the doc reflected in the code? Are there contradictions?
    4. Tests — confirm whether the doc's claimed behavior is exercised
    5. Auxiliary docs (README, changelog) — consistency only
  - Heuristics for classifying a file: path patterns (`*.lock`, `*.sum`, `dist/`, `generated/`, `__snapshots__/`, `vendor/`, `*.min.js` → generated; `docs/`, `*.md`, `rfc/`, `adr/` → doc), file size vs. additions ratio, file extension.
  - When useful, `Read` the base-branch version for comparison.
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

These are off-limits for **all** PR types:

- Drafting review comments on the user's behalf (e.g., "LGTM", "you should comment X here").
- Judging **code** quality, correctness, or style ("this is well done", "this is buggy", "this is more idiomatic").
- Proposing fix code.
- Imposing subjective stylistic or architectural preferences ("you should use library X instead of Y" without a factual basis from the doc or codebase).

What is **NOT** prohibited, and is part of the support:

- For doc/plan-centric PRs, pointing out structural and decision-quality gaps as defined in *Operating principles* (missing alternatives, no rollback plan, unstated premises, doc-vs-code contradictions, etc.). Phrase these as observations of what is or isn't present in the doc, not as commands.
- For any PR, pointing out factual inconsistencies (e.g., "the PR body says X, but the diff does Y") — this is fact reporting, not quality judgment.

Only when the user explicitly asks for a comment draft or fix proposal, assist within that request. Even then, favor presenting facts and options so the user can write the comment in their own words rather than handing them a finished verdict.
