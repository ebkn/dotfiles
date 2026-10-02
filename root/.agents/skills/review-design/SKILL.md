---
name: review-design
description: Run this before reporting a finished unit of work back to the user, without being asked, whenever that unit — committed, tests passing — added or changed an interface: an exported function or type, a command's arguments, flags or output, an environment variable, a configuration key, a file format, a new module or script. It reviews the design of the change — whether comments, docs and the intended design still match the code, and whether its interfaces are deep (simple to use, hiding real work) and testable — reports what to tidy, ranked P1/P2/P3, and the fixes follow. Also run it before create-pr while part of the branch is unreviewed. Not after every commit, and not for a change to tests, docs or configuration alone, or a small fix that changes no interface. On request too — "設計をレビューして", "設計の観点でレビューして", "コメントやドキュメントとの乖離を見て", "リファクタリングの観点で見て", "design review", "review the design" — or via the /review-design command. Not for finding bugs (code-review), reviewing test code (review-test), or line-level cleanups (simplify).
effort: high
allowed-tools: Read, Glob, Grep, Bash(git diff *), Bash(git log *), Bash(git show *), Bash(git merge-base *), Bash(git status *), Bash(git rev-parse *)
---

Review the design of a change at an implementation breakpoint and report what to tidy, ranked P1/P2/P3.

**Every run writes its report out to the user** — a requested review before anything is changed; a review it started itself at the top of its closing message, once its fixes are committed. A review folded silently into the work is one the user never sees.

**Match the user's language.** Answer a Japanese request in Japanese, an English one in English. Quote code, file paths, and command output verbatim.

**Boundary of this skill: reading only.** Never edit a file, never run tests, never run `gh`. Run git only to read — `git diff`, `git log`, `git show`, `git merge-base`, `git status`, `git rev-parse` — and never with `--output`, which writes to a file. Never `git add` / `commit` / `stash` / `checkout` / `switch` / `reset` / `restore` / `push`. Acting on the findings happens outside the skill (see "After the review").

**Why read-only git is in `allowed-tools`, when review-test keeps `Bash` out.** The range under review is the input of every run, so the reading commands are pre-approved by prefix. A prefix rule matches the raw command string, though: `Bash(git diff *)` also matches `git diff --output=<file>`, which is why that flag is named above.

**The boundary is this skill's own contract, not something the host enforces.** Some hosts ignore `allowed-tools` outright — Codex reads only `name` and `description` — and there the writing git commands above may already be pre-approved and run without confirmation. **The absence of a prompt is not permission.**

## When to start

Beyond an explicit request, **start at an implementation breakpoint, even if no one asked.** A breakpoint is the end of a unit of work — a plan step, a task, a request — with its tests passing and its commits made: the moment before reporting it back to the user, or before starting the next unit.

- **Start** at a breakpoint when, since the last review, the work has
  - added or changed an interface (Phase 2 lists what counts: an exported function or type, a command's arguments, flags or output, an environment variable, a configuration key, a file format, a new module or script), or
  - grown past about 200 changed lines outside tests.
- **Start** before `create-pr` as well, if part of the branch has not been reviewed yet.
- **Don't start**:
  - after every commit — one unit of work often spans several
  - in the middle of a unit: tests failing, the work half done
  - for a change to tests, docs, configuration or formatting alone
  - for a small fix that changes no interface; the next breakpoint reviews it
  - for the commits this skill's own follow-up made
  - when the user has said a review is unnecessary

**The trigger decides when; the range decides what.** The range runs from the last review (Phase 1), so a change that started no review is still in the next one: skipping a breakpoint delays a review, it never loses one.

**Started by itself, it reports at the top of the closing message.** Do the review, apply and commit the fixes ("After the review"), then open the closing message — before the summary of the unit — with the report in a short form of three parts:

- the heading line exactly as in Phase 5 (`## Design review: <base>..<head>`, translated), naming the range that was reviewed — the unit's commits, not the fixes
- one line per finding: its priority, what it is, and what was done about it — or, with nothing found, one line naming what was checked
- the `Reviewed:` line, with the same range

Nobody asked for this review, so this is the only way the user learns what it found and why the commits after the unit exist.

Do not leave this condition to the caller's configuration alone (a `CLAUDE.md` or equivalent). Hosts that read nothing but `name` and `description` still have to trigger, and so does any repository whose configuration this skill never sees.

## Why at a breakpoint

Two prices start rising once a unit of work is done.

- **An interface is cheapest to change while its only callers are the ones just written.** Each caller, doc and test added afterwards raises the price, and once something outside the change depends on it, changing it needs someone's agreement.
- **A doc that disagrees with the code is cheapest to fix while it is still known which side is right.** At a breakpoint the code was just changed on purpose, so the doc is the side to fix. Later, deciding which of the two is wrong takes archaeology.

## After the review

This skill changes no files while it runs, per the boundary above. After a requested review, the caller — the same agent in the same turn — takes over once the report is out, and not before. After a review it started itself, the caller takes over as soon as the review is done, and the report follows the fixes ("When to start"). Either way the caller carries on without stopping. The order, then:

- **requested**: report (Phase 5) → tests → fixes → tests → commit
- **started by itself**: tests → fixes → tests → commit → the report atop the closing message

1. **Fix the P1 and P2 findings of the first report whose reach is local, without asking first** (see "Reach" below). The report is not the deliverable; code and docs that agree, and interfaces that hide what they should, are. Reporting and stopping leaves every P1 in place, and asking permission to act on a review the caller already asked for is the failure this step exists to prevent.
2. **For drift, fix the doc, not the code.** Rewriting a doc's old promise — and the reason it gave — is not changing a requirement: the commit already changed it, and the doc is catching up. If the code looks like what is wrong, that is a question for "Outside this review", not a fix.
3. **For structure, change the code's shape and nothing it does.** Work in small named refactorings — Inline Function, Move Function, Change Function Declaration, Split Phase — and prefer deleting a layer to adding a better one. A missing seam is added the same way: Introduce Parameter, with the old source as its default, so every existing caller behaves as before.
4. **Keep behavior where it is.** Run the tests before and after. The tests of what callers see must pass unchanged — a new test beside them, say for a function the fix extracted, changes nothing they expect; a fix that would change what such a test expects is not a tidying — stop and report it. The one exception is a test the fix's seam was for: it may move onto the seam, asserting the same behavior with a fixed input in place of the clock or the environment.
5. **Commit the fixes on their own, after the commits of the unit of work.** Never amend them into those commits or fold them in: the review is what justifies the fix, and folding it in hides that. This is the caller's step — the skill runs no git that writes.
6. **Review again, for at most three rounds, until no P1 is left.** Stop on the same terms when one finding survives two rounds, and report what is left: an LLM's findings wobble, and grinding on them is not convergence.
7. **The loop gate is P1 only.** P2 raised by a later round is reported, not chased. **Never auto-fix P3**; report it.

What is left for the user to decide is what "Outside this review" asks, and any fix whose reach crosses the range — nothing else.

### Reach

Who a fix touches decides whether it needs anyone's agreement, whatever its priority.

- **Local**: every caller of what the fix changes is inside the range (Phase 2), and nothing published depends on it. An interface born in this range is local — nothing has started depending on it yet. A fix to a doc or a comment is always local.
- **Crossing**: a caller lies outside the range; or the fix touches a published contract — a command-line flag people type, a configuration key or environment variable in someone's setup, a file or message format already written somewhere, behavior documented to users, an API another repository imports; or the fix undoes a structure the stated intent asked for, such as a layer the commit says it added on purpose. Undoing what someone decided is their call, however shallow the result.

Apply a local fix without asking. Propose a crossing fix with what it would touch and wait for an answer; where nobody can be asked — a non-interactive run — leave it unapplied and list it as awaiting a decision.

## Procedure

Five phases, in this order.

### Phase 1: Scope

1. **Find the range.**
   - If the caller named one, use it.
   - If this skill already reviewed part of this branch earlier in the conversation, start from the head on that report's closing line (`Reviewed: <base>..<head>`), so finished work is not reviewed twice.
   - Otherwise, from the merge-base with the default branch to `HEAD`. Find the default branch with `git rev-parse --abbrev-ref origin/HEAD`; without a remote, use `main`, then `master`.
   - On the default branch itself, where that merge-base is `HEAD` and the range would be empty, take the commits of the unit of work just finished, which the conversation knows. With no such context, ask which commits to review.
   - Uncommitted changes (`git status --short`) belong to the work too. Include them, and say so in the report: a fix made now will share their commit.
2. **Read what the change meant to do**: the commit messages in the range (`git log`), and the plan, issue or conversation it came from. Note what comes next as well, if the plan, the task list or the conversation says — Phase 4 weighs the structure against it. Do not invent one.
3. **List the changed files** (`git diff --stat`). If the range changes nothing a caller or a reader depends on — formatting, a lockfile, tests alone — say so in one line and stop.

### Phase 2: Interfaces

List every interface the range creates or changes. An interface is anything another piece of code or a person depends on: exported functions and types; a command's arguments, flags, exit status and output; environment variables it reads; configuration keys; file and message formats; a new module or script that others will source or call.

For each, write one sentence from the caller's side — what it does, not how — using only its signature, its comment and its docs. **Write it before reading the implementation.** The reviewer is usually the one who wrote the code, and reading the implementation first lets intent fill in what the interface fails to say.

Then find its callers (Grep), tests included, and split them by file. A caller is **inside the range** when the range changes the file that makes the call; otherwise it is **outside**, even when its behavior changed through what it calls, because nothing in this change touched it. Decide it by looking each caller's file up in the `git diff --stat` list from Phase 1 — never from whether its behavior changed. The outside ones are who a change to the interface would reach.

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

### Phase 4: Structure

Weigh each interface from Phase 2 by what it hides against what it asks its callers to know. A deep module offers a small interface over a lot of work; a shallow one makes its callers learn nearly as much as it does. These red flags (Ousterhout's) name what to look for:

- **Shallow module** — the interface is nearly as complex as what it hides.
- **Pass-through** — a function that only forwards to another with a similar signature; a layer that adds no abstraction of its own.
- **Information leakage** — one design decision (a format, a rule, an ordering) written down in more than one place.
- **Temporal decomposition** — code split by the order things happen rather than by what each piece knows.
- **Overexposure** — callers must learn rarely used details to do the common thing.
- **Special-general mixture** — a special case built into a general mechanism, such as a flag that switches behavior.

The cheapest evidence is in the callers: when each one repeats the same preparation or clean-up around a call, the complexity was pushed up to them instead of pulled down into the module.

**Testability.** Each behavior an interface promises should be reachable through the interface alone. Look for:

- an input that varies between runs — the clock, randomness, an environment variable, the working directory or `$HOME`, global state, a hard-coded path, the network — read deep inside the logic instead of entering at a seam, "a place where you can alter behavior in your program without editing in that place" (Feathers). A parameter with a default, or a value read once at the edge, is enough of one.
- decision logic that is not trivial, tangled with I/O a test can only stage.
- the tests themselves: one that recomputes the clock, sleeps, reaches into internals or needs elaborate setup to reach a single behavior is the interface saying it is hard to use.

**Change cost.** When the next change is known (Phase 1, step 2), walk it through the code as it now stands and list the places it would touch. One decision to edit in several places, or structure the change would have to move first, is preparatory work worth doing now — Beck's test is whether cost(tidying) + cost(change after tidying) < cost(change without tidying). This is the case where adding a function or a layer earns its place: the next change is the change it makes cheaper. With no next change known, judge only by what the code itself shows.

### Phase 5: Report

For a requested review, write the report as text to the user before your next tool call — a message of its own. A review that started itself puts the short form from "When to start" at the top of its closing message instead. The full format: Translate the headings into the language of the report, but keep the `Reviewed:` line that closes it exactly as shown: the next run of this skill reads it.

```
## Design review: <base>..<head> (<N> commits[, plus uncommitted changes])

### Interfaces
- `<signature>` — <one sentence from the caller's side> (new | changed; callers: <n> inside the range, <m> outside)

### P1
- **<what is wrong>** `<file:line>`: "<quoted text>"
  - Contradicts (drift only): `<file:line>` <what the code does instead>
  - Cost: <who is misled into doing what, or which change gets harder>
  - Fix: <small named steps> — reach: local | crossing (<what it would touch>)

### P2
- ...

### P3
- ...

### Outside this review
- <a question about behavior for the user; a suspected bug, a test-quality issue or a line-level cleanup, with the skill that covers it>

Reviewed: <base>..<head>
```

Drop any section with nothing in it. If nothing is worth a finding, say so under the heading and list, under `### Checked`, what was checked: each doc and comment and the code it was compared with, and each red flag looked for and where. "No findings" alone cannot tell a clean change from an unread one. Still end with the `Reviewed:` line. Write abbreviated commit hashes there and in the heading, never a branch or tag name: names move, and the next session may not have them.

**For a requested review, write the report first.** Nothing is edited, run or committed until it is out — the fixes answer to it. **The report does not end the turn either.** After the `Reviewed:` line, go straight on to "After the review". A self-started review reports at the end instead, but its range is still the one it reviewed, never the fixes that came after.

## Findings

Every finding carries all four of these. A candidate missing one is not reported.

1. **What is wrong**, named: a stale comment or doc, a name that no longer fits, a missing why, or a red flag from Phase 4.
2. **Evidence**: `file:line` and the quoted text — and for drift, the code it contradicts.
3. **What it costs if it stays**: who gets misled into doing what, or which change it makes harder. A candidate that can name neither is a matter of taste; drop it.
4. **The fix**, as small named steps a reader could check one by one, and its reach.

## Where principles pull apart

Without a stance here, one round asks for what the last one undid.

- **Deep modules over small functions.** Do not suggest splitting a function for its length. Split only where it mixes levels of abstraction, holds concerns that change for different reasons, or hides a piece a test needs to reach on its own.
- **DRY is about knowledge, not text.** The same decision in two places is information leakage; report it. Code that merely looks alike is left until a third copy appears — duplication is far cheaper than the wrong abstraction. Copying one module's contract into another's comment is never a fix: it writes the same decision down twice.
- **Prefer deletion.** Removing a pass-through layer usually beats improving it. A fix that adds a layer, a parameter, an export or an option must name the change it makes cheaper; "more flexible" is not a change.
- **Small steps or not at all.** A fix that cannot be done as a short series of named refactorings within this breakpoint is a proposal, not a P1 or P2 fix.

## How to assign priority

P1/P2/P3 are **absolute criteria**, not a distribution. Classify by whether a finding meets the criterion; do not spread findings across the three, and do not manufacture a P1 for a change that is already good.

**A finding whose fix would change what the code does is not a tidying.** Rank it nowhere in P1–P3: put it under "Outside this review" as a question for the user — an edge case nothing decides, a behavior no doc or intent explains. That keeps "fix P1 and P2 without asking" from ever reaching behavior, so every P1 and P2 can be acted on without a decision.

**P1** — fix before the next unit of work starts. Any one of:

- A comment, doc, name or usage text states something about the code that is no longer true.
- An interface the range created or changed leaks an implementation decision its callers must know or repeat. Every caller written from now on will depend on it.
- A behavior an interface the range created or changed promises can be checked only against the wall clock, a real external resource, or the interface's internals.
- The next planned change would have to edit one decision in more than one place, or move structure first, and a short series of named refactorings now would bring it down to one place.

**P2** — fix now; it decides how long the code stays cheap to read and change. Any one of:

- The range introduced a shallow module or a pass-through layer.
- The range split code by the order things happen, or built a special case into a general mechanism.
- The range wrote one decision down in more than one place, with nothing — no test, no cross-reference — tying them together.
- The range reads an input that varies between runs deep inside logic, with no seam to set it.
- A non-obvious constraint or decision the range introduced has no comment saying why.
- An interface comment describes implementation detail its callers do not need.
- A comment only repeats what the code beside it already says.

**P3** — an improvement, the user's call.

- Wording that could be sharper; a doc that could be organized better; a second design for an interface that might be worth trying next time.
