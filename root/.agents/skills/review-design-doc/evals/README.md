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
  reads wide -- the label anywhere in a `#` heading or a bold-only line, any
  line under it, bullet or prose -- because "no P1" on a clean doc fails open
  when a P1 goes unseen; `assert.test.sh` pins the shapes on both sides.
  **Ranking inline is a contract failure**: a list item that leads with its
  priority (`- **P1**: …`, `- [P2] …`) or a `| P1 |` table cell fails
  "ranks findings under priority headings", since the parser cannot see it.
- **The report reaches the user**: it is graded on the run's final response,
  so a forked skill's report left in its tool result is not one.
- **Report-only, all the way through.** No Edit, no Write, no commit, a clean
  tree, for a requested review. For a doc the agent itself wrote, nothing
  edits it after the review starts. A design doc records its author's
  decisions; a run that filled in a missing alternative or rollback plan would
  be writing decisions nobody made.
- **The report follows the language** of the request and the doc.

## Where the cases come from

Each defect is one the research behind the skill found named across several
sources (Google's design docs, the Rust RFC and Python PEP templates, the
Kubernetes KEP, Oxide's RFDs, Squarespace's "Yes, if", Nygard's ADRs, Larson,
Zhang). One shared doc, `lib.sh`, is written to be good by that standard; a
defect case plants one defect, swapping only the sections it touches -- one
for most, three for `unsupported-claims` (summary, context, risks) and two for
`hidden-uncertainty` (proposal, open questions).

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
| each defect case / `clean-doc-no-false-p1` | one planted defect (`assert.test.sh` checks the doc differs) |
| `mini-doc-no-template-demands` / `clean-doc-no-false-p1` | a small doc without the large one's sections |
| `missing-rollback` / `missing-rollback-en` | language, and asked by phrase instead of by name |
| `clean-doc-no-false-p1` / `clean-doc-no-false-p1-en` | language |
| `proactive-after-writing-doc` / `no-fire-readme-edit` | the document written is a design doc, or a README |
| `fires-on-phrase` / `no-fire-code-design-request` | "review my design doc", or "review the design" of a commit that adds code (`review-design`'s request, with a design doc lying nearby) |

The defect cases are started by name (`/review-design-doc <path>`), so they
measure what the review finds, not whether it starts; the trigger cases measure
that. Each defect case also checks the run stayed read-only and was refused
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
- Proactive starting with `root/CLAUDE.md` brought in: it says nothing about
  this skill yet, so there is no pair to compare.
- A design doc in a format other than Markdown in the repository.
