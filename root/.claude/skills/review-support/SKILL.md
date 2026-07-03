---
name: review-support
description: Help the user review a GitHub pull request and compose the review comments they will send themselves. Act as a facilitator — give a compact overview, draw out the user's concerns through dialogue, verify them against the real code, and shape them into sendable, severity-labeled inline comments plus a summary memo. Do NOT originate code-quality verdicts on your own; the review judgment stays with the user. Triggered by requests like "PRをレビューしたい", "レビューを書きたい", "レビューコメントをまとめたい", "help me review this PR", "help me write review comments", or the `/review-support` command.
effort: max
allowed-tools: Bash(gh pr view *), Bash(gh pr diff *), Bash(gh pr status *), Bash(gh repo view *), Bash(git rev-parse *), Bash(git log *), Bash(git diff *), Bash(git blame *), Bash(git show *), Read, Glob, Grep, AskUserQuestion
---

Help the user **compose the review comments they want to send** on a GitHub pull request. **The user sends the review themselves — this skill never posts it.**

**Output language: match the language the user used in their request.** Japanese request → respond in Japanese. Code snippets, file paths, and command output stay verbatim.

## What this skill is for

This is the single PR-review support skill. It covers **both** understanding the PR (a compact overview + follow-up walkthrough) and, on top of that, **helping the user write the review comments they will send**. The deliverable is drafted, severity-labeled comments — but the user always submits them.

If the user clearly only wants to *understand* the PR (no intent to comment), stay in Phases 1–3 and do not push toward drafting comments.

## Operating principles

- **Facilitator, not author of verdicts.** The concerns originate from the **user**, not from your own quality judgment.
  - Do **not** spontaneously assert "this is a bug", "this should be refactored", "this is bad style", or hand over a finished LGTM/verdict.
  - Instead, surface facts that naturally draw attention and **turn them into questions for the user** ("this changes the public API signature — do you want to comment on backward compatibility?"). Let the user decide whether it becomes a review comment.
  - Your value-add is **articulation, verification, severity classification, and formatting** of the concerns the user expresses — not inventing the concerns.
  - Exception: **factual inconsistencies** (e.g., "the PR body says X but the diff does Y", "this test asserts the opposite of the doc") may be raised directly. That is fact-reporting, not a quality verdict.
- **Verify before wording.** Before turning a user's concern into a comment, check it against the real code (callers, tests, base-branch version). Label each item's status: `仮説 / 確認済み / 棄却`. Never draft a comment on an unverified hypothesis without saying so.
- **Separate facts from inference.** Distinguish what the PR/code/commits state from what you infer. When uncertain, say "unclear" rather than guessing.
- **Go deeper through dialogue.** Keep the initial overview compact. Expand only in response to the user; do not front-load.
- **Assume project familiarity.** The user develops this project and holds baseline knowledge of its domain, conventions, and stack. Do **not** explain well-known framework/stdlib behavior, restate obvious code, or re-teach project conventions they already know. Spend words only on what is **specific and non-obvious about this change** — the intent, the approach chosen, and where it touches things.
- **Orient before detail.** The first output is a **reading guide**, not a full explanation: what the PR is trying to do and why, the concrete approach, and — most importantly — *what to read first and in what order* so the user can dive into the code efficiently.
- **Visualize when it compresses.** Use a **small, simple** table when it conveys structure faster than prose (reading-order, changed-areas-by-concern, related links). Cap tables at a handful of rows and 3–4 columns; if a table would sprawl, use bullets instead. Never table-ize prose that reads fine as a sentence.
- **Prefer brevity.** Comments the user sends should be short and specific. Favor giving the user facts and options so they can phrase the comment in their own words over handing them a finished paragraph.

## Procedure

### Phase 1: Identify the PR

- Default: the user has already checked out the branch for the PR they want to review. Run `gh pr status --json number,title,headRefName,url` and use the PR for the current branch.
- Only if that resolves no PR (detached branch, wrong workspace), ask the user for the number or URL.

### Phase 2: Fetch PR information

Collect:

- `gh pr view <N> --json number,title,body,author,baseRefName,headRefName,additions,deletions,changedFiles,labels,state,url`
- `gh pr view <N> --json files` for the per-file additions/deletions.
- Diff strategy (read in **risk order**, not change-size order — do not let lockfiles or generated code crowd out high-signal files):
  - Total diff ≤ 500 lines: `gh pr diff <N>` in one call.
  - Larger: fetch file-by-file in risk order (high → low):
    1. Public API surface (exported functions/types, route handlers, RPC/GraphQL schemas)
    2. Authentication / authorization / permission checks
    3. Data model and schema migrations
    4. External I/O (third-party APIs, network, filesystem, queues)
    5. Configuration and environment variables, feature flags
    6. Core business logic
    7. Tests (confirm intent and coverage of the above)
    8. Documentation (fact-check against the code)
    9. Generated artifacts, lockfiles, snapshots — skim only; do not deep-read.
  - Path heuristics: `*.lock` / `*.sum` / `dist/` / `generated/` / `__snapshots__/` / `vendor/` / `*.min.js` → generated; `docs/` / `*.md` → doc.
  - When useful, `Read` the base-branch version for comparison.
- **Gather related context to link in the overview** (the user wants filenames/links to prior art, not just the raw diff):
  - Links in the PR body — issues, related PRs, external docs. Extract them verbatim.
  - Prior PRs on the same code: `git log --oneline -15 -- <changed-path>` to see recent history; map notable commits to their PR with `gh pr list --search "<sha or keyword>" --state all --json number,title,url`. Surface the 1–3 most relevant.
  - In-repo docs describing the touched area: `Glob` for `docs/**`, `README*`, `**/*.md` near the changed files, and `rg` for the changed module/symbol names inside `docs/`. List the ones a reviewer should read.
  - Keep every reference as `名前 + パス or URL` so the user can click through. Do not invent links — only cite what actually exists.

### Phase 3: Present a reading guide

The goal of this output is to get the user reading the right code fast — **not** to explain the PR in full. Assume they know the project. Keep it short; use the small tables below. Drop any section that has nothing meaningful to say (e.g., no related prior art → omit that table).

```
## PR #<N>: <title>  (+<additions>/-<deletions>, <changedFiles> files ・ <state> ・ <url>)

### 何を・何のために (intent)
- 1–2 lines: the problem being solved and the goal. From the PR body; if absent, write "PR本文に記載なし" — do not guess.

### 実装アプローチ (how)
- 2–3 bullets: the concrete approach taken (the mechanism, not a file listing). Focus on the non-obvious design choices, since the user knows the basics.

### まず読むべき順 (reading order)
| # | ファイル | 役割 | 見どころ |
|---|---|---|---|
| 1 | `path/to/entry.ext` | この変更の起点/公開面 | <1行: なぜ最初に読むか> |
| 2 | `path/to/core.ext` | 中核ロジック | <1行> |
| 3 | `path/to/foo_test.ext` | 振る舞いの仕様 | <1行> |
（High-signal files のみ、risk order。生成物・lockfile は載せない。3–6行に収める）

### 関連リンク (prior art) — あれば
| 種別 | 参照 | リンク/パス |
|---|---|---|
| PR | #<n> <一言> | <url> |
| issue | #<n> <一言> | <url> |
| doc | <title> | `docs/....md` |
（PR本文のリンク・関連PR・関連docのうち、レビューに効くものだけ。無ければ節ごと省略）

### 注意を引く点（質問候補）
- 2–4 objective facts stated as questions to the user, e.g.:
  - "公開API <X> のシグネチャが変わっています。後方互換についてコメントしますか？"
  - "外部サービス <Y> への新規呼び出しがあります。エラーハンドリングを確認しますか？"
  - "この変更にテストが見当たりません。テスト追加を求めますか？"
```

### Phase 4: Elicit review points (divergent)

Draw out what the **user** wants to raise. Drive it with `AskUserQuestion` or open prompts. Classify each emerging point into one of three streams:

- **疑問 (question)** — the user finds the intent unclear and wants to ask the author.
- **懸念 (concern)** — the user suspects a problem (bug, design, maintainability). Mark `仮説` until verified.
- **確認 (fact-check)** — test coverage, backward compatibility, migration, doc-vs-code consistency.

Do not add concerns the user did not raise. You *may* keep offering attention-drawing facts as questions (Phase 3 style) to prompt them, but the user decides what becomes a comment.

### Phase 5: Verify against real code (as needed)

For each `懸念(仮説)`, do the legwork before it becomes a comment:

- `rg` for callers and references to gauge blast radius.
- `Read` the related tests — is the behavior exercised?
- `Read` the base-branch version and explain what the diff actually changes.
- Update the label: `仮説 → 確認済み` (concern stands) or `棄却` (turned out fine — tell the user why, so they can drop it).

### Phase 6: Converge — assemble sendable comments

Produce **both** outputs. The user copy-pastes them into GitHub and sends manually.

**(A) Inline comments** — one block per location:

```
### 送信用コメント

1. `path/to/file.ext:120`  [issue]
   <comment body, 1–3 lines, in the user's voice — specific and short>

2. `path/to/other.ext:45`  [question]
   <comment body>

3. `path/to/file.ext:200`  [nitpick / non-blocking]
   <comment body>
```

**(B) Summary memo** — for the overall PR comment / review submission note:

```
### 全体所感（PR全体コメント用）
- <overall framing in 2–4 bullets: approve intent / blocking items / open questions>
```

Rules for this phase:

- Attach a **severity label** to every inline comment (see below).
- Keep each comment copy-paste ready and phrased as the user would send it — but keep it lean so the user can adjust wording.
- List `棄却` items separately as "確認して問題なかった点" so the user knows what was checked and dropped.
- **Do not send.** Never run `gh pr comment`, `gh pr review`, or any posting command. If the user asks you to send, remind them this skill hands off at draft; they submit it themselves.

## Severity labels (based on Conventional Comments)

Classify each comment so the user can decide what to send and how firmly. Reflect the **user's** intent, not your own verdict.

| Label | Meaning | Blocks merge? |
|---|---|---|
| `issue` | A problem the user believes should be addressed | usually yes |
| `question` | The user wants to understand the author's intent | no (but may gate approval) |
| `suggestion` | A concrete alternative the user proposes | optional |
| `nitpick` | Minor / stylistic; explicitly non-blocking | no |
| `praise` | Something the user wants to positively call out | no |

Add `(blocking)` / `(non-blocking)` when the user wants to make the merge impact explicit.

## Prohibited (unless the user explicitly requests otherwise)

- **Posting the review** (`gh pr comment` / `gh pr review` / any send). The user always submits.
- **Originating code-quality verdicts** the user did not raise ("this is buggy", "this is well done", "refactor this"). Surface facts as questions instead.
- Proposing fix code unprompted.
- Imposing subjective stylistic or architectural preferences without a factual basis from the code.

Factual inconsistencies (PR-body-vs-diff, doc-vs-code, test-asserts-opposite) are **not** prohibited — reporting them is fact-checking, and they make good review material.
