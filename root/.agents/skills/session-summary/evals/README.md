# session-summary evals

Run with `bin/skill-eval session-summary` ([bin/skill-eval.md](../../../../../bin/skill-eval.md)).
`assert.test.sh` pins the graders without calling the API; CI runs it.

## The cases

| Case | Measures |
| --- | --- |
| `reports-finished-branch` | the message itself, started by name on a finished branch: the request and its change of direction first, the unrequested fix kept apart, the interface shown, what is left at the end, and no file from a main that moved on after the branch split off |
| `reports-unfinished-request` | the same branch, with a request it does not fully meet: Usage in README.md was asked for and no commit touches it, and the unrequested usage-error fix ends `… \| ./tally.sh`, which used to count stdin. The prompt names neither; the message has to find both from git |
| `proactive-with-claude-md` / `proactive-at-finish` | whether it starts by itself after the last commit, with `root/CLAUDE.md` or with the description alone — same prompt, fixture and grader |
| `no-fire-question` | that it stays out of an answered question |

The message is graded mostly by `check_llm`, because no regex can say "the
request comes before the work". What can be stated deterministically is
checked directly: the skill started once, nothing was written (tree, HEAD,
and every branch and tag by value), and `CHANGELOG.md` — on main only — is
never named.

Every case that writes a summary is also graded for **accuracy against the
commits**: the judge is handed `git log main..HEAD` and the merge-base
`--stat`, and fails a message that reports as done what no commit holds. A
rubric written beforehand knows only the fixture's intended state, and the
commonest fault of agent-written PR descriptions is exactly that — "describes
a change that was never made", 45% of the inconsistent ones, with those PRs
accepted 28% of the time against 80% (Gong et al., [arXiv
2601.04886](https://arxiv.org/abs/2601.04886)).

## Measured

2026-10-26, sonnet. First with the haiku judge and one general concision
rubric:

| Case | Passed | Notes |
| --- | --- | --- |
| `reports-finished-branch` | 1/4, then 3/3 and 2/2 | the misses were the fixture and the rubrics, not the skill (below) |
| `proactive-with-claude-md` | 2/4, then 5/5 and 2/2 | after the `root/CLAUDE.md` wording fix (below) |
| `proactive-at-finish` | 1/3 | the description alone does not carry the auto-start |
| `no-fire-question` | 3/3 | |

Those passes still repeated themselves, which the general rubric let through.
With one rubric per kind of repetition, judged by sonnet:

| Skill | `reports-finished-branch` | `proactive-with-claude-md` |
| --- | --- | --- |
| before (saved runs, re-judged) | 0/5 | 2/4 |
| every fact in one section | 1/3 | 3/3 and 3/3 |
| Left open drafted first, check before sending | 3/5 | — |

The 3/5 misses all state an interface rule (`--json` goes first) in how it is
built and its consequence (elsewhere it is a file name) in Left open — a
small repetition, left there rather than chased with more wording.
`proactive-at-finish` went 0/3 in the same round, and `no-fire-question` 3/3.

Then accuracy against the commits, and what the change ends (sonnet,
judged by sonnet):

| Skill | `reports-unfinished-request` | `reports-finished-branch` |
| --- | --- | --- |
| before | 0/3 — every miss the piped use | 2/2 |
| looks for what worked before and no longer does | 3/3 | 3/3 |

The accuracy check and the unfinished README passed every run of both, so
the skill did not invent work here; what it missed was the cost of a fix.
Every run called the usage error a cure for a hang, which is what the commit
message says, and none said that `… | ./tally.sh` used to count stdin. With
the piped use named in the prompt, the same skill found it 3/3 — so the case
does not name it.

**The auto-start rests on `root/CLAUDE.md`**, as `review-test`'s did: the
description alone started the skill in 1 run of 6. The case is kept as the
pair's control, not as a target: a failure there is expected until the
description changes.

## What the evals taught

- **A rule elsewhere in CLAUDE.md can end the request first.** The misses in
  `proactive-with-claude-md` all found no `origin` and wrote their own report
  at once: the PR rule said "say in the report that the commits are local",
  and Reporting Back's "the commits reported as local" read as if that report
  were the finish. Both now name `session-summary` as the writer of the
  closing message.
- **A fixture a careful summary can fault puts the fault in the message.**
  `--json` alone skipped the usage check, a quote in a path broke the JSON,
  and a commit message contradicted the request; runs reported each under
  Left open, which made it long, and the judge failed it. `assert.test.sh`
  pins the fixture free of all three.
- **A rubric must not be stricter than the skill.** "Concise" first counted
  the required restatement of the request as filler, then a flag named in two
  sections as repetition; "Left open in a few lines" failed a list of real
  open items. Each rubric now states the format it judges within.
- **A general rubric passes what a named one fails.** "No explanation written
  out twice" passed every run, though each repeated the user's decision or a
  limitation; haiku even called one "borderline" and passed it. Re-judging the
  saved runs against one rubric per observed failure turned them red before
  the skill changed, which is what made the skill fix measurable.
- **A rubric's example can be wrong.** The limitation rubric first listed
  "a flag only recognised in first position" as a limitation; it is how the
  interface is called. What the runs did wrong was say it twice.
- **Trying it found a bug before any case did:** a two-dot diff against a
  main that moved on listed main's new files as this branch's.
  `reports-finished-branch` is built around that trap.
