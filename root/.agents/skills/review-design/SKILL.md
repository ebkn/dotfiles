---
name: review-design
description: Review the design of a just-finished unit of work — starting with whether comments, docs and the intended design still match the code — then report what to tidy, ranked P1/P2/P3. Use when asked to look at the design of a change — "設計をレビューして", "設計の観点でレビューして", "コメントやドキュメントとの乖離を見て", "design review", "review the design" — or via the /review-design command. Not for finding bugs (code-review), reviewing test code (review-test), or line-level cleanups (simplify).
effort: high
allowed-tools: Read, Glob, Grep, Bash(git diff *), Bash(git log *), Bash(git show *), Bash(git merge-base *), Bash(git status *), Bash(git rev-parse *)
---

Review the design of a change at an implementation breakpoint and report what to tidy, ranked P1/P2/P3.

**Match the user's language.** Answer a Japanese request in Japanese, an English one in English. Quote code, file paths, and command output verbatim.

**Boundary of this skill: reading only.** Never edit a file, never run tests, never run `gh`. Run git only to read — `git diff`, `git log`, `git show`, `git merge-base`, `git status`, `git rev-parse` — and never with `--output`, which writes to a file. Never `git add` / `commit` / `stash` / `checkout` / `switch` / `reset` / `restore` / `push`. Acting on the findings happens outside the skill (see "After the review").

**Why read-only git is in `allowed-tools`, when review-test keeps `Bash` out.** The range under review is the input of every run, so the reading commands are pre-approved by prefix. A prefix rule matches the raw command string, though: `Bash(git diff *)` also matches `git diff --output=<file>`, which is why that flag is named above.

**The boundary is this skill's own contract, not something the host enforces.** Some hosts ignore `allowed-tools` outright — Codex reads only `name` and `description` — and there the writing git commands above may already be pre-approved and run without confirmation. **The absence of a prompt is not permission.**

## Why at a breakpoint

Two prices start rising once a unit of work is done.

- **An interface is cheapest to change while its only callers are the ones just written.** Each caller, doc and test added afterwards raises the price, and once something outside the change depends on it, changing it needs someone's agreement.
- **A doc that disagrees with the code is cheapest to fix while it is still known which side is right.** At a breakpoint the code was just changed on purpose, so the doc is the side to fix. Later, deciding which of the two is wrong takes archaeology.

## After the review

This skill changes no files while it runs, per the boundary above. Once the report is out — and not before — the caller, the same agent in the same turn, takes over and carries on without stopping.

1. **Fix the P1 and P2 findings of the first report, without asking first.** The report is not the deliverable; code and docs that agree are. Reporting and stopping leaves every P1 in place, and asking permission to act on a review the caller already asked for is the failure this step exists to prevent. A doc or comment fix changes no caller, so it needs no one's agreement.
2. **Fix the doc, not the code.** Rewriting a doc's old promise — and the reason it gave — is not changing a requirement: the commit already changed it, and the doc is catching up. If the code looks like what is wrong, that is a question for "Outside this review", not a fix.
3. **Keep behavior where it is.** Run the tests before and after. A fix that would change what a test expects is not a tidying — stop and report it.
4. **Commit the fixes on their own, after the commits of the unit of work.** Never amend them into those commits or fold them in: the review is what justifies the fix, and folding it in hides that. This is the caller's step — the skill runs no git that writes.
5. **Review again, for at most three rounds, until no P1 is left.** Stop on the same terms when one finding survives two rounds, and report what is left: an LLM's findings wobble, and grinding on them is not convergence.
6. **The loop gate is P1 only.** P2 raised by a later round is reported, not chased. **Never auto-fix P3**; report it.

What is left for the user to decide is what "Outside this review" asks, and nothing else.

## Procedure

Four phases, in this order.

### Phase 1: Scope

1. **Find the range.**
   - If the caller named one, use it.
   - If this skill already reviewed part of this branch earlier in the conversation, start from the head on that report's closing line (`Reviewed: <base>..<head>`), so finished work is not reviewed twice.
   - Otherwise, from the merge-base with the default branch to `HEAD`. Find the default branch with `git rev-parse --abbrev-ref origin/HEAD`; without a remote, use `main`, then `master`.
   - Uncommitted changes (`git status --short`) belong to the work too. Include them, and say so in the report: a fix made now will share their commit.
2. **Read what the change meant to do**: the commit messages in the range (`git log`), and the plan, issue or conversation it came from.
3. **List the changed files** (`git diff --stat`). If the range changes nothing a caller or a reader depends on — formatting, a lockfile, tests alone — say so in one line and stop.

### Phase 2: Interfaces

List every interface the range creates or changes. An interface is anything another piece of code or a person depends on: exported functions and types; a command's arguments, flags, exit status and output; environment variables it reads; configuration keys; file and message formats; a new module or script that others will source or call.

For each, write one sentence from the caller's side — what it does, not how — using only its signature, its comment and its docs. **Write it before reading the implementation.** The reviewer is usually the one who wrote the code, and reading the implementation first lets intent fill in what the interface fails to say.

Then find its callers (Grep), tests included, and split them by file. A caller is **inside the range** when the range changes the file that makes the call — the file is listed in `git diff --stat` for the range; otherwise it is **outside**, even when its behavior changed through what it calls, because nothing in this change touched it. The outside ones are who a change to the interface would reach.

### Phase 3: Drift

Compare the code as it now is with everything that describes it, nearest first.

1. **Interface comments.** Every claim about accepted input, output, errors, side effects and ordering still holds.
2. **Why comments** in the functions the range changed. Each reason still applies to the code beside it.
3. **Docs that describe the changed code** — README, usage and `--help` text, the doc file beside a script, examples, the project's CLAUDE.md or AGENTS.md entries. **The range does not have to touch a doc for it to be in scope**: the commonest drift is code that moved while the README beside it did not. Check mechanically:
   - every identifier, flag, environment variable, path, default value and exit status a doc names exists in the code, with that value — Grep for each
   - every flag, output or variable the range added is documented wherever its siblings are
   - every behavior a doc describes — what happens on bad input, what is printed, what the exit status is — is what the code now does
4. **The intended design**: the plan, design doc or issue the change implements, and the commit messages in the range.

**Decide which side is right from the stated intent** (Phase 1, step 2). When the commit messages, the plan or the conversation say the behavior changed on purpose, every doc that still describes the old behavior is stale — and so is any reason it gave for the old behavior. The requirement changed in the commit; the doc has not caught up. Only when nothing states the change is the disagreement a possible bug: report it under "Outside this review", not as drift.

### Phase 4: Report

Use this format. Translate the headings into the language of the report, but keep the `Reviewed:` line that closes it exactly as shown: the next run of this skill reads it.

```
## Design review: <base>..<head> (<N> commits[, plus uncommitted changes])

### Interfaces
- `<signature>` — <one sentence from the caller's side> (new | changed; callers: <n> inside the range, <m> outside)

### P1
- **<what is wrong>** `<file:line>`: "<quoted text>"
  - Contradicts: `<file:line>` <what the code does instead>
  - Cost: <who is misled into doing what, or which change gets harder>
  - Fix: <small steps>

### P2
- ...

### P3
- ...

### Outside this review
- <a question about behavior for the user; a suspected bug, a test-quality issue or a line-level cleanup, with the skill that covers it>

Reviewed: <base>..<head>
```

Drop any section with nothing in it. If nothing is worth a finding, say so in one line under the heading and still end with the `Reviewed:` line. Write abbreviated commit hashes there and in the heading, never a branch or tag name: names move, and the next session may not have them.

**Write the report first.** Nothing is edited, run or committed until it is out — the fixes answer to it, and a report written afterwards describes a range that no longer exists. **The report does not end the turn either.** After the `Reviewed:` line, go straight on to "After the review".

## Findings

Every finding carries all four of these. A candidate missing one is not reported.

1. **What is wrong**, named: a stale comment, a stale doc, a name that no longer fits, a missing why.
2. **Evidence**: `file:line` and the quoted text — and for drift, the code it contradicts.
3. **What it costs if it stays**: who gets misled into doing what, or which change it makes harder. A candidate that can name neither is a matter of taste; drop it.
4. **The fix**, as small steps a reader could check one by one.

## How to assign priority

P1/P2/P3 are **absolute criteria**, not a distribution. Classify by whether a finding meets the criterion; do not spread findings across the three, and do not manufacture a P1 for a change that is already good.

**A finding whose fix would change what the code does is not a tidying.** Rank it nowhere in P1–P3: put it under "Outside this review" as a question for the user — an edge case nothing decides, a behavior no doc or intent explains. That keeps "fix P1 and P2 without asking" from ever reaching behavior, so every P1 and P2 can be acted on without a decision.

**P1** — fix before the next unit of work starts. Any one of:

- A comment, doc, name or usage text states something about the code that is no longer true.

**P2** — fix now; it decides how long the code stays cheap to read and change. Any one of:

- A non-obvious constraint or decision the range introduced has no comment saying why.
- An interface comment describes implementation detail its callers do not need.
- A comment only repeats what the code beside it already says.

**P3** — an improvement, the user's call.

- Wording that could be sharper; a doc that could be organized better.
