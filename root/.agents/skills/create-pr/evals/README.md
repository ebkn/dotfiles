# create-pr and update-pr evals

Run with `bin/skill-eval create-pr` and `bin/skill-eval update-pr`
([bin/skill-eval.md](../../../../../bin/skill-eval.md)). The two skills share
one fixture (`lib.sh`), one set of graders (`grading.sh`) and one grader test
(`assert.test.sh`), all kept here; update-pr's cases source them.

What is measured is the publishing half of a unit of work, none of which the
prompts mention: a draft PR once the first commit lands, the PR brought up to
date and marked ready before the work is reported back, and no question about
pushing or opening a PR at any point. That behaviour rests on `root/CLAUDE.md`
as much as on the two skills, so every case brings it in (`claude_md`) and
carries in the other PR skill and `commit` (`skills`).

| Case | Skill | Measures |
| --- | --- | --- |
| `draft-at-first-commit` | create-pr | two requests, committed one at a time: a draft PR between the first commit and the last, update-pr after the last, ready at the end |
| `ready-in-one-commit` | create-pr | one request: the PR ends ready, whether opened ready or readied by update-pr |
| `no-pr-on-default-branch` | create-pr | the same request on main: no PR, no push, no branch made for one |
| `ready-at-finish` | update-pr | a branch with a draft PR from an earlier session: no second PR, the body rewritten, ready at the end |
| `no-update-without-commits` | update-pr | the same branch, asked a question: nothing committed, so neither skill starts and the PR is left alone |

Every case also grades the question this set out to remove, three ways: the
`AskUserQuestion` tool, the closing message against the phrasings runs used
(`PR_EVAL_ASKS`), and a judge on the closing message for the rest.

**GitHub is a fake** (`bin/skill-eval-github.sh`): `origin` is a bare
repository inside the fixture's `.git/`, and `gh` a stub that keeps one PR per
branch as JSON. A run opens nothing anywhere.

**The requests are documentation changes on purpose.** With `root/CLAUDE.md`
in, a change to tests or an interface would also start `review-test` and
`review-design`, which the fixture does not carry; a doc change starts
neither.

Not measured yet: a fixture with no GitHub `origin`, a PR whose push or
`gh` call is refused, and the same cases without `root/CLAUDE.md` (whether the
skills' descriptions alone start them).
