# lint-docs evals

Run with `bin/skill-eval lint-docs` ([bin/skill-eval.md](../../../../../bin/skill-eval.md)).
This file sits in `evals/` on purpose: the runner strips the directory from the
copy of the skill a run sees.

The cases answer two questions separately, because a pass on one says nothing
about the other.

## Does each check catch what it claims

Started by name (`/lint-docs ...`), so starting is not what they measure.

| Case | Step of SKILL.md | What would make it fail |
| --- | --- | --- |
| `detects-each-category` | 3, 4, 6 | a category from the description missing from the report; a section B finding adopted without counting; any write |
| `excludes-english-docs` | 1 | an English document, the hiragana trap among them, reaching `textlint-docs`; the report not saying how many were left out |
| `prh-direction-reversed` | 4, 5 | the dictionary's サーバー applied in a project that writes サーバ; the diff not read after fixing |

`detects-each-category` plants one finding per category on its own line
(`lib.sh` lists them). **Line 18, `ことができる`, was at first one no rule
reported**: `ja-no-redundant-expression` is disabled in
`textlint/textlintrc.yml`, while the description promises 冗長表現. That case
failed 4 of 4 (below), and the local `ja-no-redundant-phrase`
(`textlint/rules/`) now reports it.

**Each planted finding was confirmed against the real toolchain** (2026-10-20,
`textlint-docs` on each scaffold's output): every line is reported (line 18
since the local rule),
`docs/ops.md` is clean, and both English documents of `excludes-english-docs`
yield `sentence-length` and `max-comma` findings. Phrasings that looked like
violations and were not: `画期的` / `劇的` (not in `no-ai-hype-expressions`'s
word list) and `次のとおり:` (`no-ai-colon-continuation` accepts a noun before
the colon). `assert.test.sh` cannot re-check this — CI has no textlint — so a
rule bump in `textlint/package.json` needs it redone by hand.

## Does it start on its own

| Case | Request | Expected |
| --- | --- | --- |
| `fires-on-trigger-phrase` | the description's own words, skill unnamed | starts |
| `fires-on-paraphrase` | same doc, words the description does not list | starts |
| `no-fire-english-doc` | proofread an English README | does not start |
| `after-writing-ja-doc` | write a Japanese doc; checking it is not asked | starts after writing, fixes only that doc |
| `after-adding-ja-section` | add a section to a Japanese doc, by Edit | starts after the Edit, fixes only that doc |
| `no-fire-small-ja-edit` | change 2 台 to 3 台 in a Japanese doc | does not start |

The two `fires-*` cases share fixture and grader by `exec`, so a difference
between them is the wording's. The last three are "## いつ起動するか": a
document written by Write, a section by Edit, a few characters by Edit. Two
cases alone would also split on the tool, so a model that started only after
Write would pass them; `after-adding-ja-section` is there to separate the size
of the change from the tool that made it.

**Graders read `git diff` with `--no-ext-diff`.** A `diff.external` in the
grading machine's git config replaces the unified diff. The first
`after-adding-ja-section` grader read `+` lines from it and failed a good run.

No case brings in `root/CLAUDE.md`: it says nothing about this skill, so the
description is the only thing that can start it.

## Last measured

**After the three fixes, 2026-10-20, sonnet, three runs per case.** The local
`ja-no-redundant-phrase`, `Bash(git diff *)` in allowed-tools, and the
written-a-document trigger in the description and "## いつ起動するか":

| Case | Passed | What failed |
| --- | --- | --- |
| `detects-each-category` | 2/3 | one run refused reading `~/dotfiles/textlint/prh.yml` to tell section A from B (below); 冗長表現 reported in all three |
| `excludes-english-docs` | 3/3 | |
| `prh-direction-reversed` | 3/3 | |
| `fires-on-trigger-phrase` | 3/3 | |
| `fires-on-paraphrase` | 3/3 | |
| `no-fire-english-doc` | 3/3 | |
| `after-writing-ja-doc` | 3/3 | (3/3 again with the file-bound breakpoint check) |
| `after-adding-ja-section` | 3/3 | (added afterwards, by review-test) |
| `no-fire-small-ja-edit` | 3/3 | |

The description alone carries the written-a-document trigger: `root/CLAUDE.md`
was not needed, unlike `review-test`'s auto-start. Section A against B is still
open, as below.

**Before them, 2026-10-20, sonnet, four runs per case** (one, then three):

| Case | Passed | What failed |
| --- | --- | --- |
| `detects-each-category` | 0/4 | 冗長表現 (line 18) missing from all four reports; one run also refused (below) |
| `excludes-english-docs` | 4/4 | |
| `prh-direction-reversed` | 1/4 | `git diff` never read after fixing in three; they re-ran `textlint-docs` instead |
| `fires-on-trigger-phrase` | 4/4 | |
| `fires-on-paraphrase` | 4/4 | |
| `no-fire-english-doc` | 4/4 | |
| `after-writing-ja-doc` | 0/4 | never started, as the description predicts |

The graders were tightened after these runs (a project-wide count, the count
in the report, the diff read *after* the edit, an English answer that names
the overlong sentence). Re-graded on the saved transcripts, the transcript
checks gave the same verdicts for all 28.

What the numbers say about the skill, not the harness:

- **Starting is carried by the description.** Unnamed requests started it 8
  of 8, paraphrase included, and an English proofreading request 0 of 4.
- **Line 18 is reported only when the skill was not started by name**: both
  `fires-*` runs read in full flagged `ことができる` by eye; the four
  `/lint-docs` runs relayed textlint and nothing else. SKILL.md asks for no
  reading beyond the tool, so the description's 冗長表現 rests on chance.
- **Section A and B cannot be told apart.** Step 4 adopts section A as-is,
  but neither textlint's output nor SKILL.md says which section a rule is in.
  `再試行` (section A) was counted and then held back as if it were B in
  three of five runs whose report was read; one run tried to read `prh.yml`
  to find out, through a guessed `~/.local/bin/../../dotfiles/textlint/prh.yml`,
  and was refused. That refusal is the only one across all 28 runs. A check
  for it is not graded yet: the right answer is "adopt", which a regex on the
  report cannot separate from a mention.
- **A section B rule the project contradicts is handled.** All four
  `prh-direction-reversed` runs counted, kept サーバ and fixed 予め by `Edit`
  rather than a blind `--fix`; what fails there is only step 5.4.
