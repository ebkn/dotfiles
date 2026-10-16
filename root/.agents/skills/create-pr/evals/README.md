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
| `ready-without-pr` | update-pr | `/update-pr ready` on a finished branch whose PR was never opened: it hands over to create-pr, which pushes and opens it ready |

Every case also grades the question this set out to remove, three ways: the
`AskUserQuestion` tool, the closing message against the phrasings runs used
(`PR_EVAL_ASKS`), and a judge on the closing message for the rest.

**GitHub is a fake** (`bin/skill-eval-github.sh`): `origin` is a bare
repository inside the fixture's `.git/`, and `gh` a stub that keeps one PR per
branch as JSON. A run opens nothing anywhere. Two things the first runs
taught about it:

- **origin's URL has to be a GitHub one.** With a local path there, a run read
  `git remote -v`, concluded there was no GitHub origin, and — following the
  rule — published nothing. git now reaches `git@github.com:example/fixture.git`
  through an ssh stub (`core.sshCommand`) that serves the bare repository.
- **The cases allow `gh pr list` and `gh pr view`**, as the user's own
  settings do. A run checking for an open PR before `update-pr` was refused
  `gh pr list`, took the refusal to cover every `gh` and push, and stopped.

**The requests are documentation changes on purpose.** With `root/CLAUDE.md`
in, a change to tests or an interface would also start `review-test` and
`review-design`, which the fixture does not carry; a doc change starts
neither.

## Last measured

2026-10-16, sonnet, three runs per case, on the final harness. The baseline
is the same harness and cases with the behaviour commit reverted.

| Case | before | after |
| --- | --- | --- |
| `draft-at-first-commit` | 0/3 | 3/3 |
| `ready-in-one-commit` | 0/3 | 3/3 |
| `ready-at-finish` | 0/3 | 3/3 |
| `no-pr-on-default-branch` | 3/3 | 3/3 |
| `no-update-without-commits` | 3/3 | 3/3 |
| `ready-without-pr` | — | 3/3 |

`ready-without-pr` came with the hand-over itself (update-pr starting
create-pr when `ready` finds no PR), so it has no before. Its first three
runs published the PR every time and still failed: the grader looked for a
Skill call starting update-pr, and `/update-pr ready` in a `claude -p`
prompt expands in place with none. The hand-over is now placed after
update-pr's own `gh pr view`. The last full run of all six cases, after the
fixes from review-test (whole-word keywords, the stub's `--flag=value`, every
branch on origin), was 18/18.

Before, no run pushed or opened a PR, and none asked either: in these
unattended runs the question did not show up, so the "never ask" half is
held, not shown to have changed. Three things on the way there were found
by these runs:

- **`git log @{upstream}..HEAD` stopped every `ready-at-finish` run.** Claude
  Code reads the braces as brace expansion and asks for approval even where
  `git log` is allowed. Both skills now push with `git push -u origin HEAD`
  and no check.
- **"Once the first commit lands" was read as "once the request is
  committed"**: two of three runs committed both requests, then opened one
  ready PR. `root/CLAUDE.md` now says right after the first commit, before
  going on.
- **`create-pr` was started on a branch that already had a PR** (two of three
  runs), relying on the caller to have checked. It now checks with
  `gh pr view` and hands over to `update-pr`.

The judge once failed a run with a reason saying the text passed: the schema
put `pass` before `reason`, so the verdict was written first. It is now the
other way round (`bin/skill-eval-assert.sh`).

Not measured yet: a fixture with no GitHub `origin`, a PR whose push or
`gh` call is refused, and the same cases without `root/CLAUDE.md` (whether the
skills' descriptions alone start them).
