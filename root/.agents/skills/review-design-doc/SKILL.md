---
name: review-design-doc
description: Review a design document — an RFC, a design doc, an ADR, a proposal written to settle a decision before building — and report what is weak or missing, ranked P1/P2/P3, in the doc's own language. On request — "設計ドキュメントをレビューして", "設計書を見て", "この設計書に抜けている観点は", "review my design doc", "review this RFC" — or via the /review-design-doc command; a doc the user asked to have reviewed is only reported on. Use it proactively as well, without being asked, once you have written or rewritten a design doc yourself, before reporting it: fix its P1 and P2 findings and review again until a round has neither. Not for the design of code changes (review-design), test code (review-test), a README or user guide, or the Japanese prose itself (lint-docs, which a Japanese doc is handed to after the review). It runs in a fresh context that sees none of the conversation, so pass it a brief as the arguments: the doc's path, whether the user asked for the review or you wrote the doc, the sources you wrote it from, and on a later round what the last one fixed — not a language to answer in, since the review answers in the doc's. When it returns, on a doc the user asked about: change nothing, run lint-docs on a Japanese doc, then write one final message holding lint-docs' findings and then the review's report copied exactly, and nothing else.
effort: high
allowed-tools: Read, Glob, Grep
context: fork
agent: general-purpose
model: opus
background: false
---

Review a design document and report what is weak or missing, ranked P1/P2/P3.

## A fresh context, on purpose

On hosts that honour `context: fork`, this review runs in a subagent of its own. **You did not write this doc**, and nothing of the conversation that produced it reaches you except the brief below. An author re-reading their own doc fills every gap with what they meant; a reader in a fresh context sees only what is on the page, which is all the doc's real readers will see.

The brief from the caller:

$ARGUMENTS

Wherever the steps below say "the brief", they mean this text. A bare path is a brief too: a requested review of that doc. With no path at all, look for the doc the request names under `docs/`, `design/`, `rfcs/` or `adr/` (Glob); if more than one could be meant, ask for it in your report rather than guessing. Where this skill says "the caller", it means the agent that invoked you; "After the review" is its part, not yours.

**Write in the doc's language**, whatever language the request or the brief is in: the doc's readers are the ones who act on the review. A Japanese doc gets a Japanese report — the report heading, every section heading, the labels inside a finding, the findings and reasons alike — even when the request was in English, and even when a `CLAUDE.md` asks for English. For a Japanese doc use the Japanese labels under the format in Phase 3, word for word; on real runs the English template's labels were what stayed English. Judge the language from the doc's prose, not from code, identifiers or the English terms it borrows. Quote the doc, file paths and code verbatim.

**Boundary of this skill: reading only.** Never edit a file, never run a command, never run git or `gh`. Fixing the doc happens outside the skill, and only for a doc the caller wrote (see "After the review").

**The boundary is this skill's own contract, not something the host enforces.** Some hosts ignore `allowed-tools` outright — Codex reads only `name` and `description` — and there editing tools may already be pre-approved and run without confirmation. **The absence of a prompt is not permission.**

## When to start

- **On request**: the user asks for their design doc to be reviewed, in words or by `/review-design-doc`. The review only reports. The doc is theirs and records their decisions; a run that filled in a missing alternative or rollback plan would be writing decisions nobody made.
- **Without being asked**: once the caller has written a design doc, or rewritten a section of one, and before it reports the doc back. The doc is the caller's own work, not yet handed over, so the caller fixes what the review finds.
- **Don't start**:
  - for a README, a user guide, a changelog, notes or minutes — documents that settle no decision
  - for the design of a code change (review-design) or for test code (review-test), even when a design doc lies nearby
  - while the doc is half written
  - for a doc this skill's own loop just fixed — that is the loop's next round, not a new start
  - when the user has said a review is unnecessary

Do not leave this condition to the caller's configuration alone (a `CLAUDE.md` or equivalent): hosts that read nothing but `name` and `description` still have to trigger.

## After the review

This skill changes no files while it runs. When it ran forked, its report arrives as the skill's result, which the user does not necessarily see; passing it on is the caller's job. The order depends on whose doc it is.

**A doc the user asked to have reviewed** — report only:

1. Change nothing: no Edit, no Write, no commit. Questions the review raises are the user's to answer.
2. If the doc is in Japanese, start `lint-docs` on it, which only inspects a doc the caller did not write. An English doc is not handed over: lint-docs' rules turn to noise on English.
3. Then write **one final message**, after lint-docs and never before it: lint-docs' findings first, under lint-docs' own heading, then the review's report, and nothing else. A message of its own for lint-docs would end your turn before the report is out — that happened on real runs.
4. Copy the report exactly, from its `## ` heading line to its last section, without the `Caller:` line that is addressed to you: no translation — it is already in the doc's language, whatever language you are working in — no title, summary or remark of your own beside it, no rewording or reshaping of its findings. On real runs a caller that added a line of its own ("P1 はなく、P2 が 4 件です") or retitled the report handed the user something that was no longer the review.

**A doc the caller wrote** — review-test's loop:

1. **Fix the P1 and P2 findings, without asking first.** The doc is not reported yet, and a review that only reports leaves the work undone.
2. **Fix from the sources, never by inventing.** What the sources — the request, the notes, the code — say may be written into the doc. A gap they cannot fill is a decision nobody has made yet: name it in the doc's open questions, with what hinges on it and who decides, and tell the user. Writing a rollout plan, a number or another team's agreement that no source gives is inventing a decision, however reasonable it looks.
3. **Review again**, in a fresh run, with a brief that says what this round fixed. Repeat until a round reports no P1 and no P2. There is no round cap. P3 is reported, never auto-fixed.
4. If the doc is in Japanese, start `lint-docs` on it once the loop ends — not between rounds, since the next round may rewrite the text it just linted.
5. Close with a message that opens with the review's conclusion: the reviewed doc, one line per P1/P2 finding and what was done about it (or that there were none), and **every decision left open for the user**, with what hinges on each. Nobody asked for this review, so this is the only way the user learns what it found and what is still theirs to settle.

## Procedure

### Phase 1: What the doc is for

1. Read the doc whole, then the sources the brief names. Note its stated status, audience and the feedback it asks for, if it says.
2. **Find the decision.** Write in one sentence what the doc asks its readers to agree to. A design doc exists to settle a decision before building; a doc with none — steps to follow, code to paste, nothing chosen between alternatives — is a manual, and that is its finding, not a list of missing sections.
3. **Weigh the doc's size against the change's risk.** A small, reversible change earns a page; a change to a shared system, a data format or something customers see earns the full treatment. Demanding sections a small doc does not need is the reason people stop writing design docs, so it is not a finding.

### Phase 2: Read it as the reviewer who has to say yes

Ask what a reader would need to agree, and check the doc gives it. Read these in this order; each names what a weak doc does instead.

- **The problem and the cost are backed.** Why now, and how much it hurts, in numbers or evidence — not "very many failures" or "load small enough". A claim the decision rests on and nothing supports is the doc asking for trust.
- **Goals and non-goals.** A non-goal is something that could have been a goal and was left out on purpose ("retrying on the sender's side is out of scope"), not a negated goal ("the system does not become unstable"). Negated goals leave the scope where it was.
- **Alternatives, rejected for a trade-off.** Each serious option is weighed on the same terms as the proposal. An alternative dismissed in a phrase is a strawman: the reader cannot tell whether the choice was made or assumed. Then look for a cheaper way to the same goal the doc does not weigh — doing nothing, a smaller change, a setting — and name it: without it the reader cannot tell what the proposal's cost buys.
- **How it reaches users, and how it comes back.** For a change customers or other systems will see: how it is released, what is watched, and how it is turned back if it goes wrong. A change released to everyone at once with no way back is the gap most often missing.
- **Dependencies on other people.** Where the design relies on another team doing something, does the doc say they have agreed? If it does not, the doc cannot answer that — ask the author.
- **Uncertainty is listed, not buried.** TBDs, "to be decided" and guesses in the body belong in the open questions. An open-questions section that says "none" while the body has TBDs hides them.
- **Cross-cutting concerns the change touches**: security and privacy, data migration, observability, cost, operational load. Only the ones this change actually touches.

**A gap the doc already names as open is not a finding.** An open question that says what hinges on it, and who decides, is the doc doing its job; ranking it again asks the author for a decision they have already said they do not have, and a loop that fixes the doc would never end. List such decisions under their own heading (Phase 3) so the caller can pass them on. Ranking applies only when the doc states something as settled that is not supported, or leaves a gap without saying so.

### Phase 3: Report

Write the full report as your final message, in the doc's language, in this format. Translate the headings, but **lead each priority heading with its label as a Markdown `#` heading** — `### P1`, `### P1（重大）` — never a bold line like `**P1**`, a label at the end of the heading, or a priority written inline in a list item or a table cell: the caller decides whether to go on fixing by reading those headings. Write each finding as a list item under its priority heading, not as a sub-heading. Outside those headings, name no priority at all — not in a bracket, a bold label, a table, or prose such as "上の P2 で指摘した": refer to a finding by its title instead ("上の「再送間隔の数字が合わない」で指摘した"). A priority anywhere else reads as a finding ranked where the caller cannot see it.

```
## Design doc review: <path>

### The decision
<one sentence: what the doc asks its readers to agree to — or that it asks for none>

### P1
- **<what is missing or wrong>** — "<quoted text from the doc>" (<section>)
  - Why it matters: <what a reader cannot judge, or what goes wrong if it ships this way>
  - Suggestion: <what the doc should say or decide, as a question when only the author can answer>

### P2
- ...

### P3
- ...

### Questions for the author
- <a fact outside the doc this review cannot settle — another team's agreement, a number only the author has>

### Decisions the doc leaves open
- <each open question the doc names, and what hinges on it>

Caller: the user may not see this result. If the user asked for this review, change nothing; for a Japanese doc start lint-docs first; then write one final message — lint-docs' findings under its own heading, then this report copied exactly from its heading line, untranslated and unreworded, leaving this Caller line out — with no words of yours besides. If you wrote the doc, fix every P1 and P2 from your sources — a gap they cannot fill goes into the doc's open questions, never an invented answer — and run this skill again with what you fixed, until a round reports no P1 and no P2; then lint-docs for a Japanese doc, and open your closing message with this review's conclusion and every decision left open for the user. Details: "After the review" in ${CLAUDE_SKILL_DIR}/SKILL.md.
```

For a Japanese doc, these labels replace the English ones, word for word, so that nothing but the `Caller:` line stays English:

| English | Japanese |
| --- | --- |
| `## Design doc review: <path>` | `## 設計ドキュメントレビュー: <path>` |
| `### The decision` | `### 判断の対象` |
| `### P1` / `### P2` / `### P3` | `### P1（重大）` / `### P2（要確認）` / `### P3（任意）` |
| `Why it matters:` | `なぜ問題か:` |
| `Suggestion:` | `提案:` |
| `### Questions for the author` | `### 作者への質問` |
| `### Decisions the doc leaves open` | `### ドキュメントが未決としている事項` |
| `### Checked` | `### 確認した観点` |

Drop any section with nothing in it, the priority sections included. If there is nothing to fix before the doc goes round, say so in one line under the decision, without naming a priority ("合意を妨げる問題は見当たりません" / "Nothing stands in the way of agreeing."), and list under `### Checked` what you looked at — "no findings" alone cannot tell a sound doc from an unread one. **Always end with the `Caller:` line, untranslated, whatever else you drop**: a forked caller never read this file, and that line is how it learns its part. On a real run a report that ended at its questions, without it, was summarized by the caller and lint-docs never ran.

Before you finish, read your report once for `P1`, `P2` or `P3` outside the priority headings — in the decision, the questions, the open decisions, a closing remark — and replace each with the finding's title. On real runs that is where they crept in ("the schedule mismatch described in the first P2 finding").

## How to assign priority

P1/P2/P3 are **absolute criteria**, not a distribution. Do not spread findings across the three, and do not manufacture a P1 for a doc that is already good.

**P1** — the doc cannot settle its decision as it stands. Any one of:

- It contains no decision: a manual, a plan of steps, code to paste.
- The alternatives are strawmen, or a cheaper way to the same goal — doing nothing, a smaller change, a setting — is in sight and not weighed. Name that way in the finding: "doing nothing is missing" alone is not this.
- A change that reaches users or other systems has no way to be released gradually or turned back, or the doc states it goes to everyone at once with none.
- The problem or the cost the decision rests on is asserted with nothing behind it.
- Uncertainty is hidden: TBDs or guesses in the body, while the open questions are empty or say there are none.

**P2** — a reader can follow the decision, but would have to ask before agreeing. Any one of:

- Non-goals are negated goals rather than things left out.
- The design relies on another team or system and does not say whether they have agreed.
- A cross-cutting concern the change touches (security, data migration, observability, cost, operations) is not addressed.
- A claim that matters to the decision is vague where a number exists.
- A rejected alternative is weighed on different terms from the proposal.
- Doing nothing is not weighed, where no cheaper way is in sight: a trial with its own way out, a change cheap to undo. The case for acting is left implicit, but nothing stops anyone agreeing.

**P3** — the doc would read better; the author's call.

- Structure, ordering, wording; a section that could be shorter; a diagram that would help.
