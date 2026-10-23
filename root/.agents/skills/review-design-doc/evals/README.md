# review-design-doc evals

Run with `bin/skill-eval review-design-doc` ([bin/skill-eval.md](../../../../../bin/skill-eval.md)).
This file sits in `evals/` on purpose: the runner strips the directory from the
copy of the skill a run sees, so what is measured here stays out of the
model's reach, as the graders do.

**Written before the skill.** The cases state what `SKILL.md` has to achieve,
so the first version of it is written against them. Nothing here has been run
against a real model yet.

## The contract the cases read

What `SKILL.md` must keep, because `grading.sh` reads it:

- **A report heading with a colon, naming the doc**: `## Design doc review: <path>`,
  translated (`設計ドキュメントレビュー:`, `設計書レビュー:` and `Design Document Review:`
  are accepted too). A preamble without the colon does not count.
- **Findings under headings naming `P1`, `P2`, `P3`**; an empty one is dropped or says
  "なし" / "None" and nothing more. A judged finding counts only under P1 or
  P2: a mention under P3, or in passing, is not a finding raised. The parser
  reads wide -- the label anywhere in a `#` heading, or a bold-only line that
  is the label (`**P1**`), and any line under it, bullet, prose or a bold
  finding title -- because "no P1" on a clean doc fails open
  when a P1 goes unseen; `assert.test.sh` pins the shapes on both sides.
  **`SKILL.md` should still lead each heading with its label** (`### P1`,
  `### P1（重大）`), not use the wider shapes: the loop's stopping rule is
  graded on `transcript_skill_rounds`' `open` count (`bin/skill-eval-assert.sh`),
  which reads only label-first headings and takes a section opening with
  "なし" as closed. A `### 重大 (P1)` round would count as clean.
  **Ranking inline is a contract failure**: a list item that leads with its
  priority (`- **P1**: …`, `- [P2] …`), a `| P1 |` table cell, a line whose
  first word is one (`P1: …`, `【P1】…`, even "P1 に当たる…"), or any bold span
  naming one but the bare `**P1**` label (`**P1: 重大**`, `🔴 **P1**`) fails
  "ranks findings under priority headings", since the parser cannot see it.
- **A requested review's report reaches the user**: it is graded on the run's
  final response, so a forked skill's report left in its tool result is not
  one. The self-started loop is graded on its rounds instead, and its closing
  message owes only a conclusion about P1/P2 and the decisions left open.
- **A doc someone asked to have reviewed is only reported on.** No Edit, no
  Write, no commit, a clean tree. It is the user's doc and records their
  decisions; a run that filled in a missing alternative or rollback plan would
  be writing decisions nobody made.
- **A doc the agent wrote itself goes through review-test's loop**: the review
  starts unasked once the doc is written, the agent fixes the P1 and P2
  findings, reviews again in a fresh run, and stops on a round with neither
  (`review_loop_checks`). A gap its sources cannot fill is fixed by naming it
  as an open decision in the doc and telling the user, not by inventing the
  answer: the notes behind `proactive-after-writing-doc` say nothing about the
  release, and a doc that states a staged rollout as settled fails. So
  `SKILL.md` must not rank again a gap the doc already lists as open, or that
  loop never ends.
- **The report is in the doc's language**, whatever the request was written
  in (`answers-in-doc-language`). Judged on the review's own report: for the
  loop, every round's, since the caller's summary may follow a `CLAUDE.md`
  asking for English. "Japanese" means at least as many kana as ASCII words once quotes
  and paths are dropped (`rdd_is_japanese`), so an English review quoting the
  doc does not pass.
- **The readability of a Japanese doc goes to `lint-docs`**, started after the
  review's last round, so it lints text the review is done changing. On a
  user's doc it only inspects (its own boundary); on the agent's it fixes. An
  English doc is not handed over: lint-docs' rules turn to noise on English.
  Every case that reviews a doc carries lint-docs (`skills: lint-docs`), so
  leaving it out is a choice the run made. **The review's report goes in the
  message after lint-docs returns**: only the final response is graded, so a
  report written out before lint-docs -- the "report first" habit of
  review-test and review-design -- is an intermediate message and fails the
  heading check in every Japanese requested case.

## Where the cases come from

Each defect is one the research behind the skill found named across several
sources (Google's design docs, the Rust RFC and Python PEP templates, the
Kubernetes KEP, Oxide's RFDs, Squarespace's "Yes, if", Nygard's ADRs, Larson,
Zhang). One shared doc, `lib.sh`, is written to be good by that standard; a
defect case plants one defect, swapping only the sections it touches -- one
for most, three for `unsupported-claims` (summary, context, risks) and two for
`hidden-uncertainty` (proposal, open questions). `implementation-manual` is the
exception: a different document with no decision in it (`lib.sh`), so a
finding there cannot be traced to one change.

| Case | What it plants | Principle |
| --- | --- | --- |
| `strawman-alternatives` | alternatives dismissed in a phrase, no "do nothing" | alternatives are rejected for a trade-off, and the status quo is one |
| `negated-non-goals` | non-goals like "the system becomes unstable" | non-goals are things that could be goals and were left out, not negated goals |
| `missing-rollback` | released to everyone at once, no way back | the cross-cutting concern most often missing |
| `unsupported-claims` | "very many failures", "load small enough" | the problem and the cost are backed by numbers |
| `hidden-uncertainty` | TBDs in the body, "open questions: none" | uncertainty is listed, not buried |
| `dependency-unconfirmed` | relies on another team upsizing a DB, no word on their agreement | do the owners know? -- a question for the author, since the doc cannot answer it |
| `implementation-manual` | steps and code, no decision at all | a design doc exists to make a decision |
| `mini-doc-no-template-demands` | a one-page doc for a small change, without sections it does not need | depth matches risk; overloaded templates stop people writing docs |

## The cases come in pairs

| Pair | Differs in |
| --- | --- |
| each defect case / `clean-doc-no-false-p1` | one planted defect; for `implementation-manual`, the whole doc (`assert.test.sh` checks the doc differs) |
| `mini-doc-no-template-demands` / `clean-doc-no-false-p1` | a small doc without the large one's sections |
| `missing-rollback` / `missing-rollback-en` | language, and asked by phrase instead of by name |
| `missing-rollback` / `answers-in-doc-language` | the request's language alone (the doc stays Japanese), and asked by phrase |
| `clean-doc-no-false-p1` / `clean-doc-no-false-p1-en` | language |
| `proactive-after-writing-doc` / `no-fire-readme-edit` | the document written is a design doc, or a README |
| `proactive-after-writing-doc` / `proactive-with-claude-md` | `root/CLAUDE.md` brought in, where review-test's auto-start rule lives and this skill's is to |
| `fires-on-phrase` / `no-fire-code-design-request` | "review my design doc", or "review the design" of a commit that adds code (`review-design`'s request, with a design doc lying nearby) |

The defect cases name the skill in words ("review-design-doc スキルで <path> を
レビューしてください"), so they measure what the review finds, not whether it
starts; the trigger cases measure that. Not as `/review-design-doc <path>`:
under `claude -p` a forked skill started by slash command ends the run with its
own report, and the caller never gets the turn that starts lint-docs. Each defect case also checks the run stayed read-only and was refused
nothing.

## How the judged checks are built

A judged check reads **only the P1 and P2 sections**, cut out deterministically
(`rdd_open_text`), so the priority is graded by a regex and only the meaning
by the judge. A report with nothing under P1 or P2 fails without asking the
judge. Two exceptions: `dependency-unconfirmed` reads the whole report, since
a question to the author is as good an answer there as a ranked finding; and
`mini-doc-no-template-demands` asks the opposite question -- that nothing was
demanded -- so an empty P1/P2 passes it without the judge.

`assert.test.sh` pins every assertion offline: a good synthetic run per case,
then each assertion provoked, and a stub judge that fails on `JUDGE_FAIL` to
show each judged check reads the text it claims to -- and that P3 is not in it.
Whether each rubric is right only real runs can tell.

## Not measured yet

- Whether each finding cites the doc's text, and whether it names what the gap
  costs. The judge is told only to look for the finding.
- A doc whose stated status asks for one kind of feedback ("only the rollout
  risk") -- Squarespace's point that the review should match the stage.
- Whether the review keeps Japanese wording out of its own P1/P2 once
  lint-docs has it. Only that lint-docs ran is checked.
- Whether a fix the loop made is right, beyond the one gap the notes leave:
  the judge reads the doc for an invented release plan and nothing else.
- A design doc in a format other than Markdown in the repository.
