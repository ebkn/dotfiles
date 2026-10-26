---
name: session-summary
description: Write the closing message that hands finished work back to the user — what they asked for and why, what was done, what was done beyond the request, and, where it helps the review, the shape of what was built (files, interfaces, system design, UI output). Use it proactively, without being asked, as the last step of a request that changed files: once its commits are made, review-test and review-design have run with their fixes committed, and update-pr has marked the PR ready (or, with no PR to open, the commits are left local), so that all that is left is for the user to check the work. It replaces the free-form wrap-up summary. Not mid-request, not for a question answered or an investigation reported with nothing committed. On request too — "まとめて", "何をやったか教えて", "summarize what you did", "wrap up" — or via the /session-summary command.
allowed-tools: Bash(git status *), Bash(git log *), Bash(git diff *), Bash(git rev-parse *), Bash(gh pr view *), Read, Glob, Grep
---

Write the message that hands a finished request back to the user. It is the last thing they read before reviewing the work, often after hours away, so it has to stand on its own.

## Why this exists

The default wrap-up is a list of everything the session touched, in the order it touched it. A reader who has forgotten what they asked for cannot tell from it whether the request was met, what was added on top, or where to start reviewing. This message answers those, in that order, and nothing else.

## Boundary: reading only

This skill writes the closing message and changes nothing. Never edit a file, never run `git add` / `git commit` / `git push`, `gh pr create` / `gh pr edit` / `gh pr ready`. `git diff` and `git log` take no `--output`, which writes a file. The work is finished before this skill starts; if something turns out unfinished while you gather the facts, say so in the message (see "Left open") rather than fixing it here.

The boundary is this skill's own contract. Some hosts ignore `allowed-tools` — Codex reads only `name` and `description` — and pre-approve the git and gh commands above. **The absence of a prompt is not permission.**

## When to start

Start, without being asked, once a request that changed files is finished: the last commit made, the review loops over (`review-test`, `review-design`, their fixes committed), and the PR marked ready by `update-pr` — or, with no PR to open, the commits left local. The message this skill writes **is** the closing message; do not write another summary before or after it.

Don't start in the middle of a request, after each commit, or when nothing was changed — a question answered or an investigation reported needs no wrap-up beyond the answer.

This condition lives here as well as in the caller's configuration, because hosts that read only `name` and `description` still have to trigger.

## Gather the facts

The conversation is the main source: what the user asked, in their words, and every change of direction since. Then check what was actually delivered against the repository, not against memory of the session:

1. The base: `git rev-parse --abbrev-ref origin/HEAD` (strip `origin/`), falling back to `main`.
2. `git log <base>..HEAD` with full messages, and `git diff --stat <base>...HEAD` — three dots, from the merge-base: two dots compare against the base's current tree, so once the base has moved on its newer changes show up as if this branch had reverted them. On the default branch, take the commits this request made.
3. `git status --short` — anything uncommitted is reported, not hidden.
4. `gh pr view --json url,isDraft,title` when the branch has a PR.

Read a changed file only when the commit messages do not tell you its interface or role.

## The message

Write in the language the conversation runs in under the user's instructions. Keep each section to what a reviewer needs. Omit a section marked *(if any)* when it would be empty — do not write "none".

**Every fact goes in exactly one section.** A decision the user made belongs to section 1, a change to section 2 or 3, a limitation to section 5 — and nowhere else, not even as a reminder or a pointer back ("the two points above"). Before sending, check each line against the others: a line that says again what one elsewhere says goes.

If `review-test` or `review-design` ran in this request, their reports keep the place those skills give them, at the top of the closing message; this message follows them.

### 1. What you asked

Two to four lines. The request as the user put it — quote their key words — the goal behind it, and the approach that was planned. Add any decision the user made mid-way that changed the request ("then you asked to drop X"). The user has likely forgotten the details of what they asked for; this is the yardstick for everything below, so it comes first and is precise.

### 2. What was done

A short list, one line per outcome, written as what the user can now do or what now holds — a behaviour, a command, a test that now exists — not as the steps taken. Map each line back to the request. Anything asked for but not done, or done differently, goes here too, stated plainly with the reason.

Not here: a decision section 1 already gives ("the setting is called X" after the user chose X), commit hashes, a count of files, the state of the working tree. None of them is something the user can now do.

### 3. Beyond the request *(if any)*

What was not asked for: fixes from the reviews, docs brought in line, refactors, a bug noticed on the way, a dependency added, a sentence added to a doc. One line each, with why. This is the section a reviewer checks hardest, because nobody asked for it — so an unrequested change goes here only, never also under section 2.

### 4. How it is built *(if any)*

Only what the user needs to review the change without opening every file. Pick the parts that apply:

- **Files**: a tree of the added and changed files only, each with a few words on its role. Skip it for a one- or two-file change.
- **Interfaces**: the signatures, commands and flags, config keys, file formats or endpoints that callers see — exactly as written in the code, in a code block.
- **Design**: how the pieces connect, in a few lines or a small ASCII diagram, and the one or two decisions made during the work that shaped it, with the alternative turned down — not the ones the user gave, which section 1 holds.
- **Frontend**: what the user will see — a screenshot path or URL if one was taken, otherwise where and how to look at it.

This section describes what the change is, not where it falls short. A rule of the interface — which argument comes first, which values it accepts — is part of the interface and is stated here, once; section 5 does not repeat it. Something that does not work, is not handled or was not verified is a limitation, and goes to section 5 only. Skip the section entirely for a change whose shape the first two sections already make obvious.

### 5. Left open

Always present, one line per item: the PR URL (or that the commits are local), and anything the user must decide, verify or run themselves — a test that could not run here, a P3 finding, an open question, a gap noticed while gathering the facts. **Every limitation lives here and only here**: what does not work, is not handled, was not run or not verified, stated in full rather than pointed to. If nothing is left but the review, that one line is the section.

## Style

- Lead each line with the point; no preamble, no closing pleasantries, no restating the headings.
- Name files, commands and identifiers exactly, in backticks; link `file:line` where it saves the reader a search.
- State results plainly. Do not call something verified unless it was; say how it was verified when that is not obvious.
